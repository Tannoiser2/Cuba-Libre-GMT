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
	emit_signal("state_changed")
	return state.current_card


func cards_left() -> int:
	return state.draw_deck.size()


## Risolve automaticamente la carta corrente (Propaganda o Evento con i bot).
func auto_resolve_current() -> Dictionary:
	if game_over or state.current_card == -1:
		return {"over": true}
	if state.current_card == 0:
		propaganda_played += 1
		var is_final := propaganda_played >= 4
		var res := propaganda.run({"final": is_final})
		for line in res.get("log", []):
			emit_signal("action_logged", "📣 " + String(line))
		if res.get("winner", "") != "":
			game_over = true; winner = res.winner
			emit_signal("action_logged", "🏆 Vittoria: %s" % winner)
		elif is_final:
			game_over = true
			emit_signal("action_logged", "🏁 Partita conclusa (4ª Propaganda)")
		emit_signal("state_changed")
		return res
	# Carta Evento: fino a 2 Fazioni Disponibili agiscono nell'ordine della carta (bot)
	var card: CardDef = game_def.card(state.current_card)
	var actors: Array = []
	for fid in card.faction_order:
		if state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) != CoinEnums.Eligibility.ELIGIBLE:
			continue
		if actors.size() >= 2:
			break
		var br := bots.take_turn(fid)
		for line in br.get("log", []):
			emit_signal("action_logged", "🤖 " + String(line))
		if br.get("action", "pass") != "pass":
			actors.append(fid)
	for f in game_def.factions:
		state.eligibility[f.id] = CoinEnums.Eligibility.INELIGIBLE if actors.has(f.id) else CoinEnums.Eligibility.ELIGIBLE
	emit_signal("state_changed")
	return {"actors": actors}


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
	_emit_result(res)
	return res


func run_event(number: int, side: String, faction: String, params: Dictionary = {}) -> Dictionary:
	var res := events.apply(number, side, faction, params)
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


func faction_color(fid: String) -> Color:
	match fid:
		"government": return Color("3a6ea5")
		"m26": return Color("c0392b")
		"directorio": return Color("d4ac0d")
		"syndicate": return Color("27ae60")
		_: return Color.WHITE
