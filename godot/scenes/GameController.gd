extends Node

## Singleton (autoload) che incapsula il motore di gioco e lo espone alla UI.
## Mantiene il modulo, lo stato e le classi di regole, ed emette segnali quando lo
## stato cambia, così che le viste possano aggiornarsi.

signal state_changed
signal action_logged(text: String, faction: String)
signal bot_decision(text: String, faction: String, trace: Array)

var module: CubaLibreModule
var game_def: GameDef
var state: GameState
var ops: CubaLibreOperations
var specials: CubaLibreSpecials
var propaganda: CubaLibrePropaganda
var events: CubaLibreEvents
var bot: CLCalixto   ## Unico sistema NP: Calixto (sostituisce i bot cap. 8)

## Sequenza di Gioco della carta Evento corrente (loop di turno giocabile).
var seq: SequenceOfPlay
var _turn_did_op := false
var _turn_did_special := false
var _turn_did_event := false

## Annulla (undo) a un livello: istantanea catturata prima dell'ultima azione eseguita.
var _undo: Dictionary = {}


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
	bot = CLCalixto.new(state, module)
	stats = {}
	build_deck()
	advance_card()
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
	# La partita non deve aprirsi con una Propaganda (primo turno vuoto + doppia pesca
	# con l'auto-avanzamento): se capita in cima, scambiala col primo Evento successivo.
	if not state.draw_deck.is_empty() and state.draw_deck[0] == 0:
		for i in range(1, state.draw_deck.size()):
			if state.draw_deck[i] != 0:
				state.draw_deck[0] = state.draw_deck[i]
				state.draw_deck[i] = 0
				break
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
	_undo = {}   # l'Annulla non attraversa il confine tra le carte
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


## La Fazione di turno gioca l'Evento della carta corrente: applica l'effetto e
## REGISTRA subito l'azione nella sequenza (l'Evento è l'intera azione della Fazione),
## così non può essere rigiocato. Restituisce {"ok", "error"}.
func play_event(side: String, params: Dictionary = {}) -> Dictionary:
	var A := CoinEnums.ActionType
	if seq == null or seq.pending_faction() == "":
		return {"ok": false, "error": "Non è il turno di nessuna Fazione"}
	if not seq.is_legal(A.EVENT):
		return {"ok": false, "error": "L'Evento non è un'azione legale in questo slot"}
	var n: int = state.current_card
	if n <= 0:
		return {"ok": false, "error": "Nessuna carta Evento corrente"}
	var fid := seq.pending_faction()
	var p := params.duplicate()
	p["faction"] = fid
	var res := run_event(n, side, fid, p)
	if not res.get("ok", true):
		return {"ok": false, "error": String(res.get("error", "Evento non eseguibile"))}
	seq.act(A.EVENT)
	_after_decision()
	return {"ok": true, "error": ""}


## La Fazione di turno Passa.
func seq_pass() -> bool:
	if seq == null or seq.pending_faction() == "":
		return false
	var fid := seq.pending_faction()
	if not seq.act_pass():
		return false
	emit_signal("action_logged", "%s Passa" % faction_name(fid), fid)
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
		emit_signal("action_logged", "⚠ Nessuna azione valida da concludere (esegui un'Operazione/Evento o Passa)", "")
		return false
	if not seq.act(t):
		emit_signal("action_logged", "⚠ Azione non legale in questo momento", "")
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


const _OP_IT := {"train": "Addestramento", "garrison": "Guarnigione", "sweep": "Perlustrazione",
	"assault": "Assalto", "rally": "Riorganizzazione", "march": "Marcia", "attack": "Attacco",
	"terror": "Terrorismo", "construct": "Costruzione", "build": "Costruzione"}
const _SA_IT := {"transport": "Trasporto", "air_strike": "Attacco Aereo", "reprisal": "Rappresaglia",
	"infiltrate": "Infiltrazione", "ambush": "Imboscata", "kidnap": "Sequestro",
	"subvert": "Sovversione", "assassinate": "Assassinio", "profit": "Profitto",
	"muscle": "Muscle", "bribe": "Corruzione"}

## Conteggio azioni (per statistiche/simulazioni).
var stats: Dictionary = {}


func _count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


func _bot_take_pending() -> void:
	var A := CoinEnums.ActionType
	var fid := seq.pending_faction()
	if fid == "":
		return
	var fname := faction_name(fid)
	# Scelta Evento (Calixto): se l'Evento è legale e conviene, giocalo.
	if seq.is_legal(A.EVENT) and state.current_card > 0:
		var ec := bot.event_choice(fid, state.current_card)
		if ec.get("play", false):
			var side: String = ec["side"]
			var eres := events.apply(state.current_card, side, fid)
			var etrace := ["Evento giocato dal bot (lato %s) perché migliora il margine" % side]
			etrace.append_array(eres.get("log", []))
			emit_signal("bot_decision", "%s → EVENTO (%s)" % [fname, side], fid, etrace)
			seq.act(A.EVENT)
			_count("event")
			return
	var can_full := seq.is_legal(A.OPERATION_WITH_SPECIAL)
	var can_op := seq.is_legal(A.OPERATION)
	var can_lim := seq.is_legal(A.LIMITED_OPERATION)
	if not (can_full or can_op or can_lim):
		emit_signal("bot_decision", "%s → PASSA" % fname, fid,
			["Solo Evento/Pass erano legali in questo slot e l'Evento non conveniva."])
		seq.act_pass()
		_count("pass")
		return
	var br := bot.take_turn(fid)
	var trace: Array = br.get("trace", [])
	if br.get("action", "pass") == "pass":
		emit_signal("bot_decision", "%s → PASSA (nessuna Operazione legale)" % fname, fid, trace)
		seq.act_pass()
		_count("pass")
		return
	var optype := String(br.get("action", ""))
	var did_sa: bool = br.get("special", false)
	# Tipo di azione: Op+SA solo se ha svolto un'Att.Speciale ed è legale; altrimenti Op (only).
	var t := A.OPERATION
	if did_sa and can_full:
		t = A.OPERATION_WITH_SPECIAL
	elif can_op:
		t = A.OPERATION
	elif can_lim:
		t = A.LIMITED_OPERATION
	elif can_full:
		t = A.OPERATION_WITH_SPECIAL
	var atype := "Operazione"
	if t == A.OPERATION_WITH_SPECIAL:
		atype = "Op+Att.Speciale"
	elif t == A.LIMITED_OPERATION:
		atype = "Op Limitata"
	var label := "%s: %s" % [atype, _OP_IT.get(optype, optype)]
	if t == A.OPERATION_WITH_SPECIAL:
		label += " + " + String(_SA_IT.get(String(br.get("special_type", "")), br.get("special_type", "")))
	emit_signal("bot_decision", "%s → %s" % [fname, label], fid, trace)
	seq.act(t)
	_count("op:" + optype)
	if t == A.OPERATION_WITH_SPECIAL:
		_count("sa:" + String(br.get("special_type", "")))


## Dopo una decisione (Op/Pass/Evento): aggiorna stato; a carta conclusa, chiude e pesca.
func _after_decision() -> void:
	_reset_turn_flags()
	state.recompute_all_control()
	module._refresh_victory_tracks(state)
	if seq != null and seq.is_done():
		seq.finish()
		emit_signal("action_logged", "— Carta conclusa —", "")
		advance_card()
		return
	emit_signal("state_changed")


## Pesca la carta successiva e risolve in automatico le eventuali Propaganda incontrate.
func advance_card() -> void:
	draw_next()
	var guard := 0
	while state.current_card == 0 and not game_over and guard < 6:
		guard += 1
		resolve_propaganda()
		if not game_over:
			draw_next()


func cards_left() -> int:
	return state.draw_deck.size()


## La prossima carta in cima al mazzo (-1 se mazzo vuoto). 0 = Propaganda.
func next_card() -> int:
	return state.draw_deck[0] if not state.draw_deck.is_empty() else -1


## Risolve automaticamente la carta corrente (Propaganda o Evento con i bot).
func auto_resolve_current() -> Dictionary:
	if game_over or state.current_card == -1:
		return {"over": true}
	if state.current_card == 0:
		return resolve_propaganda()
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


var _busy := false
var pace_delay := 1.1   ## Pausa (s) tra le mosse dei bot; regolabile dalla UI (≥ durata animazioni).


## Risolve la carta corrente con i bot facendo una PAUSA tra le mosse (per vederle una alla
## volta, con il flash), poi pesca la carta successiva.
func run_card_paced(delay: float = -1.0) -> void:
	if delay < 0.0:
		delay = pace_delay
	if _busy or game_over or state.current_card == -1:
		return
	_busy = true
	if seq == null:
		_start_card_sequence()
	var guard := 0
	while seq != null and not seq.is_done() and guard < 8:
		guard += 1
		_bot_take_pending()
		emit_signal("state_changed")
		await get_tree().create_timer(delay).timeout
	if seq != null:
		seq.finish()
	state.recompute_all_control()
	module._refresh_victory_tracks(state)
	if not game_over:
		advance_card()
	emit_signal("state_changed")
	_busy = false


## Gioca l'intera partita con i bot, a ritmo (pausa tra le mosse e tra le carte).
func run_full_game_paced(delay: float = -1.0) -> void:
	if delay < 0.0:
		delay = pace_delay
	if _busy:
		return
	if state.current_card == -1:
		draw_next()
	var steps := 0
	while not game_over and state.current_card != -1 and steps < 200:
		await run_card_paced(delay)
		await get_tree().create_timer(delay * 0.5).timeout
		steps += 1


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
	var tr := ""
	if c.translation != "":
		tr = "[i][font_size=11]%s[/font_size][/i]\n" % c.translation
	return "[b]#%d %s[/b]%s\n%s%s\nCarte rimaste: %d" % [c.number, c.title, tag, tr, order, cards_left()]


## Esegue un'Operazione per id e ne propaga il risultato/log.
## Cattura un'istantanea dello stato per consentire l'Annulla dell'ultima azione.
func _capture_undo() -> void:
	_undo = {
		"state": state.to_dict(),
		"seq": seq.snapshot() if seq != null else {},
		"did_op": _turn_did_op,
		"did_special": _turn_did_special,
		"did_event": _turn_did_event,
	}


func can_undo() -> bool:
	return not _undo.is_empty()


## Annulla l'ultima Operazione/Att.Speciale/Evento eseguito (un solo livello).
func undo_last() -> bool:
	if _undo.is_empty():
		return false
	state.load_dict(_undo["state"])
	if seq != null and not (_undo["seq"] as Dictionary).is_empty():
		seq.restore_snapshot(_undo["seq"])
	_turn_did_op = bool(_undo["did_op"])
	_turn_did_special = bool(_undo["did_special"])
	_turn_did_event = bool(_undo["did_event"])
	_undo = {}
	state.recompute_all_control()
	module._refresh_victory_tracks(state)
	emit_signal("action_logged", "↩ Annullata l'ultima azione", "")
	emit_signal("state_changed")
	return true


func run_operation(op_id: String, params: Dictionary) -> Dictionary:
	_capture_undo()
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
	else:
		_undo = {}   # azione fallita: niente da annullare
	_emit_result(res)
	return res


## Smista un'Attività Speciale verso il metodo corretto dell'oggetto specials dato.
func _dispatch_special(sp: CubaLibreSpecials, sa_id: String, params: Dictionary) -> Dictionary:
	match sa_id:
		"transport": return sp.transport(params)
		"air_strike": return sp.air_strike(params)
		"reprisal": return sp.reprisal(params)
		"infiltrate": return sp.infiltrate(params)
		"ambush_m26": return sp.ambush("m26", params)
		"kidnap": return sp.kidnap(params)
		"subvert": return sp.subvert(params)
		"ambush_dr": return sp.ambush("directorio", params)
		"assassinate": return sp.assassinate(params)
		"profit": return sp.profit(params)
		"muscle": return sp.muscle(params)
		"bribe": return sp.bribe(params)
	return {"ok": false, "error": "Attività speciale sconosciuta: %s" % sa_id, "log": []}


## Verifica (senza modificare lo stato) se un'Att.Speciale sarebbe legale ed efficace.
## Simula l'azione su una copia dello stato e ne restituisce l'esito.
func can_special(sa_id: String, params: Dictionary) -> bool:
	var copy := GameState.from_dict(game_def, state.to_dict())
	var sp := CubaLibreSpecials.new(copy, module)
	return bool(_dispatch_special(sp, sa_id, params).get("ok", false))


func run_special(sa_id: String, params: Dictionary) -> Dictionary:
	_capture_undo()
	var res := _dispatch_special(specials, sa_id, params)
	if res.get("ok", false):
		_turn_did_special = true
	else:
		_undo = {}   # azione fallita: niente da annullare
	_emit_result(res)
	return res


func run_event(number: int, side: String, faction: String, params: Dictionary = {}) -> Dictionary:
	_capture_undo()
	var res := events.apply(number, side, faction, params)
	if res.get("ok", true):
		_turn_did_event = true
	else:
		_undo = {}   # azione fallita: niente da annullare
	for line in res.get("log", []):
		emit_signal("action_logged", String(line), faction)
	emit_signal("state_changed")
	return res


func run_bot_turn(faction: String) -> Dictionary:
	var res := bot.take_turn(faction)
	for line in res.get("log", []):
		emit_signal("action_logged", "🤖 " + String(line), faction)
	emit_signal("state_changed")
	return res


## Risolve la carta Propaganda corrente (Vittoria → Risorse → Supporto → azioni NP → Reset),
## gestendo conteggio (X/4), vittoria e Propaganda finale. Percorso UNICO e corretto.
func resolve_propaganda() -> Dictionary:
	if state.current_card != 0:
		emit_signal("action_logged", "⚠ La carta corrente non è una Propaganda", "")
		return {"ok": false}
	propaganda_played += 1
	var is_final := propaganda_played >= 4
	emit_signal("action_logged", "📣 Round Propaganda %d/4" % propaganda_played, "")
	# Fase Vittoria
	var vp := propaganda.victory_phase()
	if vp.get("winner", "") != "":
		game_over = true
		winner = vp.winner
		emit_signal("action_logged", "🏆 Vittoria: %s" % winner, winner)
		emit_signal("state_changed")
		return vp
	# Risorse, Supporto (Alleanza) e azioni di Supporto dei bot (Civica/Dimostrazioni/Espatriati)
	var plog: Array = []
	plog.append_array(propaganda.resources_phase())
	plog.append_array(propaganda.support_phase())
	plog.append_array(bot.propaganda_support())
	for line in plog:
		emit_signal("action_logged", "📣 " + String(line), "")
	if is_final:
		game_over = true
		emit_signal("action_logged", "🏁 Partita conclusa (4ª Propaganda)", "")
	else:
		propaganda.reset_phase()
	emit_signal("state_changed")
	return {"propaganda": true}


## Pulsante "Risolvi Propaganda": risolve e pesca la carta successiva.
func run_propaganda(_params: Dictionary = {}) -> Dictionary:
	var res := resolve_propaganda()
	if not game_over:
		draw_next()
	return res


func _emit_result(res: Dictionary) -> void:
	# La fazione che agisce (turno umano corrente) per colorare il log.
	var fac := seq.pending_faction() if seq != null else ""
	if res.get("ok", false):
		for line in res.get("log", []):
			emit_signal("action_logged", String(line), fac)
		emit_signal("state_changed")
	else:
		emit_signal("action_logged", "⚠ " + String(res.get("error", "errore")), "")


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
