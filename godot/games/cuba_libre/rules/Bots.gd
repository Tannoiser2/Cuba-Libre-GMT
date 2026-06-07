class_name CubaLibreBots
extends BotBrain

## Bot Non-Giocatore di Cuba Libre (cap. 8). Traduce i flowchart per Fazione in decisioni
## deterministiche, eseguite tramite le classi Operazioni e Attività Speciali.
##
## NOTA: i bot ufficiali scelgono l'Evento quando ha effetto (8.1); poiché gli effetti
## degli Eventi non sono ancora implementati, qui i bot svolgono Operazioni + Attività
## Speciali secondo 8.5-8.8. L'aggancio all'Evento sarà aggiunto con la Fase 2 (Carte).

var state: GameState
var mod: CubaLibreModule
var ops: CubaLibreOperations
var specials: CubaLibreSpecials

var _log: Array = []


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module
	ops = CubaLibreOperations.new(p_state, p_module)
	specials = CubaLibreSpecials.new(p_state, p_module)


## Azioni dei bot nella Fase di Supporto della Propaganda (8.6.2, 8.7.5, 8.8.6).
## Da chiamare dopo l'Alleanza USA e prima della Sistemazione.
func propaganda_support() -> Array:
	_log = []
	_gov_civic_action()
	_m26_demonstrations()
	_dr_expatriate_support()
	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	return _log


## 8.8.6 Azione Civica del Governo: spende 4 Risorse per passo (Terrore o +1 Supporto),
## senza scendere sotto 9 Risorse, negli spazi Controllati con Truppe e Polizia.
func _gov_civic_action() -> void:
	var guard := 0
	while state.get_resources("government") >= 13 and guard < 50:
		guard += 1
		var target := _best_support_space("government", true)
		if target == "":
			break
		state.add_resources("government", -4)
		var st: SpaceState = state.space_state(target)
		if st.marker("terror") > 0:
			st.add_marker("terror", -1)
		elif st.support < CoinEnums.Support.ACTIVE_SUPPORT:
			st.support = (st.support + 1) as CoinEnums.Support
	_log.append("Azione Civica del Governo completata")


## 8.7.5 Dimostrazioni del 26 Luglio: 1 Risorsa per passo verso Opposizione Attiva.
func _m26_demonstrations() -> void:
	var guard := 0
	while state.get_resources("m26") >= 1 and guard < 80:
		guard += 1
		var target := _best_support_space("m26", false)
		if target == "":
			break
		state.add_resources("m26", -1)
		var st: SpaceState = state.space_state(target)
		if st.marker("terror") > 0:
			st.add_marker("terror", -1)
		elif st.support > CoinEnums.Support.ACTIVE_OPPOSITION:
			st.support = (st.support - 1) as CoinEnums.Support
	_log.append("Dimostrazioni del 26 Luglio completate")


## 8.6.2 Sostegno degli Espatriati (DR): Rally gratuito per ottenere Controllo DR
## della maggiore Popolazione possibile.
func _dr_expatriate_support() -> void:
	var best := ""
	var best_pop := -1
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.has_population():
			continue
		var st: SpaceState = state.space_state(sid)
		if abs(st.support) == 2:
			continue  # niente Supporto/Opposizione Attiva
		if st.control != "" and st.control != "directorio":
			continue
		if st.control == "directorio":
			continue  # già controllata
		if sd.pop > best_pop and state.available("directorio", "guerrilla") > 0:
			best_pop = sd.pop; best = sid
	if best == "":
		return
	# Piazza Guerriglie DR sufficienti a controllare lo spazio
	var st2: SpaceState = state.space_state(best)
	var others := 0
	for f in ["government", "m26", "syndicate"]:
		others += state.control_count(f, st2)
	var need: int = others - st2.count("directorio") + 1
	state.place_from_available("directorio", "guerrilla", best, maxi(need, 1))
	_log.append("Sostegno Espatriati: Controllo DR a %s" % best)


## Spazio migliore per Azione Civica (govt=true) o Dimostrazioni (govt=false).
func _best_support_space(faction: String, govt: bool) -> String:
	var best := ""
	var best_pop := -1
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.has_population():
			continue
		var st: SpaceState = state.space_state(sid)
		if st.control != faction:
			continue
		if govt:
			if st.count("government", "troops") == 0 or st.count("government", "police") == 0:
				continue
			if st.support >= CoinEnums.Support.ACTIVE_SUPPORT and st.marker("terror") == 0:
				continue
		else:
			if st.support <= CoinEnums.Support.ACTIVE_OPPOSITION and st.marker("terror") == 0:
				continue
		if sd.pop > best_pop:
			best_pop = sd.pop; best = sid
	return best


func take_turn(faction: String) -> Dictionary:
	_log = []
	var action := "pass"
	match faction:
		"syndicate": action = _syndicate_turn()
		"directorio": action = _directorio_turn()
		"m26": action = _m26_turn()
		"government": action = _government_turn()
	if action == "pass":
		var gain := mod.pass_resources(faction)
		state.add_resources(faction, gain)
		_log.append("%s Passa (+%d Risorse)" % [faction, gain])
	return {"ok": action != "pass", "action": action, "log": _log}


# ---------------------------------------------------------------------------
# Helper di lettura
# ---------------------------------------------------------------------------

func _ids() -> Array:
	return state.game_def.space_ids()


func _is_ec(sid: String) -> bool:
	return state.game_def.space(sid).is_economic()


func _has_underground(faction: String, sid: String) -> bool:
	return state.space_state(sid).count(faction, "guerrilla", "underground") > 0


func _run(res: Dictionary) -> void:
	for line in res.get("log", []):
		_log.append(String(line))
	if not res.get("ok", false):
		_log.append("⚠ " + String(res.get("error", "")))


# ---------------------------------------------------------------------------
# 8.5 SINDACATO
# ---------------------------------------------------------------------------

func _syndicate_turn() -> String:
	# 8.5.1 Riorganizzazione: aggiungi Guerriglia in spazi con Casinò e senza Guerriglia Sindacato
	var rally_spaces: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var has_casino := st.count("syndicate", "casino") > 0
		if has_casino and st.count("syndicate", "guerrilla") == 0:
			rally_spaces.append(sid)
	if not rally_spaces.is_empty() and state.available("syndicate", "guerrilla") > 0:
		var choices := {}
		for sid in rally_spaces:
			choices[sid] = "place"
		_run(ops.rally({"faction": "syndicate", "spaces": rally_spaces, "choices": choices}))
		_syndicate_special()
		return "rally"

	# 8.5.3 Costruzione: se Casinò disp+chiusi > Denaro fuori mappa e controllo Govt/Syn
	var build_spaces := _syndicate_build_spaces()
	var casinos_off := state.available("syndicate", "casino")  # disponibili
	if not build_spaces.is_empty() and casinos_off > 0 and state.get_resources("syndicate") >= 5:
		var n: int = 2 if state.get_resources("syndicate") > 35 else 1
		var chosen := build_spaces.slice(0, n)
		var choices := {}
		for sid in chosen:
			choices[sid] = "new"
		_run(ops.build({"spaces": chosen, "choices": choices}))
		_syndicate_special()
		return "build"

	# 8.5.4 Terrorismo: se ci sono Guerriglie Clandestine del Sindacato
	var terror_spaces := _spaces_with_underground("syndicate")
	if not terror_spaces.is_empty():
		_run(ops.terror({"faction": "syndicate", "spaces": [terror_spaces[0]]}))
		_run(_syndicate_bribe())
		return "terror"

	return "pass"


func _syndicate_build_spaces() -> Array:
	var out: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.has_population():
			continue
		if (st.control == "government" or st.control == "syndicate") and mod.can_place_base(state, sid, true):
			out.append(sid)
	return out


func _syndicate_special() -> void:
	# 8.5.5: Profitto se possibile, altrimenti Muscle, altrimenti Corruzione
	var profit_spaces: Array = []
	for sid in _ids():
		if state.space_state(sid).count("syndicate", "casino", "open") > 0:
			profit_spaces.append(sid)
	if not profit_spaces.is_empty() and state.total_cash_on_map() < GameState.CASH_LIMIT:
		_run(specials.profit({"mode": "cash", "spaces": profit_spaces.slice(0, 2)}))
		return
	_run(_syndicate_bribe())


func _syndicate_bribe() -> Dictionary:
	# Corruzione su uno spazio con pezzi nemici, se ha Risorse
	if state.get_resources("syndicate") < 3:
		return {"ok": false, "error": "Sindacato senza Risorse per Corruzione", "log": []}
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		for enemy in ["m26", "directorio"]:
			if st.count(enemy, "troops") + st.count(enemy, "police") > 0:
				return specials.bribe({"space": sid, "action": "cubes", "count": 2})
			if st.count(enemy, "guerrilla") > 0:
				return specials.bribe({"space": sid, "action": "guerrillas_remove", "count": 2})
	return {"ok": false, "error": "Nessun bersaglio per la Corruzione", "log": []}


# ---------------------------------------------------------------------------
# 8.6 DIRECTORIO
# ---------------------------------------------------------------------------

func _directorio_turn() -> String:
	# 8.6.1 Terrorismo in spazi con Supporto/Opposizione Attiva (per poi Assassinare)
	var terror_spaces: Array = []
	for sid in _spaces_with_underground("directorio"):
		var s: int = state.space_state(sid).support
		if abs(s) == 2:
			terror_spaces.append(sid)
	if not terror_spaces.is_empty():
		_run(ops.terror({"faction": "directorio", "spaces": [terror_spaces[0]]}))
		# Assassinio se possibile
		var st: SpaceState = state.space_state(terror_spaces[0])
		if st.count("directorio", "guerrilla") > st.count("government", "police"):
			_run(specials.assassinate({"space": terror_spaces[0]}))
		return "terror"

	# 8.6.2 Riorganizzazione (se >=6 Guerriglie disp. o porrebbe una Base)
	if state.available("directorio", "guerrilla") >= 6 or _can_place_base("directorio"):
		var rally_spaces := _insurgent_rally_spaces("directorio")
		if not rally_spaces.is_empty():
			var _sp := rally_spaces.slice(0, 3)
			_run(ops.rally({"faction": "directorio", "spaces": _sp, "choices": _rally_choices("directorio", _sp)}))
			_directorio_subvert()
			return "rally"

	# 8.6.4 Attacco se aggiungerebbe Controllo DR / rimuove nemici
	var atk := _spaces_with_attack("directorio")
	if not atk.is_empty():
		_run(ops.attack({"faction": "directorio", "spaces": atk.slice(0, 3)}))
		return "attack"

	# 8.6.3 Marcia di ripiego
	if _insurgent_march("directorio"):
		_directorio_subvert()
		return "march"
	return "pass"


func _directorio_subvert() -> void:
	for sid in _ids():
		if state.space_state(sid).control == "directorio" \
				and state.game_def.space(sid).type == CoinEnums.SpaceType.PROVINCE:
			_run(specials.subvert({"space": sid}))
			return


# ---------------------------------------------------------------------------
# 8.7 26 LUGLIO
# ---------------------------------------------------------------------------

func _m26_turn() -> String:
	# 8.7.1 Terrorismo (Sequestro/Sabotaggio/spostamento Supporto)
	var terror_spaces: Array = []
	for sid in _spaces_with_underground("m26"):
		var sd: SpaceDef = state.game_def.space(sid)
		var s: int = state.space_state(sid).support
		# EC non sabotato, o Città/Provincia con Supporto o Neutrale
		if _is_ec(sid) and state.space_state(sid).marker("sabotage") == 0:
			terror_spaces.append(sid)
		elif sd.has_population() and s >= 0:
			terror_spaces.append(sid)
	if not terror_spaces.is_empty():
		_run(ops.terror({"faction": "m26", "spaces": [terror_spaces[0]]}))
		_m26_kidnap(terror_spaces[0])
		return "terror"

	# 8.7.2 Riorganizzazione
	if state.available("m26", "guerrilla") >= 6 or _can_place_base("m26"):
		var rally_spaces := _insurgent_rally_spaces("m26")
		if not rally_spaces.is_empty():
			var _sp := rally_spaces.slice(0, 3)
			_run(ops.rally({"faction": "m26", "spaces": _sp, "choices": _rally_choices("m26", _sp)}))
			_m26_infiltrate()
			return "rally"

	# 8.7.4 Attacco se >=4 Guerriglie + cubo
	var atk: Array = []
	for sid in _spaces_with_attack("m26"):
		if state.space_state(sid).count("m26", "guerrilla") >= 4:
			atk.append(sid)
	if not atk.is_empty():
		_run(ops.attack({"faction": "m26", "spaces": atk.slice(0, 2)}))
		return "attack"

	# 8.7.3 Marcia
	if _insurgent_march("m26"):
		_m26_infiltrate()
		return "march"
	return "pass"


func _m26_kidnap(sid: String) -> void:
	var st: SpaceState = state.space_state(sid)
	if st.count("m26", "guerrilla") <= st.count("government", "police"):
		return
	var sd: SpaceDef = state.game_def.space(sid)
	var target := "government"
	if st.count("syndicate", "casino", "open") > 0 and not (sd.type == CoinEnums.SpaceType.CITY):
		target = "syndicate"
	_run(specials.kidnap({"space": sid, "target": target}))


func _m26_infiltrate() -> void:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.support > 0:
			continue
		if st.count("government", "troops") + st.count("government", "police") == 0:
			continue
		if specials._has_or_adjacent_underground("m26", sid):
			_run(specials.infiltrate({"space": sid}))
			return


# ---------------------------------------------------------------------------
# 8.8 GOVERNO
# ---------------------------------------------------------------------------

func _government_turn() -> String:
	var n_spaces: int = [4, 3, 2][int(state.tracks.get("us_alliance", 0))]

	# 8.8.2 Addestramento: se una Città o Base Govt manca di Controllo/Truppe/Polizia
	var train_spaces := _government_train_spaces()
	if not train_spaces.is_empty():
		var chosen: Array = train_spaces.slice(0, n_spaces)
		var place := {}
		for sid in chosen:
			place[sid] = _government_cube_fill(sid)
		_run(ops.train({"spaces": chosen, "place": place}))
		_government_transport()
		return "train"

	# 8.8.3 Guarnigione: EC con Guerriglie M26 clandestine o > cubi
	if _government_needs_garrison():
		_run(ops.garrison({"moves": _government_garrison_moves(), "assault_ec": _first_ec_with_enemy()}))
		_government_air_or_reprisal()
		return "garrison"

	# 8.8.5 Assalto: se rimuove Basi / 3+ Guerriglie / aggiunge Controllo
	var assault_spaces := _government_assault_spaces()
	if not assault_spaces.is_empty():
		_run(ops.assault({"spaces": assault_spaces.slice(0, n_spaces)}))
		_government_air_or_reprisal()
		return "assault"

	# 8.8.4 Perlustrazione (attiva Guerriglie) di ripiego
	var sweep_spaces := _government_sweep_spaces()
	if not sweep_spaces.is_empty():
		_run(ops.sweep({"spaces": sweep_spaces.slice(0, n_spaces)}))
		_government_air_or_reprisal()
		return "sweep"

	return "pass"


func _government_train_spaces() -> Array:
	var out: Array = []
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		var is_target := sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0
		if not is_target:
			continue
		if st.control != "government" or st.count("government", "police") == 0 or st.count("government", "troops") == 0:
			out.append(sid)
	return out


func _government_cube_fill(sid: String) -> Dictionary:
	# Porta fino a 4 cubi, preferendo Polizia poi Truppe secondo disponibilità
	var st: SpaceState = state.space_state(sid)
	var cur := st.count("government", "troops") + st.count("government", "police")
	var need: int = clampi(4 - cur, 0, 4)
	var police: int = mini(need, state.available("government", "police"))
	var troops: int = mini(need - police, state.available("government", "troops"))
	return {"police": police, "troops": troops}


func _government_needs_garrison() -> bool:
	for sid in _ids():
		if not _is_ec(sid):
			continue
		var st: SpaceState = state.space_state(sid)
		var m26g := st.count("m26", "guerrilla")
		var cubes := st.count("government", "troops") + st.count("government", "police")
		if st.count("m26", "guerrilla", "underground") > 0 or m26g > cubes:
			if m26g > 0:
				return true
	return false


func _government_garrison_moves() -> Array:
	# Sposta Polizia verso gli EC con Guerriglie M26 (semplificato: dal maggior numero di Polizia)
	var moves: Array = []
	var source := _space_with_most("government", "police")
	for sid in _ids():
		if _is_ec(sid) and state.space_state(sid).count("m26", "guerrilla") > 0 and source != "":
			moves.append({"type": "police", "from": source, "to": sid, "count": 1})
			break
	return moves


func _first_ec_with_enemy() -> String:
	for sid in _ids():
		if _is_ec(sid) and state.space_state(sid).count("m26", "guerrilla", "active") > 0:
			return sid
	return ""


func _government_assault_spaces() -> Array:
	var out: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var enemy_active := st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active")
		var enemy_base := st.count("m26", "base") + st.count("directorio", "base")
		if st.count("government", "troops") > 0 and (enemy_active >= 3 or enemy_base > 0):
			out.append(sid)
	return out


func _government_sweep_spaces() -> Array:
	var out: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var und := st.count("m26", "guerrilla", "underground") + st.count("directorio", "guerrilla", "underground")
		if und > 0 and st.count("government", "troops") + st.count("government", "police") > 0:
			out.append(sid)
	return out


func _government_transport() -> void:
	var src := _space_with_most("government", "troops")
	if src == "":
		return
	# verso una Provincia con Polizia ma senza Truppe
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.type == CoinEnums.SpaceType.PROVINCE and st.count("government", "police") > 0 \
				and st.count("government", "troops") == 0:
			_run(specials.transport({"from": src, "to": sid, "count": 2}))
			return


func _government_air_or_reprisal() -> void:
	if mod.is_embargo(state):
		_government_reprisal()
		return
	# Attacco Aereo su una Provincia/EC con Base o Guerriglia Attiva nemica
	for sid in _ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.type == CoinEnums.SpaceType.CITY:
			continue
		var st: SpaceState = state.space_state(sid)
		var target := st.count("m26", "base") + st.count("directorio", "base") \
			+ st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active")
		if target > 0:
			_run(specials.air_strike({"space": sid}))
			return
	_government_reprisal()


func _government_reprisal() -> void:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.control == "government" and st.support < 0:
			_run(specials.reprisal({"space": sid}))
			return


# ---------------------------------------------------------------------------
# Helper condivisi per gli Insorgenti
# ---------------------------------------------------------------------------

func _spaces_with_underground(faction: String) -> Array:
	var out: Array = []
	for sid in _ids():
		if _has_underground(faction, sid):
			out.append(sid)
	return out


func _spaces_with_attack(faction: String) -> Array:
	var out: Array = []
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count(faction, "guerrilla") < 1:
			continue
		var enemies := 0
		for e in ["government", "m26", "directorio", "syndicate"]:
			if e != faction:
				enemies += st.count(e)
		if enemies > 0:
			out.append(sid)
	return out


## Scelte di Rally per spazio: costruisci Base se possibile, altrimenti Guerriglie extra,
## altrimenti piazza 1 Guerriglia. Le Basi contano direttamente per la vittoria insorgente.
func _rally_choices(faction: String, spaces: Array) -> Dictionary:
	var ch := {}
	for sid in spaces:
		var st: SpaceState = state.space_state(sid)
		if st.count(faction, "base") > 0:
			ch[sid] = "extra"
		elif st.count(faction, "guerrilla") >= 2 and mod.can_place_base(state, sid, false):
			ch[sid] = "base"
		else:
			ch[sid] = "place"
	return ch


func _insurgent_rally_spaces(faction: String) -> Array:
	# Province/Città valide secondo i vincoli di Supporto della Fazione
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
	# Priorità: spazi dove la Fazione ha già Basi, poi Guerriglie, poi altri
	out.sort_custom(func(a, b): return _rally_score(faction, a) > _rally_score(faction, b))
	return out


func _rally_score(faction: String, sid: String) -> int:
	var st: SpaceState = state.space_state(sid)
	return st.count(faction, "base") * 10 + st.count(faction, "guerrilla")


func _insurgent_march(faction: String) -> bool:
	# Marcia 1 Guerriglia verso un EC privo di pezzi della Fazione, se adiacente
	for sid in _ids():
		if state.space_state(sid).count(faction, "guerrilla") == 0:
			continue
		for adj in state.game_def.space(sid).adjacent:
			if _is_ec(adj) and state.space_state(adj).count(faction) == 0:
				_run(ops.march({"faction": faction, "moves": [{"from": sid, "to": adj, "count": 1}]}))
				return true
	return false


func _can_place_base(faction: String) -> bool:
	for sid in _ids():
		var st: SpaceState = state.space_state(sid)
		if st.count(faction, "guerrilla") >= 2 and mod.can_place_base(state, sid, false):
			return true
	return false


func _space_with_most(faction: String, type: String) -> String:
	var best := ""
	var best_n := 0
	for sid in _ids():
		var n := state.space_state(sid).count(faction, type)
		if n > best_n:
			best_n = n
			best = sid
	return best
