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


func _load_data() -> void:
	var f := FileAccess.open("res://games/cuba_libre/data/calixto_cards.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_cards = d
			_an_dice = d.get("_an_dice", {})


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
		_execute_special(faction, CalixtoEngine.specials_for(side, op_id))
		state.recompute_all_control()
		mod._refresh_victory_tracks(state)
		_log.append("Calixto %s: carta %s → %s" % [faction, letter, op_def.get("type", op_id)])
		return {"ok": true, "action": String(op_def.get("type", op_id)), "log": _log}
	return _pass(faction)


func _pass(faction: String) -> Dictionary:
	_log.append("Calixto %s: nessuna Operazione legale → Passa" % faction)
	return {"ok": false, "action": "pass", "log": _log}


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
		"train": return _do_train(an)
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


func _do_train(an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		if sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
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
	return _run(ops.train({"spaces": chosen, "place": place}))


func _do_sweep(an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var und := st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground")
		if und > 0 and st.count("government", "troops") + st.count("government", "police") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
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
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla") == 0:
			continue
		for adj in state.game_def.space(sid).adjacent:
			if state.space_state(adj).count(faction) == 0:
				return _run(ops.march({"faction": faction, "moves": [{"from": sid, "to": adj, "count": 1}]}))
	return false


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
	return _run(ops.attack({"faction": faction, "spaces": spaces.slice(0, _spaces_allowed(an, spaces.size()))}))


func _do_terror(faction: String, an: int) -> bool:
	var spaces: Array = []
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
			spaces.append(sid)
	if spaces.is_empty():
		return false
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
	out.sort_custom(func(a, b):
		var sa: SpaceState = state.space_state(a)
		var sb: SpaceState = state.space_state(b)
		return sa.count(faction, "base") * 10 + sa.count(faction, "guerrilla") \
			> sb.count(faction, "base") * 10 + sb.count(faction, "guerrilla"))
	return out


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

func _execute_special(faction: String, list: Array) -> void:
	for entry in list:
		if _try_special(faction, entry):
			return


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
