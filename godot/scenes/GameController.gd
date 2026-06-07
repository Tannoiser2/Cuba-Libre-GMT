extends Node

## Singleton (autoload) che incapsula il motore di gioco e lo espone alla UI.
## Mantiene il modulo, lo stato e le classi di regole, ed emette segnali quando lo
## stato cambia, così che le viste possano aggiornarsi.

signal state_changed
signal action_logged(text: String)

var module: CubaLibreModule
var game_def: GameDef
var state: GameState
var ops: CubaLibreOperations
var specials: CubaLibreSpecials
var propaganda: CubaLibrePropaganda
var events: CubaLibreEvents
var bots: CubaLibreBots

## Sequenza di Gioco della carta Evento corrente (loop di turno giocabile).
var seq: SequenceOfPlay
var _turn_did_op := false
var _turn_did_special := false
var _turn_did_event := false


func _ready() -> void:
	new_game()


## Avvia una nuova partita con lo schieramento standard.
func new_game(scenario: String = "standard") -> void:
	module = CubaLibreModule.new()
	game_def = module.build_game_def()
	state = GameState.new(game_def)
	module.apply_setup(state, scenario)
	ops = CubaLibreOperations.new(state, module)
	specials = CubaLibreSpecials.new(state, module)
	propaganda = CubaLibrePropaganda.new(state, module)
	events = CubaLibreEvents.new(state, module)
	bots = CubaLibreBots.new(state, module)
	build_deck()
	draw_next()
	emit_signal("state_changed")


# ---------------------------------------------------------------------------
# Mazzo e loop di gioco
# ---------------------------------------------------------------------------

var propaganda_played: int = 0
var game_over: bool = false
var winner: String = ""

## Costruisce il mazzo: 48 Eventi divisi in 4 pile, 1 Propaganda mescolata in ciascuna.
## La Propaganda è rappresentata dal valore 0.
func build_deck(short: bool = false) -> void:
	var events_list: Array = []
	for i in range(1, 49):
		events_list.append(i)
	events_list.shuffle()
	if short:
		events_list = events_list.slice(0, 40)  # opzione gioco breve: 8 carte da parte
	var piles: Array = [[], [], [], []]
	for idx in range(events_list.size()):
		piles[idx % 4].append(events_list[idx])
	state.draw_deck.clear()
	for p in piles:
		p.append(0)  # carta Propaganda
		p.shuffle()
		for c in p:
			state.draw_deck.append(int(c))
	propaganda_played = 0
	game_over = false
	winner = ""
	state.current_card = -1


## Pesca la carta successiva (la mette come corrente). -1 = mazzo esaurito.
func draw_next() -> int:
	if state.draw_deck.is_empty():
		state.current_card = -1
	else:
		state.current_card = state.draw_deck.pop_front()
	_start_card_sequence()
	emit_signal("state_changed")
	return state.current_card


## Costruisce la Sequenza di Gioco per la carta Evento corrente (per il turno guidato).
func _start_card_sequence() -> void:
	seq = null
	_reset_turn_flags()
	if state.current_card > 0:
		var card: CardDef = game_def.card(state.current_card)
		seq = SequenceOfPlay.new(state, module, card)
		# Carta Evento finale (2.3.9): ultima carta del mazzo -> solo Operazioni Limitate.
		seq.final_event_card = cards_left() == 0


func _reset_turn_flags() -> void:
	_turn_did_op = false
	_turn_did_special = false
	_turn_did_event = false


## Stato della sequenza per la UI: chi è di turno, slot, azioni legali, conclusione.
func seq_status() -> Dictionary:
	if seq == null:
		return {"active": false}
	return {
		"active": true,
		"pending": seq.pending_faction(),
		"first_slot": seq.is_first_slot(),
		"legal": seq.legal_actions(),
		"done": seq.is_done(),
	}


## Vero se la Fazione di turno può svolgere solo un'Operazione Limitata (1 spazio, no Att.Speciale).
func seq_is_limited_only() -> bool:
	if seq == null:
		return false
	var A := CoinEnums.ActionType
	var legal := seq.legal_actions()
	return legal.has(A.LIMITED_OPERATION) \
		and not legal.has(A.OPERATION) and not legal.has(A.OPERATION_WITH_SPECIAL)


## La Fazione di turno Passa.
func seq_pass() -> bool:
	if seq == null or seq.pending_faction() == "":
		return false
	var fid := seq.pending_faction()
	if not seq.act_pass():
		return false
	emit_signal("action_logged", "%s Passa" % faction_name(fid))
	_after_decision()
	return true


## Conclude il turno della Fazione corrente, registrando l'azione svolta (Op/Op+SA/Evento).
func end_turn() -> bool:
	if seq == null or seq.pending_faction() == "":
		return false
	var A := CoinEnums.ActionType
	var t := -1
	if _turn_did_event:
		t = A.EVENT
	elif _turn_did_op:
		if _turn_did_special and seq.is_legal(A.OPERATION_WITH_SPECIAL):
			t = A.OPERATION_WITH_SPECIAL
		elif seq.is_legal(A.OPERATION):
			t = A.OPERATION
		elif seq.is_legal(A.LIMITED_OPERATION):
			t = A.LIMITED_OPERATION
		elif seq.is_legal(A.OPERATION_WITH_SPECIAL):
			t = A.OPERATION_WITH_SPECIAL
	if t == -1:
		emit_signal("action_logged", "⚠ Nessuna azione valida da concludere (esegui un'Operazione/Evento o Passa)")
		return false
	if not seq.act(t):
		emit_signal("action_logged", "⚠ Azione non legale in questo momento")
		return false
	_after_decision()
	return true


## Fa giocare il bot per la Fazione di turno e ne registra l'azione nella sequenza.
func bot_act_pending() -> bool:
	if seq == null or seq.pending_faction() == "":
		return false
	_bot_take_pending()
	_after_decision()
	return true


func _bot_take_pending() -> void:
	var A := CoinEnums.ActionType
	var fid := seq.pending_faction()
	if fid == "":
		return
	var br := bots.take_turn(fid)
	for line in br.get("log", []):
		emit_signal("action_logged", "🤖 " + String(line))
	if br.get("action", "pass") == "pass":
		seq.act_pass()
		return
	# Il bot svolge Operazione (+ Att.Speciale). Scegli il tipo legale più ricco.
	var t := A.OPERATION
	if seq.is_legal(A.OPERATION_WITH_SPECIAL):
		t = A.OPERATION_WITH_SPECIAL
	elif seq.is_legal(A.OPERATION):
		t = A.OPERATION
	elif seq.is_legal(A.LIMITED_OPERATION):
		t = A.LIMITED_OPERATION
	else:
		seq.act_pass()
		return
	seq.act(t)


## Dopo una decisione (Op/Pass/Evento): aggiorna stato; a carta conclusa, chiude e pesca.
func _after_decision() -> void:
	_reset_turn_flags()
	state.recompute_all_control()
	module._refresh_victory_tracks(state)
	if seq != null and seq.is_done():
		seq.finish()
		emit_signal("action_logged", "— Carta conclusa —")
		draw_next()
		return
	emit_signal("state_changed")


func cards_left() -> int:
	return state.draw_deck.size()


## Risolve automaticamente la carta corrente (Propaganda o Evento con i bot).
func auto_resolve_current() -> Dictionary:
	if game_over or state.current_card == -1:
		return {"over": true}
	if state.current_card == 0:
		propaganda_played += 1
		var is_final := propaganda_played >= 4
		# Fase Vittoria
		var vp := propaganda.victory_phase()
		if vp.get("winner", "") != "":
			game_over = true; winner = vp.winner
			emit_signal("action_logged", "🏆 Vittoria: %s" % winner)
			emit_signal("state_changed")
			return vp
		# Fasi Risorse, Supporto (Alleanza) e azioni di Supporto dei bot (Civica/Dimostr./Espatriati)
		var plog: Array = []
		plog.append_array(propaganda.resources_phase())
		plog.append_array(propaganda.support_phase())
		plog.append_array(bots.propaganda_support())
		for line in plog:
			emit_signal("action_logged", "📣 " + String(line))
		if is_final:
			game_over = true
			emit_signal("action_logged", "🏁 Partita conclusa (4ª Propaganda)")
		else:
			propaganda.reset_phase()
		emit_signal("state_changed")
		return {"propaganda": true}
	# Carta Evento: le Fazioni Disponibili agiscono (bot) secondo la Sequenza di Gioco.
	if seq == null:
		_start_card_sequence()
	var guard := 0
	while seq != null and not seq.is_done() and guard < 8:
		guard += 1
		_bot_take_pending()
	var acted: Array = []
	if seq != null:
		for f in seq.actors():
			acted.append(f)
		seq.finish()
	state.recompute_all_control()
	module._refresh_victory_tracks(state)
	emit_signal("state_changed")
	return {"actors": acted}


## Gioca automaticamente l'intera partita (tutti i bot) fino a fine mazzo o vittoria.
func run_full_game(max_steps: int = 200) -> void:
	if state.current_card == -1:
		draw_next()
	var steps := 0
	while not game_over and state.current_card != -1 and steps < max_steps:
		auto_resolve_current()
		if game_over:
			break
		draw_next()
		steps += 1


## Avanza: risolve la carta corrente e ne pesca una nuova.
func step_card() -> void:
	auto_resolve_current()
	if not game_over:
		draw_next()


func current_card_text() -> String:
	if game_over:
		return "Partita conclusa" + ("" if winner == "" else " — vince %s" % winner)
	if state.current_card == -1:
		return "Mazzo esaurito"
	if state.current_card == 0:
		return "[b]Carta Propaganda[/b] (%d/4)" % (propaganda_played + 1)
	var c: CardDef = game_def.card(state.current_card)
	var order := ""
	for fid in c.faction_order:
		order += "[color=#%s]●[/color] " % faction_color(fid).to_html(false)
	var tag := ""
	if c.is_capability: tag = " · Capacità"
	elif c.is_momentum: tag = " · Momentum"
	return "[b]#%d %s[/b]%s\n%s\nCarte rimaste: %d" % [c.number, c.title, tag, order, cards_left()]


## Esegue un'Operazione per id e ne propaga il risultato/log.
func run_operation(op_id: String, params: Dictionary) -> Dictionary:
	var res: Dictionary
	match op_id:
		"train": res = ops.train(params)
		"garrison": res = ops.garrison(params)
		"sweep": res = ops.sweep(params)
		"assault": res = ops.assault(params)
		"rally": res = ops.rally(params)
		"march": res = ops.march(params)
		"attack": res = ops.attack(params)
		"terror": res = ops.terror(params)
		"build": res = ops.build(params)
		_: res = {"ok": false, "error": "Operazione sconosciuta: %s" % op_id, "log": []}
	if res.get("ok", false):
		_turn_did_op = true
	_emit_result(res)
	return res


func run_special(sa_id: String, params: Dictionary) -> Dictionary:
	var res: Dictionary
	match sa_id:
		"transport": res = specials.transport(params)
		"air_strike": res = specials.air_strike(params)
		"reprisal": res = specials.reprisal(params)
		"infiltrate": res = specials.infiltrate(params)
		"ambush_m26": res = specials.ambush("m26", params)
		"kidnap": res = specials.kidnap(params)
		"subvert": res = specials.subvert(params)
		"ambush_dr": res = specials.ambush("directorio", params)
		"assassinate": res = specials.assassinate(params)
		"profit": res = specials.profit(params)
		"muscle": res = specials.muscle(params)
		"bribe": res = specials.bribe(params)
		_: res = {"ok": false, "error": "Attività speciale sconosciuta: %s" % sa_id, "log": []}
	if res.get("ok", false):
		_turn_did_special = true
	_emit_result(res)
	return res


func run_event(number: int, side: String, faction: String, params: Dictionary = {}) -> Dictionary:
	var res := events.apply(number, side, faction, params)
	if res.get("ok", true):
		_turn_did_event = true
	for line in res.get("log", []):
		emit_signal("action_logged", String(line))
	emit_signal("state_changed")
	return res


func run_bot_turn(faction: String) -> Dictionary:
	var res := bots.take_turn(faction)
	for line in res.get("log", []):
		emit_signal("action_logged", "🤖 " + String(line))
	emit_signal("state_changed")
	return res


func run_propaganda(params: Dictionary = {}) -> Dictionary:
	var res := propaganda.run(params)
	for line in res.get("log", []):
		emit_signal("action_logged", line)
	emit_signal("state_changed")
	return res


func _emit_result(res: Dictionary) -> void:
	if res.get("ok", false):
		for line in res.get("log", []):
			emit_signal("action_logged", String(line))
		emit_signal("state_changed")
	else:
		emit_signal("action_logged", "⚠ " + String(res.get("error", "errore")))


# --- Helper di lettura per la UI ---

func victory() -> Dictionary:
	return module.victory_status(state)


func faction_name(fid: String) -> String:
	var f := game_def.faction(fid)
	return f.name if f != null else fid


func faction_color(fid: String) -> Color:
	match fid:
		"government": return Color("3a6ea5")
		"m26": return Color("c0392b")
		"directorio": return Color("d4ac0d")
		"syndicate": return Color("27ae60")
		_: return Color.WHITE
