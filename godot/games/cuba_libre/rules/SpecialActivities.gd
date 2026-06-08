class_name CubaLibreSpecials
extends RefCounted

## Attività Speciali di Cuba Libre (cap. 4). Stesso schema di risultato delle Operazioni:
##   { "ok": bool, "error": String, "cost": int, "log": Array }
## Il rispetto dell'abbinamento Operazione+Attività e della tempistica è gestito dal
## livello superiore (sequenza di gioco); qui si valida e si applica l'effetto.

var state: GameState
var mod: CubaLibreModule


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module


func _ok(cost: int, log: Array = []) -> Dictionary:
	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	return {"ok": true, "error": "", "cost": cost, "log": log}


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "cost": 0, "log": []}


func _adjacent(a: String, b: String) -> bool:
	var sd: SpaceDef = state.game_def.space(a)
	return sd != null and sd.adjacent.has(b)


# ===========================================================================
# GOVERNO
# ===========================================================================

## Trasporto (4.2.1): muove fino a 3 Truppe da una Città o Base a 1 spazio qualsiasi.
func transport(params: Dictionary) -> Dictionary:
	var from_id: String = params.get("from", "")
	var to_id: String = params.get("to", "")
	var count: int = mini(int(params.get("count", 0)), 3)
	var sd: SpaceDef = state.game_def.space(from_id)
	var st: SpaceState = state.space_state(from_id)
	if sd == null or state.game_def.space(to_id) == null:
		return _err("Spazi non validi")
	if sd.type != CoinEnums.SpaceType.CITY and st.count("government", "base") == 0:
		return _err("Il Trasporto parte solo da una Città o da una Base Govt")
	var moved := state.move_pieces("government", "troops", from_id, to_id, count, "")
	if moved == 0:
		return _err("Trasporto: nessuna Truppa da spostare da %s" % from_id)
	return _ok(0, ["Trasporto: %d Truppe %s -> %s" % [moved, from_id, to_id]])


## Attacco Aereo (4.2.2): rimuove 1 Guerriglia Attiva o (se assente) 1 Base, in 1
## Provincia o EC (non Città). Vietato durante Embargo.
func air_strike(params: Dictionary) -> Dictionary:
	if mod.is_embargo(state):
		return _err("Nessun Attacco Aereo durante l'Embargo")
	var sid: String = params.get("space", "")
	var sd: SpaceDef = state.game_def.space(sid)
	if sd == null or sd.type == CoinEnums.SpaceType.CITY:
		return _err("Attacco Aereo solo in Provincia o EC")
	# Momentum "Guantánamo Bay": l'Attacco Aereo rimuove 2 pezzi invece di 1
	var cap: int = 2 if mod.has_momentum(state, "Guantánamo Bay") else 1
	var removed := mod.remove_enemy_pieces(state, sid, cap, "government",
		{"active_g": true, "underground_g": false, "cubes": false, "bases": true})
	if removed == 0:
		return _err("Nessun bersaglio per l'Attacco Aereo a %s" % sid)
	return _ok(0, ["Attacco Aereo a %s: rimossi %d pezzi" % [sid, removed]])


## Rappresaglia (4.2.3): in 1 spazio Controllato dal Governo, pone Terrore, sposta
## l'Opposizione di 1 verso Neutrale e sposta 1 Guerriglia in uno spazio adiacente.
## params: { space, move:{faction, to} }
func reprisal(params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var st: SpaceState = state.space_state(sid)
	if st == null or st.control != "government":
		return _err("Rappresaglia solo in spazio Controllato dal Governo")
	var log: Array = []
	st.add_marker("terror", 1)
	if st.support < 0:
		st.support = (st.support + 1) as CoinEnums.Support
	log.append("Rappresaglia: Terrore a %s (Opp -> Neutrale)" % sid)
	var mv: Dictionary = params.get("move", {})
	if not mv.is_empty():
		var gf: String = mv.get("faction", "")
		var to_id: String = mv.get("to", "")
		if _adjacent(sid, to_id) and st.count(gf, "guerrilla") > 0:
			# sposta 1 Guerriglia (preferendo Attiva)
			var moved := state.move_pieces(gf, "guerrilla", sid, to_id, 1, "active")
			if moved == 0:
				moved = state.move_pieces(gf, "guerrilla", sid, to_id, 1, "underground")
			if moved > 0:
				log.append("Rappresaglia: 1 Guerriglia di %s %s -> %s" % [gf, sid, to_id])
	return _ok(0, log)


# ===========================================================================
# 26 LUGLIO
# ===========================================================================

## Infiltrazione (4.3.1): rimpiazza 1 cubo (Polizia, se c'è, altrimenti Truppe) con
## una Guerriglia del 26 Luglio in 1 spazio privo di Supporto, con o adiacente a una
## Guerriglia M26 Clandestina. Requisizione del Denaro.
func infiltrate(params: Dictionary) -> Dictionary:
	return _infiltrate_for("m26", params)


func _infiltrate_for(faction: String, params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var st: SpaceState = state.space_state(sid)
	if st == null:
		return _err("Spazio non valido")
	if st.support > 0:
		return _err("Infiltrazione non in spazi con Supporto")
	if not _has_or_adjacent_underground(faction, sid):
		return _err("Serve una Guerriglia %s Clandestina in %s o adiacente" % [faction, sid])
	var removed_police := st.remove_piece("government", "police", 1, "")
	if removed_police == 0:
		st.remove_piece("government", "troops", 1, "")
	state.place_from_available(faction, "guerrilla", sid, 1)
	# Requisizione: il Denaro eventuale resta con una Guerriglia della Fazione
	return _ok(0, ["Infiltrazione di %s a %s" % [faction, sid]])


func _has_or_adjacent_underground(faction: String, sid: String) -> bool:
	if state.space_state(sid).count(faction, "guerrilla", "underground") > 0:
		return true
	for adj in state.game_def.space(sid).adjacent:
		if state.space_state(adj).count(faction, "guerrilla", "underground") > 0:
			return true
	return false


## Imboscata (4.3.2 / 4.4.2): in 1 spazio scelto per l'Attacco con Guerriglia Clandestina,
## l'Attacco ha successo automatico (no tiro): attiva 1 Clandestina, rimuove 2 nemici,
## piazza 1 Guerriglia come se avesse tirato "1".
func ambush(faction: String, params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var st: SpaceState = state.space_state(sid)
	if st == null or st.count(faction, "guerrilla", "underground") < 1:
		return _err("Serve 1 Guerriglia %s Clandestina a %s" % [faction, sid])
	state.flip_pieces(faction, "guerrilla", sid, "underground", "active", 1)
	var removed := mod.remove_enemy_pieces(state, sid, 2, faction,
		{"active_g": true, "underground_g": true, "cubes": true, "bases": true})
	state.place_from_available(faction, "guerrilla", sid, 1)
	return _ok(0, ["Imboscata di %s a %s: rimossi %d nemici" % [faction, sid, removed]])


## Sequestro/Kidnap (4.3.3): trasferisce Risorse (tiro di dado) o Denaro dal bersaglio
## al 26 Luglio, poi chiude 1 Casinò aperto nello spazio.
## params: { space, target:"government"|"syndicate", die? }
func kidnap(params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var target: String = params.get("target", "")
	var st: SpaceState = state.space_state(sid)
	if st == null:
		return _err("Spazio non valido")
	if st.count("m26", "guerrilla") <= st.count("government", "police"):
		return _err("Sequestro: servono più Guerriglie M26 che Polizia a %s" % sid)
	var log: Array = []
	# Denaro del riscatto: se il bersaglio ha Denaro qui, trasferiscine 1 invece di tirare
	if st.cash_for(target) > 0:
		state.transfer_cash(sid, target, "m26", 1)
		log.append("Sequestro: 1 Denaro del Riscatto da %s a M26 a %s" % [target, sid])
	else:
		var die: int = int(params.get("die", randi() % 6 + 1))
		var avail := state.get_resources(target)
		var amt: int = mini(die, avail)
		state.add_resources(target, -amt)
		state.add_resources("m26", amt)
		log.append("Sequestro: %d Risorse da %s a M26 (tiro %d)" % [amt, target, die])
	# Chiudi 1 Casinò aperto nello spazio
	state.flip_pieces("syndicate", "casino", sid, "open", "closed", 1)
	return _ok(0, log)


# ===========================================================================
# DIRECTORIO
# ===========================================================================

## Sovversione (4.4.1): aggiunge la Popolazione della Provincia alle Risorse DR e la
## rende Neutrale. Solo in 1 Provincia con Controllo DR.
func subvert(params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var sd: SpaceDef = state.game_def.space(sid)
	var st: SpaceState = state.space_state(sid)
	if sd == null or sd.type != CoinEnums.SpaceType.PROVINCE:
		return _err("Sovversione solo in una Provincia")
	if st.control != "directorio":
		return _err("Sovversione richiede Controllo del Directorio a %s" % sid)
	state.add_resources("directorio", sd.pop)
	st.support = CoinEnums.Support.NEUTRAL
	return _ok(0, ["Sovversione a %s: +%d Risorse DR, spazio Neutrale" % [sid, sd.pop]])


func ambush_dr(params: Dictionary) -> Dictionary:
	return ambush("directorio", params)


## Assassinio (4.4.3): rimuove o chiude 1 pezzo nemico in 1 spazio scelto per il Terror DR,
## se le Guerriglie DR superano la Polizia. params: { space }
func assassinate(params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var st: SpaceState = state.space_state(sid)
	if st == null:
		return _err("Spazio non valido")
	if st.count("directorio", "guerrilla") <= st.count("government", "police"):
		return _err("Assassinio: servono più Guerriglie DR che Polizia a %s" % sid)
	# Rimuove 1 qualsiasi pezzo nemico (anche una Base protetta) — niente protezione Basi
	var removed := mod.remove_enemy_pieces(state, sid, 1, "directorio",
		{"active_g": true, "underground_g": true, "cubes": true, "bases": false})
	if removed == 0:
		# nessun non-base: rimuovi/chiudi una Base nemica
		removed = _remove_any_enemy_base(sid, "directorio")
	if removed == 0:
		return _err("Nessun bersaglio per l'Assassinio a %s" % sid)
	return _ok(0, ["Assassinio a %s" % sid])


## Numero di bersagli che la Corruzione potrebbe colpire nello spazio, per l'azione scelta.
## Serve a impedire una Corruzione senza effetto (che sprecherebbe 3 Risorse).
func _bribe_targets(st: SpaceState, action: String) -> int:
	var n := 0
	match action:
		"cubes":
			for fid in ["government", "m26", "directorio"]:
				n += st.count(fid, "police") + st.count(fid, "troops")
		"guerrillas_remove":
			for fid in ["m26", "directorio"]:
				n += st.count(fid, "guerrilla", "active") + st.count(fid, "guerrilla", "underground")
		"guerrillas_flip":
			for fid in ["m26", "directorio"]:
				n += st.count(fid, "guerrilla", "underground")
		"base":
			# _remove_any_enemy_base (attaccante=syndicate) colpisce solo Basi Govt/26-7.
			for fid in ["government", "m26"]:
				n += st.count(fid, "base")
	return n


func _remove_any_enemy_base(sid: String, attacker: String) -> int:
	var st: SpaceState = state.space_state(sid)
	for fid in ["government", "m26", "syndicate"]:
		if fid == attacker:
			continue
		if st.count(fid, "base") > 0:
			st.remove_piece(fid, "base", 1, "")
			return 1
		if fid == "syndicate" and st.count("syndicate", "casino", "open") > 0:
			state.flip_pieces("syndicate", "casino", sid, "open", "closed", 1)
			return 1
	return 0


# ===========================================================================
# SINDACATO
# ===========================================================================

## Profitto (4.5.1): accumula Denaro (1 segnalino in 1-2 spazi con Casinò aperto) OPPURE
## chiude Casinò / rimuove Denaro proprio per +3 Risorse ciascuno.
## params: { mode:"cash"|"convert", spaces:[id], close:[id] }
func profit(params: Dictionary) -> Dictionary:
	var mode: String = params.get("mode", "cash")
	var log: Array = []
	if mode == "cash":
		var spaces: Array = params.get("spaces", [])
		if spaces.size() > 2:
			return _err("Profitto: massimo 2 spazi")
		for sid in spaces:
			if state.space_state(sid).count("syndicate", "casino", "open") < 1:
				return _err("Profitto richiede un Casinò aperto a %s" % sid)
			var placed := state.place_cash(sid, "syndicate", 1)
			log.append("Profitto: +%d Denaro a %s" % [placed, sid])
		return _ok(0, log)
	else:
		# Converti: chiudi Casinò aperti e rimuovi Denaro proprio -> +3 Risorse ciascuno
		var gained := 0
		for sid in params.get("close", []):
			var n := state.flip_pieces("syndicate", "casino", sid, "open", "closed", 1)
			gained += 3 * n
		# Rimuove tutto il Denaro del Sindacato sulla mappa
		for sid in state.game_def.space_ids():
			var c := state.space_state(sid).cash_for("syndicate")
			if c > 0:
				state.remove_cash(sid, "syndicate", c)
				gained += 3 * c
		state.add_resources("syndicate", gained)
		log.append("Profitto: +%d Risorse Sindacato (conversione)" % gained)
		return _ok(0, log)


## Dimostrazione di Forza/Muscle (4.5.3): muove 1-2 Polizia (verso Città) o 1-2 Truppe
## (verso Provincia/EC) a 1 destinazione con Casinò aperto o EC.
## params: { type:"police"|"troops", from, to, count }
func muscle(params: Dictionary) -> Dictionary:
	var t: String = params.get("type", "police")
	var from_id: String = params.get("from", "")
	var to_id: String = params.get("to", "")
	var count: int = clampi(int(params.get("count", 1)), 1, 2)
	var dest: SpaceDef = state.game_def.space(to_id)
	if dest == null:
		return _err("Destinazione non valida")
	var dest_ok := dest.is_economic() or state.space_state(to_id).count("syndicate", "casino", "open") > 0
	if not dest_ok:
		return _err("Muscle: la destinazione deve avere un Casinò aperto o essere un EC")
	if t == "police" and dest.type != CoinEnums.SpaceType.CITY:
		return _err("La Polizia può essere mossa solo verso una Città")
	if t == "troops" and dest.type == CoinEnums.SpaceType.CITY:
		return _err("Le Truppe verso Provincia o EC, non Città")
	var moved := state.move_pieces("government", t, from_id, to_id, count, "")
	if moved == 0:
		return _err("Muscle: nessun %s da spostare da %s" % [t, from_id])
	return _ok(0, ["Muscle: %d %s -> %s" % [moved, t, to_id]])


## Corruzione/Bribe (4.5.4): -3 Risorse del Sindacato per spazio. Rimuove fino a 2 cubi,
## o rimuove/gira fino a 2 Guerriglie, o rimuove 1 Base nemica. Unica Att.Speciale con costo.
## params: { space, action:"cubes"|"guerrillas_remove"|"guerrillas_flip"|"base", count }
func bribe(params: Dictionary) -> Dictionary:
	var sid: String = params.get("space", "")
	var st: SpaceState = state.space_state(sid)
	if st == null:
		return _err("Spazio non valido")
	if state.get_resources("syndicate") < 3:
		return _err("Servono 3 Risorse per la Corruzione")
	var action: String = params.get("action", "cubes")
	var count: int = clampi(int(params.get("count", 1)), 1, 2)
	# Niente bersagli validi → l'azione non ha effetto: non eseguirla (e non spendere Risorse).
	if _bribe_targets(st, action) == 0:
		return _err("Corruzione a %s: nessun bersaglio valido" % sid)
	state.add_resources("syndicate", -3)
	var log: Array = []
	match action:
		"cubes":
			var removed := mod.remove_enemy_pieces(state, sid, count, "syndicate",
				{"active_g": false, "underground_g": false, "cubes": true, "bases": false})
			log.append("Corruzione a %s: rimossi %d cubi" % [sid, removed])
		"guerrillas_remove":
			var removed := mod.remove_enemy_pieces(state, sid, count, "syndicate",
				{"active_g": true, "underground_g": true, "cubes": false, "bases": false})
			log.append("Corruzione a %s: rimosse %d Guerriglie" % [sid, removed])
		"guerrillas_flip":
			var n := mod.activate_guerrillas(state, sid, count, "syndicate")
			log.append("Corruzione a %s: girate %d Guerriglie" % [sid, n])
		"base":
			var r := _remove_any_enemy_base(sid, "syndicate")
			log.append("Corruzione a %s: rimossa %d Base nemica" % [sid, r])
	return _ok(3, log)
