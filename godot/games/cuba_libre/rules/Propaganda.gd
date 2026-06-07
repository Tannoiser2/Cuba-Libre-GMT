class_name CubaLibrePropaganda
extends RefCounted

## Round di Propaganda di Cuba Libre (cap. 6). Esegue le fasi nell'ordine:
##   Vittoria -> Risorse -> Supporto -> Spostamento -> Sistemazione.
## Le fasi deterministiche (Risorse, Alleanza USA, Sistemazione) sono complete; le
## azioni a scelta del giocatore (Azione Civica, Dimostrazioni, Supporto Espatriati,
## Spostamento) si attivano tramite parametri opzionali.

var state: GameState
var mod: CubaLibreModule


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module


# ---------------------------------------------------------------------------
# 6.1 Vittoria
# ---------------------------------------------------------------------------

## Restituisce { "winner": faction_id|"" , "status": {...} }.
func victory_phase() -> Dictionary:
	var status := mod.victory_status(state)
	var winners: Array = []
	for fid in status.keys():
		if status[fid].get("won", false):
			winners.append(fid)
	var winner := ""
	if winners.size() == 1:
		winner = winners[0]
	elif winners.size() > 1:
		# Risoluzione parità per ordine del modulo
		for fid in mod.tiebreak_order():
			if winners.has(fid):
				winner = fid
				break
	return {"winner": winner, "status": status}


# ---------------------------------------------------------------------------
# 6.2 Risorse
# ---------------------------------------------------------------------------

func resources_phase(cash_policy: Dictionary = {}) -> Array:
	var log: Array = []
	# 6.2.1 Sabotaggio EC dove Guerriglie (M26+DR) > cubi, poi entrate Governo
	for sid in state.game_def.space_ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if not sd.is_economic():
			continue
		var st: SpaceState = state.space_state(sid)
		var ins := st.count("m26", "guerrilla") + st.count("directorio", "guerrilla")
		var cubes := st.count("government", "troops") + st.count("government", "police")
		if ins > cubes and st.marker("sabotage") == 0:
			st.add_marker("sabotage", 1)
			log.append("Sabotaggio automatico a %s" % sid)
	var econ := 0
	for sid in state.game_def.space_ids():
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.is_economic() and state.space_state(sid).marker("sabotage") == 0:
			econ += sd.econ
	var aid := int(state.tracks.get("aid", 0))
	state.add_resources("government", econ + aid)
	log.append("Entrate Governo: +%d (Econ %d + Aiuti %d)" % [econ + aid, econ, aid])

	# 6.2.2 Entrate Insorgenti
	var m26_inc := state.base_count("m26")
	state.add_resources("m26", m26_inc)
	var dr_spaces := 0
	for sid in state.game_def.space_ids():
		if state.space_state(sid).count("directorio") > 0:
			dr_spaces += 1
	state.add_resources("directorio", dr_spaces)
	var syn_inc := 0
	for sid in state.game_def.space_ids():
		var sd: SpaceDef = state.game_def.space(sid)
		var st: SpaceState = state.space_state(sid)
		var syn_g := st.count("syndicate", "guerrilla")
		var police := st.count("government", "police")
		if sd.type == CoinEnums.SpaceType.CITY and syn_g > police:
			syn_inc += sd.pop
		elif sd.is_economic() and st.marker("sabotage") == 0 and syn_g > police:
			syn_inc += sd.econ
		syn_inc += 2 * st.count("syndicate", "casino", "open")
	state.add_resources("syndicate", syn_inc)
	log.append("Entrate: M26 +%d, DR +%d, Sindacato +%d" % [m26_inc, dr_spaces, syn_inc])

	# 6.2.3 Fare la Cresta (Skim): per ogni spazio con Casinò aperto, 2 Risorse al controllante
	for sid in state.game_def.space_ids():
		var st: SpaceState = state.space_state(sid)
		if st.count("syndicate", "casino", "open") > 0:
			var ctrl := st.control
			if ctrl != "" and ctrl != "syndicate":
				var amt: int = mini(2, state.get_resources("syndicate"))
				state.add_resources("syndicate", -amt)
				state.add_resources(ctrl, amt)
				log.append("Cresta: %d Risorse dal Sindacato a %s (%s)" % [amt, ctrl, sid])

	# 6.2.4 Depositi di Denaro (ordine M26, DR, Govt, Sindacato)
	for fid in ["m26", "directorio", "government", "syndicate"]:
		for sid in state.game_def.space_ids():
			var c := state.space_state(sid).cash_for(fid)
			if c <= 0:
				continue
			var policy := String(cash_policy.get(fid, "resources"))
			state.remove_cash(sid, fid, c)
			if policy == "base" and fid != "syndicate" and mod.can_place_base(state, sid, false):
				state.place_from_available(fid, "base", sid, c)
				log.append("Deposito Denaro: %d Base di %s a %s" % [c, fid, sid])
			elif policy == "base" and fid == "syndicate":
				state.flip_pieces("syndicate", "casino", sid, "closed", "open", c)
				log.append("Deposito Denaro: %d Casinò aperti a %s" % [c, sid])
			else:
				state.add_resources(fid, 6 * c)
				log.append("Deposito Denaro: %s +%d Risorse" % [fid, 6 * c])

	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	return log


# ---------------------------------------------------------------------------
# 6.3 Supporto (Alleanza USA; le spese opzionali sono gestite altrove)
# ---------------------------------------------------------------------------

func support_phase() -> Array:
	var log: Array = []
	if state.total_support() <= 18:
		var idx := int(state.tracks.get("us_alliance", 0))
		if idx < 2:
			state.tracks["us_alliance"] = idx + 1
			log.append("Alleanza USA scende di 1 livello")
		var aid := int(state.tracks.get("aid", 0))
		state.tracks["aid"] = maxi(0, aid - 10)
		log.append("Aiuti -10 (ora %d)" % state.tracks["aid"])
	return log


# ---------------------------------------------------------------------------
# 6.5 Sistemazione (Reset)
# ---------------------------------------------------------------------------

func reset_phase() -> Array:
	var log: Array = []
	# Tutte le Fazioni Disponibili
	for f in state.game_def.factions:
		state.eligibility[f.id] = CoinEnums.Eligibility.ELIGIBLE
	# Rimuovi Terrore/Sabotaggio
	for sid in state.game_def.space_ids():
		var st: SpaceState = state.space_state(sid)
		st.set_marker("terror", 0)
		st.set_marker("sabotage", 0)
	state.tracks["terror_sabotage_used"] = 0
	# Scarta Momentum del Governo
	state.active_momentum = PackedStringArray()
	# Guerriglie -> Clandestine, Casinò -> Aperti
	for sid in state.game_def.space_ids():
		for fid in ["m26", "directorio", "syndicate"]:
			state.flip_pieces(fid, "guerrilla", sid, "active", "underground")
		state.flip_pieces("syndicate", "casino", sid, "closed", "open")
	state.recompute_all_control()
	mod._refresh_victory_tracks(state)
	log.append("Sistemazione: Disponibilità ripristinata, marker rimossi, Guerriglie Clandestine, Casinò aperti")
	return log


# ---------------------------------------------------------------------------
# Esecuzione completa del round
# ---------------------------------------------------------------------------

## Esegue l'intero round. `params` può contenere: cash_policy, final (bool).
## Restituisce { winner, log:[...], ended:bool }.
func run(params: Dictionary = {}) -> Dictionary:
	var vp := victory_phase()
	if vp.winner != "":
		return {"winner": vp.winner, "log": ["Vittoria di %s" % vp.winner], "ended": true}
	var log: Array = []
	log.append_array(resources_phase(params.get("cash_policy", {})))
	log.append_array(support_phase())
	if bool(params.get("final", false)):
		# Propaganda finale: niente Spostamento/Sistemazione (6.3.5)
		return {"winner": "", "log": log, "ended": true}
	# (Spostamento del Governo: a scelta del giocatore — gestito dal livello UI)
	log.append_array(reset_phase())
	return {"winner": "", "log": log, "ended": false}
