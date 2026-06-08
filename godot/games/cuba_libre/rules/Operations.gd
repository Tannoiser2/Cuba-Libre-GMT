class_name CubaLibreOperations
extends RefCounted

## Operazioni di Cuba Libre (cap. 3). Ogni metodo valida i parametri, paga le Risorse,
## applica gli effetti e ricalcola il Controllo. Restituisce un dizionario risultato:
##   { "ok": bool, "error": String, "cost": int, "log": Array[String] }
##
## I parametri di scelta (spazi, piazzamenti, bersagli) sono decisi dal chiamante
## (UI o bot); il motore valida e applica in modo deterministico.

var state: GameState
var mod: CubaLibreModule


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

func _ok(cost: int, log: Array = []) -> Dictionary:
	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	return {"ok": true, "error": "", "cost": cost, "log": log}


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "cost": 0, "log": []}


func _can_pay(faction: String, amount: int) -> bool:
	# Le Fazioni NP che non tracciano Risorse possono sempre pagare (Calixto C8.5.9).
	if not state.tracks_resources(faction):
		return true
	return state.get_resources(faction) >= amount


func _is_support(space_id: String) -> bool:
	return state.space_state(space_id).support > 0


func _is_opposition(space_id: String) -> bool:
	return state.space_state(space_id).support < 0


func _adjacent(a: String, b: String) -> bool:
	var sd: SpaceDef = state.game_def.space(a)
	return sd != null and sd.adjacent.has(b)


## Raggiungibile in Marcia: adiacente, oppure entro 2 spazi se dist2 (Capacità Morgan).
func _march_reachable(a: String, b: String, dist2: bool) -> bool:
	if _adjacent(a, b):
		return true
	if dist2:
		for mid in state.game_def.space(a).adjacent:
			if _adjacent(mid, b):
				return true
	return false


# ===========================================================================
# OPERAZIONI DEL GOVERNO (COIN)
# ===========================================================================

## Train / Addestramento (3.2.1).
## params: { spaces:[id], place:{id:{troops,police}}, special:{type:"base"|"civic", space, steps?} }
func train(params: Dictionary) -> Dictionary:
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := mod.coin_op_cost(state) * spaces.size()
	if not _can_pay("government", cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	# Valida spazi
	for sid in spaces:
		var sd: SpaceDef = state.game_def.space(sid)
		if sd == null or not sd.has_population():
			return _err("%s non è una Provincia o Città" % str(sid))

	state.add_resources("government", -cost)
	var log: Array = []
	# Piazzamento cubi
	var place: Dictionary = params.get("place", {})
	for sid in spaces:
		var sd: SpaceDef = state.game_def.space(sid)
		var allowed := sd.type == CoinEnums.SpaceType.CITY \
			or state.space_state(sid).count("government", "base") > 0
		if not allowed:
			continue
		var req: Dictionary = place.get(sid, {})
		var n_t := int(req.get("troops", 0))
		var n_p := int(req.get("police", 0))
		if n_t + n_p > 4:
			return _err("Massimo 4 cubi per spazio in Addestramento (%s)" % str(sid))
		state.place_from_available("government", "troops", sid, n_t)
		state.place_from_available("government", "police", sid, n_p)
		if n_t + n_p > 0:
			log.append("Addestramento: +%dT +%dP a %s" % [n_t, n_p, sid])

	# Azione speciale in 1 spazio
	var special: Dictionary = params.get("special", {})
	if not special.is_empty():
		var sid: String = special.get("space", "")
		if not spaces.has(sid):
			return _err("L'azione speciale di Train deve essere in uno spazio scelto")
		match String(special.get("type", "")):
			"base":
				var st: SpaceState = state.space_state(sid)
				if st.count("government", "troops") + st.count("government", "police") < 2:
					return _err("Servono 2 cubi Govt per costruire una Base")
				if not mod.can_place_base(state, sid, false):
					return _err("Raggruppamento: impossibile piazzare una Base a %s" % sid)
				# Rimuovi 2 cubi (prima Polizia poi Truppe) e piazza 1 Base
				var removed := st.remove_piece("government", "police", 2, "")
				if removed < 2:
					st.remove_piece("government", "troops", 2 - removed, "")
				state.place_from_available("government", "base", sid, 1)
				log.append("Train: nuova Base Govt a %s" % sid)
			"civic":
				var r := _civic_action(sid, int(special.get("steps", 1)))
				if not r.ok:
					return _err(r.error)
				log.append_array(r.log)
	return _ok(cost, log)


## Azione Civica (6.3.2): 4 Risorse per passo; rimuove Terrore o sposta verso Supporto Attivo.
func _civic_action(space_id: String, steps: int) -> Dictionary:
	var st: SpaceState = state.space_state(space_id)
	if st.control != "government":
		return _err("Azione Civica richiede Controllo del Governo a %s" % space_id)
	if st.count("government", "troops") == 0 or st.count("government", "police") == 0:
		return _err("Azione Civica richiede Truppe e Polizia a %s" % space_id)
	var cost := 4 * steps
	if not _can_pay("government", cost):
		return _err("Risorse insufficienti per l'Azione Civica")
	state.add_resources("government", -cost)
	var log: Array = []
	for i in range(steps):
		if st.marker("terror") > 0:
			st.add_marker("terror", -1)
			log.append("Azione Civica: -1 Terrore a %s" % space_id)
		elif st.support < CoinEnums.Support.ACTIVE_SUPPORT:
			st.support = (st.support + 1) as CoinEnums.Support
			log.append("Azione Civica: Supporto +1 a %s" % space_id)
	return {"ok": true, "error": "", "cost": cost, "log": log}


## Sweep / Perlustrazione (3.2.3).
## params: { spaces:[id], moves:[{from,to,count}] }  (solo Truppe, adiacenti)
func sweep(params: Dictionary) -> Dictionary:
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := mod.coin_op_cost(state) * spaces.size()
	if not _can_pay("government", cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	state.add_resources("government", -cost)
	var log: Array = []
	# Movimento Truppe adiacenti
	for m in params.get("moves", []):
		if not _adjacent(m["from"], m["to"]):
			return _err("Movimento non adiacente in Sweep: %s->%s" % [m["from"], m["to"]])
		state.move_pieces("government", "troops", m["from"], m["to"], int(m["count"]), "")
	# Attivazione
	for sid in spaces:
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		var cubes := st.count("government", "troops") + st.count("government", "police")
		var act := cubes if sd.terrain != "forest" else int(cubes / 2)
		var n := mod.activate_guerrillas(state, sid, act)
		if n > 0:
			log.append("Sweep: attivate %d Guerriglie a %s" % [n, sid])
	return _ok(cost, log)


## Assault / Assalto (3.2.4). params: { spaces:[id] }
func assault(params: Dictionary) -> Dictionary:
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := 3 * spaces.size()
	if not _can_pay("government", cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	state.add_resources("government", -cost)
	var log: Array = []
	for sid in spaces:
		var removed := _assault_in_space(sid)
		log.append("Assalto a %s: rimossi %d pezzi" % [sid, removed])
	return _ok(cost, log)


func _assault_in_space(space_id: String) -> int:
	var sd: SpaceDef = state.game_def.space(space_id)
	var st: SpaceState = state.space_state(space_id)
	var troops := st.count("government", "troops")
	# Momentum "S.I.M.": la Polizia conta come Truppe nell'Assalto
	if mod.has_momentum(state, "S.I.M."):
		troops += st.count("government", "police")
	# Momentum "Sánchez Mosquera": l'Assalto tratta la Montagna come Città
	var as_city := sd.type == CoinEnums.SpaceType.CITY or sd.is_economic()
	if sd.terrain == "mountain" and mod.has_momentum(state, "Sánchez Mosquera"):
		as_city = true
	var capacity: int
	if sd.terrain == "mountain" and not mod.has_momentum(state, "Sánchez Mosquera"):
		capacity = int(troops / 2)
	elif as_city:
		capacity = troops + int(troops / 2)
	else:
		capacity = troops
	return mod.remove_enemy_pieces(state, space_id, capacity, "government",
		{"active_g": true, "underground_g": false, "cubes": false, "bases": true})


## Garrison / Guarnigione (3.2.2). params: { moves:[{type,from,to,count}], assault_ec? }
func garrison(params: Dictionary) -> Dictionary:
	var cost := mod.coin_op_cost(state)  # costo totale, non per spazio
	if not _can_pay("government", cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	state.add_resources("government", -cost)
	var log: Array = []
	# Muovi cubi (Truppe/Polizia) verso EC o Città
	for m in params.get("moves", []):
		var dest: SpaceDef = state.game_def.space(m["to"])
		if dest == null or not (dest.is_economic() or dest.type == CoinEnums.SpaceType.CITY):
			return _err("Garrison: la destinazione %s non è EC né Città" % str(m["to"]))
		var t := String(m.get("type", "troops"))
		state.move_pieces("government", t, m["from"], m["to"], int(m["count"]), "")
	# In ogni EC: attiva 1 Guerriglia per cubo presente
	for sid in state.game_def.space_ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.is_economic():
			continue
		var st: SpaceState = state.space_state(sid)
		var cubes := st.count("government", "troops") + st.count("government", "police")
		if cubes > 0:
			var n := mod.activate_guerrillas(state, sid, cubes)
			if n > 0:
				log.append("Garrison: attivate %d Guerriglie a %s" % [n, sid])
	# Assalto gratuito opzionale in 1 EC
	var ec: String = params.get("assault_ec", "")
	if ec != "":
		var removed := _assault_in_space(ec)
		log.append("Garrison: Assalto gratuito a %s, rimossi %d" % [ec, removed])
	return _ok(cost, log)


# ===========================================================================
# OPERAZIONI DEGLI INSORGENTI
# ===========================================================================

## Rally / Riorganizzazione (3.3.1).
## params: { faction, spaces:[id], choices:{id:"place"|"base"|"flip"|"extra"} }
func rally(params: Dictionary) -> Dictionary:
	var f: String = params.get("faction", "")
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := spaces.size()  # 1 Risorsa per spazio
	if not _can_pay(f, cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	# Vincoli di Supporto
	for sid in spaces:
		var sup: int = state.space_state(sid).support
		if f == "m26" and sup > 0:
			return _err("M26 non può Riorganizzare in spazi con Supporto (%s)" % sid)
		if f == "directorio" and abs(sup) == 2:
			return _err("Directorio non può Riorganizzare in spazi Attivi (%s)" % sid)
	state.add_resources(f, -cost)
	var log: Array = []
	var choices: Dictionary = params.get("choices", {})
	for sid in spaces:
		var st: SpaceState = state.space_state(sid)
		var choice := String(choices.get(sid, "place"))
		var has_base := st.count(f, "base") > 0 if f != "syndicate" else st.count(f, "casino", "open") > 0
		match choice:
			"base":
				if f == "syndicate":
					return _err("Il Sindacato non costruisce Basi con Rally (usa Build)")
				if st.count(f, "guerrilla") < 2:
					return _err("Servono 2 Guerriglie per una Base a %s" % sid)
				if not mod.can_place_base(state, sid, false):
					return _err("Raggruppamento: niente Base a %s" % sid)
				st.remove_piece(f, "guerrilla", 2, "underground")
				state.place_from_available(f, "base", sid, 1)
				log.append("Rally: Base di %s a %s" % [f, sid])
			"flip":
				if not has_base:
					return _err("Serve una Base per girare le Guerriglie a %s" % sid)
				var n := state.flip_pieces(f, "guerrilla", sid, "active", "underground")
				log.append("Rally: girate %d Guerriglie Clandestine a %s" % [n, sid])
			"extra":
				if not has_base:
					return _err("Serve una Base per piazzare Guerriglie extra a %s" % sid)
				var pop := state.game_def.space(sid).pop
				var limit: int
				if f == "m26":
					limit = 2 * st.count(f, "base") + 2 * pop
				else:  # directorio
					limit = st.count(f, "base") + pop
				var placed := state.place_from_available(f, "guerrilla", sid, limit)
				log.append("Rally: +%d Guerriglie di %s a %s" % [placed, f, sid])
			_:  # "place": 1 Guerriglia
				var p := state.place_from_available(f, "guerrilla", sid, 1)
				log.append("Rally: +%d Guerriglia di %s a %s" % [p, f, sid])
	# Capacità "The Guerrilla Life": le Guerriglie 26July restano Clandestine col Rally
	if f == "m26" and mod.has_capability(state, "The Guerrilla Life"):
		for sid in spaces:
			state.flip_pieces("m26", "guerrilla", sid, "active", "underground")
	return _ok(cost, log)


## March / Marcia (3.3.2). params: { faction, moves:[{from,to,count}] }
func march(params: Dictionary) -> Dictionary:
	var f: String = params.get("faction", "")
	var moves: Array = params.get("moves", [])
	# Costo: 1 per destinazione Provincia/Città distinta (0 per EC)
	var dests := {}
	for m in moves:
		dests[m["to"]] = true
	var cost := 0
	for d in dests.keys():
		if not state.game_def.space(d).is_economic():
			cost += 1
	if not _can_pay(f, cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	# Valida adiacenza (Capacità "Morgan": il DR può Marciare entro 2 spazi)
	var dist2: bool = f == "directorio" and mod.has_capability(state, "Morgan")
	for m in moves:
		if not _march_reachable(m["from"], m["to"], dist2):
			return _err("Marcia non raggiungibile: %s->%s" % [m["from"], m["to"]])
	state.add_resources(f, -cost)
	var log: Array = []
	# Esegui i movimenti (le Guerriglie restano Clandestine durante lo spostamento)
	for m in moves:
		var cnt := int(m["count"])
		# muovi prima le Clandestine, poi le Attive
		var moved_u := state.move_pieces(f, "guerrilla", m["from"], m["to"], cnt, "underground")
		if moved_u < cnt:
			state.move_pieces(f, "guerrilla", m["from"], m["to"], cnt - moved_u, "active")
	# Capacità "El Che": il 1º gruppo che Marcia (26July) resta/torna Clandestino, senza Attivarsi
	var el_che_first: bool = f == "m26" and mod.has_capability(state, "El Che")
	# Attivazione: per ogni destinazione, se EC o spazio con Supporto e (guerriglie mosse + cubi) > 3
	for d in dests.keys():
		var sd: SpaceDef = state.game_def.space(d)
		var st: SpaceState = state.space_state(d)
		if el_che_first:
			state.flip_pieces(f, "guerrilla", d, "active", "underground")
			el_che_first = false
			log.append("Marcia (El Che): 1º gruppo di %s resta Clandestino a %s" % [f, d])
			continue
		var moved_here := 0
		for m in moves:
			if m["to"] == d:
				moved_here += int(m["count"])
		var cubes := st.count("government", "troops") + st.count("government", "police")
		if (sd.is_economic() or st.support > 0) and (moved_here + cubes) > 3:
			var n := state.flip_pieces(f, "guerrilla", d, "underground", "active")
			if n > 0:
				log.append("Marcia: attivate %d Guerriglie di %s entrando a %s" % [n, f, d])
	if log.is_empty():
		log.append("Marcia di %s completata" % f)
	return _ok(cost, log)


## Attack / Attacco (3.3.3) - solo M26/DR. params: { faction, spaces:[id], die_rolls?:{id:int} }
func attack(params: Dictionary) -> Dictionary:
	var f: String = params.get("faction", "")
	if f != "m26" and f != "directorio":
		return _err("Solo M26 e Directorio possono Attaccare")
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := spaces.size()
	if not _can_pay(f, cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	# Valida: >=1 Guerriglia propria e >=1 pezzo nemico
	for sid in spaces:
		var st: SpaceState = state.space_state(sid)
		if st.count(f, "guerrilla") < 1:
			return _err("Serve almeno 1 Guerriglia di %s a %s" % [f, sid])
	state.add_resources(f, -cost)
	var log: Array = []
	var die_rolls: Dictionary = params.get("die_rolls", {})
	var targets: Dictionary = params.get("targets", {})
	for sid in spaces:
		var st: SpaceState = state.space_state(sid)
		# Attiva tutte le proprie Guerriglie
		var g := state.flip_pieces(f, "guerrilla", sid, "underground", "active")
		var num_g := st.count(f, "guerrilla")
		var roll := int(die_rolls.get(sid, randi() % 6 + 1))
		if roll <= num_g:
			var removed := mod.remove_enemy_pieces(state, sid, 2, f,
				{"active_g": true, "underground_g": true, "cubes": true, "bases": true},
				String(targets.get(sid, "")))
			log.append("Attacco a %s (tiro %d <= %d): rimossi %d pezzi" % [sid, roll, num_g, removed])
			if roll == 1:
				state.place_from_available(f, "guerrilla", sid, 1)
				log.append("Beni catturati: +1 Guerriglia di %s a %s" % [f, sid])
		else:
			log.append("Attacco a %s fallito (tiro %d > %d)" % [sid, roll, num_g])
	return _ok(cost, log)


## Terror / Terrorismo (3.3.4). params: { faction, spaces:[id] }
func terror(params: Dictionary) -> Dictionary:
	var f: String = params.get("faction", "")
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := 0
	for sid in spaces:
		if not state.game_def.space(sid).is_economic():
			cost += 1
	if not _can_pay(f, cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	for sid in spaces:
		if state.space_state(sid).count(f, "guerrilla", "underground") < 1:
			return _err("Serve 1 Guerriglia Clandestina di %s a %s" % [f, sid])
	state.add_resources(f, -cost)
	var log: Array = []
	for sid in spaces:
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		if int(state.tracks.get("terror_sabotage_used", 0)) >= 20:
			log.append("Niente segnalini Terrore/Sabotaggio disponibili (max 20)")
			continue
		state.flip_pieces(f, "guerrilla", sid, "underground", "active", 1)
		if sd.is_economic():
			if st.marker("sabotage") == 0:
				st.add_marker("sabotage", 1)
				state.tracks["terror_sabotage_used"] = int(state.tracks.get("terror_sabotage_used", 0)) + 1
				log.append("Sabotaggio a %s" % sid)
		else:
			st.add_marker("terror", 1)
			state.tracks["terror_sabotage_used"] = int(state.tracks.get("terror_sabotage_used", 0)) + 1
			if f == "m26":
				# verso Opposizione Attiva
				if st.support > CoinEnums.Support.ACTIVE_OPPOSITION:
					st.support = (st.support - 1) as CoinEnums.Support
			else:
				# verso Neutrale
				if st.support > 0:
					st.support = (st.support - 1) as CoinEnums.Support
				elif st.support < 0:
					st.support = (st.support + 1) as CoinEnums.Support
			log.append("Terrore a %s (Supporto ora %d)" % [sid, st.support])
	return _ok(cost, log)


## Build / Costruzione (3.3.5) - solo Sindacato. params: { spaces:[id], choices:{id:"new"|"open"} }
func build(params: Dictionary) -> Dictionary:
	var spaces: Array = params.get("spaces", [])
	if spaces.is_empty():
		return _err("Nessuno spazio selezionato")
	var cost := 5 * spaces.size()
	if not _can_pay("syndicate", cost):
		return _err("Risorse insufficienti (servono %d)" % cost)
	for sid in spaces:
		var st: SpaceState = state.space_state(sid)
		if st.control != "government" and st.control != "syndicate":
			return _err("Build solo in spazi controllati da Govt o Sindacato (%s)" % sid)
	state.add_resources("syndicate", -cost)
	var log: Array = []
	var choices: Dictionary = params.get("choices", {})
	for sid in spaces:
		var choice := String(choices.get(sid, "new"))
		if choice == "open":
			var n := state.flip_pieces("syndicate", "casino", sid, "closed", "open", 1)
			log.append("Build: aperto %d Casinò a %s" % [n, sid])
		else:
			if not mod.can_place_base(state, sid, true):
				return _err("Raggruppamento: niente Casinò a %s" % sid)
			state.place_from_available("syndicate", "casino", sid, 1, "closed")
			log.append("Build: nuovo Casinò (chiuso) a %s" % sid)
	return _ok(cost, log)
