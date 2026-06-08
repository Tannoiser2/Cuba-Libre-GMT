class_name CLCalixto
extends BotBrain

## Bot Non-Giocatore "Calixto" per Cuba Libre. La DECISIONE (quale Operazione + Attività
## Speciale) è guidata dalle carte Calixto (dati + interprete generico); l'ESECUZIONE usa le
## classi Operazioni/Attività Speciali con una selezione spazi semplificata limitata dall'AN.
##
## NOTA: prima versione funzionante. La selezione spazi non usa ancora l'intera matrice
## Space Selection Priorities (C8.5.6); usa euristiche legali. Da raffinare.

var state: GameState
var mod: CubaLibreModule
var ops: CubaLibreOperations
var specials: CubaLibreSpecials

var _cards: Dictionary = {}
var _an_dice: Dictionary = {}
var deck: CalixtoDeck
var _log: Array = []
var _rng := RandomNumberGenerator.new()
var _af := ""   # Fazione attiva (per i predicati)

const LETTERS := {
	"government": ["U", "Y", "Z", "X", "W", "V"],
	"m26": ["G", "H", "J", "K", "L", "M"],
	"directorio": ["A", "B", "C", "D", "E", "F"],
	"syndicate": ["N", "P", "Q", "R", "S", "T"],
}


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module
	ops = CubaLibreOperations.new(p_state, p_module)
	specials = CubaLibreSpecials.new(p_state, p_module)
	_rng.randomize()
	_load_data()
	deck = CalixtoDeck.new(LETTERS, _rng)


var _ss := {}   # space_selection per fazione
var _events := {}   # Event Instructions per carta/fazione


func _load_data() -> void:
	var f := FileAccess.open("res://games/cuba_libre/data/calixto_cards.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_cards = d
			_an_dice = d.get("_an_dice", {})
	var ft := FileAccess.open("res://games/cuba_libre/data/calixto_tables.json", FileAccess.READ)
	if ft != null:
		var dt = JSON.parse_string(ft.get_as_text())
		if dt is Dictionary:
			_ss = dt.get("space_selection", {})
	var fe := FileAccess.open("res://games/cuba_libre/data/calixto_events.json", FileAccess.READ)
	if fe != null:
		var de = JSON.parse_string(fe.get_as_text())
		if de is Dictionary:
			_events = de.get("events", {})


# Colonna della tabella Space Selection da usare per ogni Operazione.
const OP_COLUMN := {
	"government": {"train": "place_cubes", "sweep": "sweep_dest", "assault": "remove_or_replace", "garrison": "garrison_dest"},
	"m26": {"rally": "place_guerrillas", "march": "march_dest", "attack": "attack", "terror": "shift_active_opposition"},
	"directorio": {"rally": "place_guerrillas", "march": "march_dest", "attack": "attack", "terror": "shift_neutral"},
	"syndicate": {"construct": "place_open_casinos", "rally": "place_guerrillas", "march": "march_dest", "terror": "shift_neutral"},
}


## Ordina i candidati secondo la matrice Space Selection (C8.5.6) per l'Operazione.
func _ordered(faction: String, op_type: String, candidates: Array) -> Array:
	return _ordered_col(faction, String(OP_COLUMN.get(faction, {}).get(op_type, "")), candidates)


## Ordina i candidati per una specifica colonna della matrice Space Selection.
func _ordered_col(faction: String, col: String, candidates: Array) -> Array:
	var tbl: Dictionary = _ss.get(faction, {})
	if col == "" or tbl.is_empty():
		return candidates
	var rows: Array = tbl.get("rows", [])
	# Righe applicabili a questa colonna (in ordine di priorità).
	var applicable: Array = []
	for row in rows:
		var cols: Array = row.get("cols", [])
		if cols.has(col) or cols.has("all"):
			applicable.append(String(row["crit"]))
	# Vettore-punteggio per ogni spazio; ordina decrescente lessicografico, pareggio casuale.
	var scored: Array = []
	for sid in candidates:
		var vec: Array = []
		for crit in applicable:
			vec.append(_crit_value(crit, sid, faction))
		scored.append({"sid": sid, "vec": vec, "r": _rng.randf()})
	scored.sort_custom(func(a, b):
		for i in range(min(a["vec"].size(), b["vec"].size())):
			if a["vec"][i] != b["vec"][i]:
				return a["vec"][i] > b["vec"][i]
		return a["r"] < b["r"])
	var out: Array = []
	for e in scored:
		out.append(e["sid"])
	return out


## Valore di un criterio per uno spazio (più alto = preferito). 0 se non applicabile.
func _crit_value(crit: String, sid: String, faction: String) -> float:
	var st: SpaceState = state.space_state(sid)
	var sd: SpaceDef = state.game_def.space(sid)
	match crit:
		"havana": return 1.0 if sid == "havana" else 0.0
		"city": return 1.0 if sd.type == CoinEnums.SpaceType.CITY else 0.0
		"province": return 1.0 if sd.type == CoinEnums.SpaceType.PROVINCE else 0.0
		"not_at_active_support": return 1.0 if st.support < CoinEnums.Support.ACTIVE_SUPPORT else 0.0
		"not_at_active_opposition": return 1.0 if st.support > CoinEnums.Support.ACTIVE_OPPOSITION else 0.0
		"gov_base_without_police": return 1.0 if st.count("government", "base") > 0 and st.count("government", "police") == 0 else 0.0
		"underground_guerrillas": return float(st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground") + st.count("syndicate", "guerrilla", "underground"))
		"most_support": return float(max(0, st.support) * sd.pop)
		"most_population": return float(sd.pop)
		"highest_econ": return float(sd.econ)
		"fewest_enemy_forces": return float(-_enemy_count(faction, st))
		"fewest_enemy_forces_ignore_closed_casinos": return float(-(_enemy_count(faction, st) - st.count("syndicate", "casino", "closed")))
		"enemy_base_open_casino":
			return 1.0 if st.count("m26", "base") + st.count("directorio", "base") + st.count("syndicate", "casino", "open") > 0 else 0.0
		"enemy_piece_with_cash":
			for e in ["government", "m26", "directorio", "syndicate"]:
				if e != faction and st.cash_for(e) > 0 and st.count(e) > 0:
					return 1.0
			return 0.0
		"open_casino": return 1.0 if st.count("syndicate", "casino", "open") > 0 else 0.0
		"open_casino_or_cash": return 1.0 if st.count("syndicate", "casino", "open") > 0 or st.cash_for("syndicate") > 0 else 0.0
		"syn_control": return 1.0 if st.control == "syndicate" else 0.0
		"underground_syn_guerrilla": return float(st.count("syndicate", "guerrilla", "underground"))
		"underground_26j_dr_at_open_casino":
			var ug := st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground")
			return 1.0 if st.count("syndicate", "casino", "open") > 0 and ug > 0 else 0.0
		"vulnerable_26j_base": return 1.0 if st.count("m26", "base") > 0 and st.count("m26", "guerrilla", "underground") == 0 else 0.0
		"vulnerable_dr_base": return 1.0 if st.count("directorio", "base") > 0 and st.count("directorio", "guerrilla", "underground") == 0 else 0.0
		"vulnerable_open_casino": return 1.0 if st.count("syndicate", "casino", "open") > 0 and st.count("syndicate", "guerrilla", "underground") == 0 else 0.0
		"most_26j_guerrillas": return float(st.count("m26", "guerrilla"))
		"most_dr_guerrillas": return float(st.count("directorio", "guerrilla"))
		"most_underground_26j_guerrillas": return float(st.count("m26", "guerrilla", "underground"))
		"most_underground_dr_guerrillas": return float(st.count("directorio", "guerrilla", "underground"))
		"province_or_city_without_gov_control": return 1.0 if sd.has_population() and st.control != "government" else 0.0
		"province_or_city_without_26j_control": return 1.0 if sd.has_population() and st.control != "m26" else 0.0
		"province_or_city_without_dr_control": return 1.0 if sd.has_population() and st.control != "directorio" else 0.0
		"adjacent_to_province_or_city_without_dr_control":
			for adj in sd.adjacent:
				if state.game_def.space(adj).has_population() and state.space_state(adj).control != "directorio":
					return 1.0
			return 0.0
		"province_room_for_available_gov_base":
			return 1.0 if sd.type == CoinEnums.SpaceType.PROVINCE and state.available("government", "base") > 0 and mod.can_place_base(state, sid, false) else 0.0
		"guerrillas_1_2_and_room_for_26j_base":
			var g := st.count("m26", "guerrilla")
			return 1.0 if g >= 1 and g <= 2 and mod.can_place_base(state, sid, false) else 0.0
		"guerrillas_1_2_and_room_for_dr_base":
			var g2 := st.count("directorio", "guerrilla")
			return 1.0 if g2 >= 1 and g2 <= 2 and mod.can_place_base(state, sid, false) else 0.0
	return 0.0


# ---------------------------------------------------------------------------
# Turno
# ---------------------------------------------------------------------------

func take_turn(faction: String) -> Dictionary:
	_log = []
	if not _cards.has(faction):
		return _pass(faction)
	var letter := deck.draw_for(faction)
	var attempts := 0
	while letter != "" and attempts < 6:
		attempts += 1
		var card: Dictionary = _cards[faction].get(letter, {})
		var side: Dictionary = card.get("front", {})
		var res := CalixtoEngine.walk(side, func(n): return _pred(n, faction))
		if res["result"] == "flip":
			side = card.get("back", {})
			res = CalixtoEngine.walk(side, func(n): return _pred(n, faction))
		if res["result"] == "draw":
			letter = deck.draw_next(faction)
			continue
		# res = op
		var op_id: String = res["op_id"]
		var op_def: Dictionary = side.get("ops", {}).get(op_id, {})
		var an := _activation_number(faction, side)
		var done := _execute_op(faction, op_def, an, letter)
		if not done:
			letter = deck.draw_next(faction)
			continue
		# Attività Speciale (prima fattibile)
		var sa := _execute_special(faction, CalixtoEngine.specials_for(side, op_id))
		state.recompute_all_control()
		mod._refresh_victory_tracks(state)
		_log.append("Calixto %s: carta %s → %s" % [faction, letter, op_def.get("type", op_id)])
		return {"ok": true, "action": String(op_def.get("type", op_id)),
			"special": sa != "", "special_type": sa, "log": _log}
	return _pass(faction)


func _pass(faction: String) -> Dictionary:
	_log.append("Calixto %s: nessuna Operazione legale → Passa" % faction)
	return {"ok": false, "action": "pass", "log": _log}


## Azioni della Fase di Supporto della Propaganda NP (Calixto C8.5.9):
## GOV Azione Civica (verso Supporto Attivo), 26J Agitazione (verso Opposizione Attiva),
## DR Sostegno Espatriati (Rally). Restituisce il log.
func propaganda_support() -> Array:
	_log = []
	# GOV: shift verso Supporto Attivo, max 1d3 + EC senza Sabotaggio
	var gbudget := _rng.randi_range(1, 3) + _ecs_without_sabotage()
	var gd := 0
	while gd < gbudget:
		var t := _best_civic_space()
		if t == "":
			break
		var st: SpaceState = state.space_state(t)
		if st.marker("terror") > 0:
			st.add_marker("terror", -1)
		elif st.support < CoinEnums.Support.ACTIVE_SUPPORT:
			st.support = (st.support + 1) as CoinEnums.Support
		else:
			break
		gd += 1
	if gd > 0:
		_log.append("Propaganda GOV: %d verso Supporto Attivo" % gd)
	# 26J: shift verso Opposizione Attiva, max 1d3 + Basi 26J sulla mappa
	var mbudget := _rng.randi_range(1, 3) + state.count_on_map("m26", "base")
	var md := 0
	while md < mbudget:
		var t2 := _best_agitation_space()
		if t2 == "":
			break
		var st2: SpaceState = state.space_state(t2)
		if st2.marker("terror") > 0:
			st2.add_marker("terror", -1)
		elif st2.support > CoinEnums.Support.ACTIVE_OPPOSITION:
			st2.support = (st2.support - 1) as CoinEnums.Support
		else:
			break
		md += 1
	if md > 0:
		_log.append("Propaganda 26J: %d verso Opposizione Attiva" % md)
	# DR: Sostegno Espatriati (Rally)
	_do_rally("directorio", 3)
	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	return _log


func _ecs_without_sabotage() -> int:
	var n := 0
	for sid in _ids():
		if _is_ec(sid) and state.space_state(sid).marker("sabotage") == 0:
			n += 1
	return n


func _best_agitation_space() -> String:
	var cands: Array = []
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		if not sd.has_population() or st.count("m26") == 0:
			continue
		if st.support <= CoinEnums.Support.ACTIVE_OPPOSITION and st.marker("terror") == 0:
			continue
		cands.append(sid)
	if cands.is_empty():
		return ""
	cands = _ordered_col("m26", "shift_active_opposition", cands)
	return cands[0]


## Scelta Evento guidata dalla tabella Event Instructions (lato + Critical) con verifica di
## beneficio: simula i lati candidati su una copia dello stato e gioca se migliora il margine.
## Soglia di guadagno più bassa se la carta è Critical per la Fazione. Restituisce
## {"play": bool, "side": String}.
func event_choice(faction: String, card_number: int) -> Dictionary:
	if card_number <= 0:
		return {"play": false}
	var entry: Dictionary = _events.get(str(card_number), {}).get(faction, {})
	# Eventi "solo se giocatore": gli NP non li eseguono.
	if entry.get("player_only", false):
		return {"play": false}
	# Lati candidati: quello indicato dalla tabella, altrimenti entrambi.
	var sides: Array = []
	if entry.has("side") and entry["side"] != null:
		sides = [String(entry["side"])]
	else:
		sides = ["unshaded", "shaded"]
	# Soglia: Critical (per tabella) → basta non peggiorare; con istruzione → 2; senza → 3.
	var gain_min := 3
	if not entry.is_empty():
		gain_min = 1 if entry.get("critical", false) else 2
	var base: int = int(mod.victory_status(state)[faction].margin)
	var best := base
	var best_side := ""
	for side in sides:
		var copy := GameState.from_dict(state.game_def, state.to_dict())
		var ev := CubaLibreEvents.new(copy, mod)
		ev.apply(card_number, side, faction)
		copy.recompute_all_control()
		mod._refresh_victory_tracks(copy)
		var m: int = int(mod.victory_status(copy)[faction].margin)
		if m > best:
			best = m
			best_side = side
	if best_side != "" and best - base >= gain_min:
		return {"play": true, "side": best_side}
	return {"play": false}


## Numero di Attivazione: Governo = livello Alleanza USA (4/3/2); insorti = dado della carta.
func _activation_number(faction: String, side: Dictionary) -> int:
	if faction == "government":
		return [4, 3, 2][int(state.tracks.get("us_alliance", 0))]
	return int(side.get("an", 2))


## Numero di spazi consentiti: tira 1d6 dopo ogni spazio; > AN consente un altro spazio.
func _spaces_allowed(an: int, candidates: int) -> int:
	var n := 0
	while n < candidates:
		n += 1
		if _rng.randi_range(1, 6) <= an:
			break
	return n


# ---------------------------------------------------------------------------
# Esecuzione Operazioni (selezione spazi semplificata)
# ---------------------------------------------------------------------------

func _execute_op(faction: String, op_def: Dictionary, an: int, _letter: String) -> bool:
	var t := String(op_def.get("type", ""))
	match t:
		"train": return _do_train(an, op_def)
		"sweep": return _do_sweep(an)
		"assault": return _do_assault(an)
		"garrison": return _do_garrison()
		"rally": return _do_rally(faction, an)
		"march": return _do_march(faction)
		"attack": return _do_attack(faction, an)
		"terror": return _do_terror(faction, an)
		"construct": return _do_build()
	return false


func _ids() -> Array:
	return state.game_def.space_ids()


func _is_ec(sid: String) -> bool:
	return state.game_def.space(sid).is_economic()


func _run(res: Dictionary) -> bool:
	for line in res.get("log", []):
		_log.append(String(line))
	if not res.get("ok", false):
		if res.has("error"):
			_log.append("⚠ " + String(res["error"]))
		return false
	return true


func _do_train(an: int, op_def: Dictionary = {}) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		if sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
	spaces = _ordered("government", "train", spaces)
	var n := _spaces_allowed(an, spaces.size())
	var chosen := spaces.slice(0, n)
	var place := {}
	for sid in chosen:
		var st: SpaceState = state.space_state(sid)
		var cur := st.count("government", "troops") + st.count("government", "police")
		var need: int = clampi(4 - cur, 0, 4)
		var police: int = mini(need, state.available("government", "police"))
		var troops: int = mini(need - police, state.available("government", "troops"))
		place[sid] = {"police": police, "troops": troops}
	var ok := _run(ops.train({"spaces": chosen, "place": place}))
	if ok:
		_gov_train_post(op_def)
	return ok


## Istruzioni "post" dell'Addestramento (Governo): Azione Civica (Shift verso Supporto
## Attivo, max 1d3) e piazzamento Base in una Provincia senza Base GOV.
func _gov_train_post(op_def: Dictionary) -> void:
	var has_civic := false
	var has_base := false
	for step in op_def.get("post", []):
		var do := String(step.get("do", ""))
		if do == "civic_action":
			has_civic = true
		elif do == "place_base":
			has_base = true
	if has_civic:
		var budget := _rng.randi_range(1, 3)
		var done := 0
		while done < budget:
			var target := _best_civic_space()
			if target == "":
				break
			var st: SpaceState = state.space_state(target)
			if st.marker("terror") > 0:
				st.add_marker("terror", -1)
			elif st.support < CoinEnums.Support.ACTIVE_SUPPORT:
				st.support = (st.support + 1) as CoinEnums.Support
			else:
				break
			done += 1
		if done > 0:
			_log.append("Azione Civica: %d shift verso Supporto Attivo" % done)
	if has_base and state.available("government", "base") > 0:
		var provs: Array = []
		for sid in _ids():
			var sd: SpaceDef = state.game_def.space(sid)
			if sd.type == CoinEnums.SpaceType.PROVINCE and state.space_state(sid).count("government", "base") == 0 \
					and mod.can_place_base(state, sid, false):
				provs.append(sid)
		provs = _ordered_col("government", "place_bases", provs)
		if not provs.is_empty():
			state.place_from_available("government", "base", provs[0], 1)
			_log.append("Governo piazza una Base in %s" % provs[0])


## Migliore spazio per l'Azione Civica: Controllato dal Governo, con Truppe e Polizia,
## non già a Supporto Attivo (o con Terrore), ordinato per priorità Shift verso Supporto.
func _best_civic_space() -> String:
	var cands: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.control != "government":
			continue
		if st.count("government", "troops") == 0 or st.count("government", "police") == 0:
			continue
		if st.support >= CoinEnums.Support.ACTIVE_SUPPORT and st.marker("terror") == 0:
			continue
		cands.append(sid)
	if cands.is_empty():
		return ""
	cands = _ordered_col("government", "shift_active_support", cands)
	return cands[0]


func _do_sweep(an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var und := st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground")
		if und > 0 and st.count("government", "troops") + st.count("government", "police") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
	spaces = _ordered("government", "sweep", spaces)
	return _run(ops.sweep({"spaces": spaces.slice(0, _spaces_allowed(an, spaces.size()))}))


func _do_assault(an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var enemy := st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active") \
			+ st.count("m26", "base") + st.count("directorio", "base") + st.count("syndicate", "casino", "open")
		if st.count("government", "troops") > 0 and enemy > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
	spaces = _ordered("government", "assault", spaces)
	return _run(ops.assault({"spaces": spaces.slice(0, _spaces_allowed(an, spaces.size()))}))


func _do_garrison() -> bool:
	var target := ""
	for sid in _ids():
		if _is_ec(sid) and state.space_state(sid).count("m26", "guerrilla") > 0:
			target = sid; break
	var source := _most("government", "police")
	var moves: Array = []
	if target != "" and source != "":
		moves.append({"type": "police", "from": source, "to": target, "count": 1})
	return _run(ops.garrison({"moves": moves, "assault_ec": target}))


func _do_rally(faction: String, an: int) -> bool:
	var spaces := _insurgent_rally_spaces(faction)
	if spaces.is_empty():
		return false
	spaces = _ordered(faction, "rally", spaces)
	var chosen := spaces.slice(0, _spaces_allowed(an, spaces.size()))
	var choices := {}
	for sid in chosen:
		var st: SpaceState = state.space_state(sid)
		if st.count(faction, "base") > 0:
			choices[sid] = "extra"
		elif st.count(faction, "guerrilla") >= 2 and mod.can_place_base(state, sid, false):
			choices[sid] = "base"
		else:
			choices[sid] = "place"
	return _run(ops.rally({"faction": faction, "spaces": chosen, "choices": choices}))


func _do_march(faction: String) -> bool:
	# Destinazione: spazi adiacenti a Guerriglie della Fazione, ordinati per priorità march_dest.
	var dests: Array = []
	for sid in _ids():
		var adj_with_g := false
		for adj in state.game_def.space(sid).adjacent:
			if state.space_state(adj).count(faction, "guerrilla") > 0:
				adj_with_g = true
				break
		if adj_with_g:
			dests.append(sid)
	if dests.is_empty():
		return false
	dests = _ordered(faction, "march", dests)
	for dest in dests:
		var moves: Array = []
		for adj in state.game_def.space(dest).adjacent:
			var surplus := _march_surplus(faction, adj)
			if surplus > 0:
				moves.append({"from": adj, "to": dest, "count": surplus})
		if not moves.is_empty():
			return _run(ops.march({"faction": faction, "moves": moves}))
	return false


## Guerriglie che possono lasciare l'origine senza perdere Controllo/clandestinità (Move
## Priorities, "keep in origin": tieni abbastanza per non cambiare Controllo e 1 Clandestina
## se c'è una Base della Fazione).
func _march_surplus(faction: String, sid: String) -> int:
	var st: SpaceState = state.space_state(sid)
	var g := st.count(faction, "guerrilla")
	if g == 0:
		return 0
	var keep := 0
	# Tieni almeno 1 Clandestina se la Fazione ha una Base qui.
	if st.count(faction, "base") > 0 and st.count(faction, "guerrilla", "underground") > 0:
		keep += 1
	# Tieni abbastanza per non cedere il Controllo della Fazione.
	if st.control == faction:
		var others := 0
		for e in ["government", "m26", "directorio", "syndicate"]:
			if e != faction:
				others += st.count(e)
		keep = maxi(keep, others + 1 - (st.count(faction) - g))
	return maxi(0, g - keep)


func _do_attack(faction: String, an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count(faction, "guerrilla") < 1:
			continue
		var enemies := 0
		for e in ["government", "m26", "directorio", "syndicate"]:
			if e != faction:
				enemies += st.count(e)
		if enemies > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
	spaces = _ordered(faction, "attack", spaces)
	return _run(ops.attack({"faction": faction, "spaces": spaces.slice(0, _spaces_allowed(an, spaces.size()))}))


func _do_terror(faction: String, an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
	spaces = _ordered(faction, "terror", spaces)
	return _run(ops.terror({"faction": faction, "spaces": spaces.slice(0, _spaces_allowed(an, spaces.size()))}))


func _do_build() -> bool:
	var spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.has_population() and (st.control == "government" or st.control == "syndicate") \
				and mod.can_place_base(state, sid, true):
			spaces.append(sid)
	if spaces.is_empty() or state.get_resources("syndicate") < 5:
		return false
	spaces = _ordered("syndicate", "construct", spaces)
	var choices := {}
	for sid in spaces.slice(0, 1):
		choices[sid] = "new"
	return _run(ops.build({"spaces": choices.keys(), "choices": choices}))


func _insurgent_rally_spaces(faction: String) -> Array:
	var out: Array = []
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.has_population():
			continue
		var s: int = state.space_state(sid).support
		if faction == "m26" and s > 0:
			continue
		if faction == "directorio" and abs(s) == 2:
			continue
		out.append(sid)
	# Priorità: spazi con Base (per piazzare "extra" → Controllo), poi alta Popolazione,
	# poi numero di Guerriglie. Aiuta a conquistare il Controllo di spazi a 2-Pop.
	out.sort_custom(func(a, b):
		return _rally_score(faction, a) > _rally_score(faction, b))
	return out


func _rally_score(faction: String, sid: String) -> int:
	var st: SpaceState = state.space_state(sid)
	var sd: SpaceDef = state.game_def.space(sid)
	return st.count(faction, "base") * 100 + sd.pop * 10 + st.count(faction, "guerrilla")


func _most(faction: String, type: String) -> String:
	var best := ""
	var best_n := 0
	for sid in _ids():
		var n := state.space_state(sid).count(faction, type)
		if n > best_n:
			best_n = n; best = sid
	return best


# ---------------------------------------------------------------------------
# Attività Speciali (prima fattibile della lista)
# ---------------------------------------------------------------------------

func _execute_special(faction: String, list: Array) -> String:
	for entry in list:
		if _try_special(faction, entry):
			return String(entry.get("sa", ""))
	return ""


func _try_special(faction: String, entry: Dictionary) -> bool:
	var sa := String(entry.get("sa", ""))
	match sa:
		"air_strike":
			for sid in _ids():
				if state.game_def.space(sid).type == CoinEnums.SpaceType.CITY:
					continue
				var st: SpaceState = state.space_state(sid)
				if st.count("m26", "base") + st.count("directorio", "base") \
						+ st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active") > 0:
					return _run(specials.air_strike({"space": sid}))
		"reprisal":
			for sid in _ids():
				var st: SpaceState = state.space_state(sid)
				if st.control == "government" and st.support < 0:
					return _run(specials.reprisal({"space": sid, "move": {}}))
		"transport":
			var src := _most("government", "troops")
			if src != "":
				for sid in _ids():
					var sd: SpaceDef = state.game_def.space(sid)
					var st: SpaceState = state.space_state(sid)
					if sd.type == CoinEnums.SpaceType.PROVINCE and st.count("government", "police") > 0 \
							and st.count("government", "troops") == 0:
						return _run(specials.transport({"from": src, "to": sid, "count": 2}))
		"infiltrate":
			for sid in _ids():
				if specials._has_or_adjacent_underground("m26", sid):
					return _run(specials.infiltrate({"space": sid}))
		"ambush":
			var fn := "ambush_m26"
			for sid in _ids():
				var st: SpaceState = state.space_state(sid)
				if st.count(faction, "guerrilla") > 0 and _enemy_count(faction, st) > 0:
					return _run(specials.ambush(faction, {"space": sid}))
		"kidnap":
			for sid in _ids():
				var st: SpaceState = state.space_state(sid)
				if st.count("m26", "guerrilla") > st.count("government", "police"):
					return _run(specials.kidnap({"space": sid, "target": "government"}))
		"subvert":
			for sid in _ids():
				if state.space_state(sid).control == "directorio":
					return _run(specials.subvert({"space": sid}))
		"assassinate":
			for sid in _ids():
				var st: SpaceState = state.space_state(sid)
				if st.count("directorio", "guerrilla") > st.count("government", "police"):
					return _run(specials.assassinate({"space": sid}))
		"profit":
			var sp: Array = []
			for sid in _ids():
				if state.space_state(sid).count("syndicate", "casino", "open") > 0:
					sp.append(sid)
			if not sp.is_empty():
				return _run(specials.profit({"mode": "cash", "spaces": sp.slice(0, 2)}))
		"muscle":
			for sid in _ids():
				var st: SpaceState = state.space_state(sid)
				if st.count("syndicate", "guerrilla") > 0 and _enemy_count("syndicate", st) > 0:
					return _run(specials.muscle({"space": sid}))
		"bribe":
			if state.get_resources("syndicate") >= 3:
				for sid in _ids():
					var st: SpaceState = state.space_state(sid)
					for enemy in ["m26", "directorio"]:
						if st.count(enemy, "troops") + st.count(enemy, "police") > 0:
							return _run(specials.bribe({"space": sid, "action": "cubes", "count": 2}))
						if st.count(enemy, "guerrilla") > 0:
							return _run(specials.bribe({"space": sid, "action": "guerrillas_remove", "count": 2}))
	return false


func _enemy_count(faction: String, st: SpaceState) -> int:
	var n := 0
	for e in ["government", "m26", "directorio", "syndicate"]:
		if e != faction:
			n += st.count(e)
	return n


# ---------------------------------------------------------------------------# Predicati delle condizioni delle carte. Niente lambda: cicli espliciti.

func _pred(node: Dictionary, faction: String) -> bool:
	_af = faction
	var cond := String(node.get("cond", ""))
	if cond == "" or cond == "otherwise":
		return true
	if cond == "any":
		for c in node.get("of", []):
			if _eval(String(c)):
				return true
		return false
	return _eval(cond)


func _eval(cond: String) -> bool:
	match cond:
		# --- Governo ---
		"city_not_active_support": return _f_city_not_active_support()
		"underground_guerrilla_at_support": return _f_underground_at_support()
		"ec_with_guerrillas": return _f_ec_with_guerrillas()
		"province_2pop_without_gov_control": return _f_prov2_no_gov()
		"assault_could_remove_3plus_or_base_casino": return _f_assault_ok()
		"space_gov_forces_and_vulnerable_enemies": return _f_gov_vuln()
		"troops_3plus_not_needed_for_control": return _f_troops3()
		"available_gov_base": return state.available("government", "base") > 0
		"ec_26j_dr_guerrillas_gt_cubes": return _f_ec_g_gt_cubes()
		"avail_cubes_4plus": return state.available("government", "troops") + state.available("government", "police") >= 4
		# --- Insorti comuni ---
		"d6_le_avail_26j_guerrillas": return _rng.randi_range(1, 6) <= state.available("m26", "guerrilla")
		"avail_26j_guerrillas_lt_d6": return state.available("m26", "guerrilla") < _rng.randi_range(1, 6)
		"avail_26j_guerrillas_4plus": return state.available("m26", "guerrilla") >= 4
		"d6_le_avail_dr_guerrillas": return _rng.randi_range(1, 6) <= state.available("directorio", "guerrilla")
		"avail_dr_guerrillas_lt_d6": return state.available("directorio", "guerrilla") < _rng.randi_range(1, 6)
		"avail_dr_guerrillas_4plus": return state.available("directorio", "guerrilla") >= 4
		"guerrillas_4plus_any_space": return _f_count_ge("m26", 4)
		"any_2pop_without_active_opp": return _f_2pop_not_active_opp()
		"any_2pop_without_dr_control": return _f_2pop_no_ctrl("directorio")
		"any_available_dr_bases": return state.available("directorio", "base") > 0
		"underground_26j_in_2pop_with_support": return _f_und_2pop_support("m26")
		"underground_26j_in_2pop_not_active_opp": return _f_und_2pop_not_actopp("m26")
		"underground_26j_not_active_opp": return _f_und_not_actopp("m26")
		"underground_dr_at_active_opp_or_active_support": return _f_und_active_so("directorio")
		"underground_dr_at_opp_or_support": return _f_und_so("directorio")
		"enemy_space_4plus_or_underground": return _f_enemy_space(false)
		"enemy_space_4plus_or_underground_no_control": return _f_enemy_space(true)
		"moveable_26j_adj_uncontrolled", "moveable_dr_adj_uncontrolled", "adjacent_to_province_or_city_without_dr_control":
			return _f_adj_uncontrolled(1)
		"moveable_2plus_26j_adj_uncontrolled", "moveable_2plus_dr_adj_uncontrolled":
			return _f_adj_uncontrolled(2)
		"guerrillas_3plus_no_support_room_for_base", "dr_guerrillas_3plus_no_active_supp_opp_room_for_base":
			return _f_g3_room_base()
		"province": return _f_any_province()
		"most_support": return state.total_support() > 0
		# --- Sindacato ---
		"any_available_casinos": return state.available("syndicate", "casino") > 0
		"any_available_cash_markers": return state.total_cash_on_map() < GameState.CASH_LIMIT
		"open_casinos_lt_8": return mod.open_casinos(state) < 8
		"syn_resources_lt_6": return state.get_resources("syndicate") < 6
		"syn_resources_gt5_and_construct_possible": return _f_syn_construct()
		"d3_le_avail_or_active_syn_guerrillas": return _rng.randi_range(1, 3) <= state.available("syndicate", "guerrilla") + _active("syndicate")
		"underground_syn_in_support_or_opp": return _f_und_so("syndicate")
		"underground_syn_in_support_or_opp_no_open_casino": return _f_syn_und_so_no_casino()
		"space_2plus_underground_syn": return _f_count_und("syndicate", 2)
		"moveable_syn_guerrilla_with_cash": return _f_syn_g_cash()
		"any_avail_or_active_syn_guerrillas": return state.available("syndicate", "guerrilla") + _active("syndicate") > 0
	return false


# --- Helper a ciclo esplicito ---

func _f_city_not_active_support() -> bool:
	for sid in _ids():
		if state.game_def.space(sid).type == CoinEnums.SpaceType.CITY \
				and state.space_state(sid).support < CoinEnums.Support.ACTIVE_SUPPORT:
			return true
	return false


func _f_underground_at_support() -> bool:
	for sid in _ids():
		if state.space_state(sid).support > 0 and _underground_any(sid):
			return true
	return false


func _f_ec_with_guerrillas() -> bool:
	for sid in _ids():
		if _is_ec(sid) and _guerrillas_any(sid) > 0:
			return true
	return false


func _f_prov2_no_gov() -> bool:
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.type == CoinEnums.SpaceType.PROVINCE and sd.pop >= 2 \
				and state.space_state(sid).control != "government":
			return true
	return false


func _f_assault_ok() -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count("government", "troops") == 0:
			continue
		var act := st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active")
		var bc := st.count("m26", "base") + st.count("directorio", "base") + st.count("syndicate", "casino", "open")
		if act >= 3 or bc > 0:
			return true
	return false


func _f_gov_vuln() -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count("government", "troops") + st.count("government", "police") > 0 and _vulnerable_enemies(sid) > 0:
			return true
	return false


func _f_troops3() -> bool:
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		var relevant := sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0
		if relevant and st.count("government", "troops") >= 3:
			return true
	return false


func _f_ec_g_gt_cubes() -> bool:
	for sid in _ids():
		if not _is_ec(sid):
			continue
		var st: SpaceState = state.space_state(sid)
		var g := st.count("m26", "guerrilla") + st.count("directorio", "guerrilla")
		var c := st.count("government", "troops") + st.count("government", "police")
		if g > c and g > 0:
			return true
	return false


func _f_count_ge(faction: String, n: int) -> bool:
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla") >= n:
			return true
	return false


func _f_count_und(faction: String, n: int) -> bool:
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla", "underground") >= n:
			return true
	return false


func _f_2pop_not_active_opp() -> bool:
	for sid in _ids():
		if state.game_def.space(sid).pop >= 2 \
				and state.space_state(sid).support > CoinEnums.Support.ACTIVE_OPPOSITION:
			return true
	return false


func _f_2pop_no_ctrl(faction: String) -> bool:
	for sid in _ids():
		if state.game_def.space(sid).pop >= 2 and state.space_state(sid).control != faction:
			return true
	return false


func _f_und_2pop_support(faction: String) -> bool:
	for sid in _ids():
		if state.game_def.space(sid).pop >= 2 and state.space_state(sid).support > 0 \
				and state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


func _f_und_2pop_not_actopp(faction: String) -> bool:
	for sid in _ids():
		if state.game_def.space(sid).pop >= 2 \
				and state.space_state(sid).support > CoinEnums.Support.ACTIVE_OPPOSITION \
				and state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


func _f_und_not_actopp(faction: String) -> bool:
	for sid in _ids():
		if state.space_state(sid).support > CoinEnums.Support.ACTIVE_OPPOSITION \
				and state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


func _f_und_active_so(faction: String) -> bool:
	for sid in _ids():
		if abs(state.space_state(sid).support) == 2 \
				and state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


func _f_und_so(faction: String) -> bool:
	for sid in _ids():
		if state.space_state(sid).support != 0 \
				and state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


func _f_enemy_space(need_no_control: bool) -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if need_no_control and st.control == _af:
			continue
		var ok := st.count(_af, "guerrilla") >= 4 or st.count(_af, "guerrilla", "underground") >= 1
		if ok and _enemy_count(_af, st) > 0:
			return true
	return false


func _f_adj_uncontrolled(min_g: int) -> bool:
	for sid in _ids():
		if state.space_state(sid).count(_af, "guerrilla") < min_g:
			continue
		for adj in state.game_def.space(sid).adjacent:
			if state.space_state(adj).control != _af:
				return true
	return false


func _f_g3_room_base() -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count(_af, "guerrilla") >= 3 and st.support <= 0 and mod.can_place_base(state, sid, false):
			return true
	return false


func _f_any_province() -> bool:
	for sid in _ids():
		if state.game_def.space(sid).type == CoinEnums.SpaceType.PROVINCE:
			return true
	return false


func _f_syn_construct() -> bool:
	if state.get_resources("syndicate") <= 5:
		return false
	for sid in _ids():
		if state.game_def.space(sid).has_population() and mod.can_place_base(state, sid, true):
			return true
	return false


func _f_syn_und_so_no_casino() -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.support != 0 and st.count("syndicate", "guerrilla", "underground") > 0 \
				and st.count("syndicate", "casino", "open") == 0:
			return true
	return false


func _f_syn_g_cash() -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count("syndicate", "guerrilla") > 0 and st.cash_for("syndicate") > 0:
			return true
	return false


func _underground_any(sid: String) -> bool:
	var st: SpaceState = state.space_state(sid)
	return st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground") \
		+ st.count("syndicate", "guerrilla", "underground") > 0


func _guerrillas_any(sid: String) -> int:
	var st: SpaceState = state.space_state(sid)
	return st.count("m26", "guerrilla") + st.count("directorio", "guerrilla") + st.count("syndicate", "guerrilla")


func _vulnerable_enemies(sid: String) -> int:
	var st: SpaceState = state.space_state(sid)
	var und := st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground")
	var act := st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active")
	var bc := st.count("m26", "base") + st.count("directorio", "base") + st.count("syndicate", "casino", "open")
	if und > 0:
		return act
	return act + bc


func _active(faction: String) -> int:
	var n := 0
	for sid in _ids():
		n += state.space_state(sid).count(faction, "guerrilla", "active")
	return n
