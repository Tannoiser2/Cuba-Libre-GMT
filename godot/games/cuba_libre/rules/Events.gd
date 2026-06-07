class_name CubaLibreEvents
extends RefCounted

## Motore degli Eventi di Cuba Libre (cap. 5). Per ogni carta con effetto automatizzabile
## c'è un gestore `_ev_<n>(side, faction, params)`; le carte non ancora automatizzate
## restituiscono `manual = true` (la UI mostra il testo e il giocatore applica a mano,
## usando gli strumenti di Operazioni/pezzi).
##
## side: "unshaded" | "shaded"  ·  faction: id della Fazione che svolge l'Evento.

var state: GameState
var mod: CubaLibreModule


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module


func apply(number: int, side: String, faction: String, params: Dictionary = {}) -> Dictionary:
	var card: CardDef = state.game_def.card(number)
	if card == null:
		return {"ok": false, "manual": false, "log": ["Carta %d inesistente" % number]}
	var log: Array = []

	# Effetti duraturi: Capacità Insorgenti / Momentum del Governo
	if card.is_capability and not state.active_capabilities.has(card.title):
		state.active_capabilities.append(card.title)
		log.append("Capacità attivata: %s" % card.title)
	if card.is_momentum and side == "shaded" and not state.active_momentum.has(card.title):
		state.active_momentum.append(card.title)
		log.append("Momentum del Governo: %s" % card.title)

	var method := "_ev_%d" % number
	if has_method(method):
		var res: Dictionary = call(method, side, faction, params)
		log.append_array(res.get("log", []))
		state.recompute_all_control()
		mod._refresh_victory_tracks(state)
		return {"ok": res.get("ok", true), "manual": false, "log": log}

	# Nessun gestore: applicazione manuale
	log.append("Evento «%s» (%s): da applicare manualmente." % [card.title, side])
	return {"ok": true, "manual": true, "log": log}


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

func _cities() -> Array:
	var out: Array = []
	for sid in state.game_def.space_ids():
		if state.game_def.space(sid).type == CoinEnums.SpaceType.CITY:
			out.append(sid)
	return out


func _roll(params: Dictionary) -> int:
	return int(params.get("die", randi() % 6 + 1))


func _shift_support(sid: String, steps: int) -> void:
	## steps>0 verso Supporto Attivo, steps<0 verso Opposizione Attiva
	var st: SpaceState = state.space_state(sid)
	st.support = clampi(st.support + steps, CoinEnums.Support.ACTIVE_OPPOSITION,
		CoinEnums.Support.ACTIVE_SUPPORT) as CoinEnums.Support


# ---------------------------------------------------------------------------
# Gestori degli Eventi (sottoinsieme automatizzato)
# ---------------------------------------------------------------------------

## #7 Election
func _ev_7(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		for c in _cities():
			if state.place_from_available(faction, "guerrilla", c, 1) > 0:
				log.append("Election: +1 Guerriglia di %s a %s" % [faction, c])
	else:
		var target: String = params.get("space", _cities()[0])
		state.set_support(target, CoinEnums.Support.NEUTRAL)
		state.tracks["aid"] = mini(49, int(state.tracks.get("aid", 0)) + 10)
		log.append("Election: %s a Neutrale, Aiuti +10" % target)
	return {"ok": true, "log": log}


## #11 Batista Flees
func _ev_11(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		state.add_resources("government", -10)
		var n := _roll(params)
		var removed := 0
		for sid in state.game_def.space_ids():
			while removed < n and state.space_state(sid).count("government", "troops") > 0:
				state.space_state(sid).remove_piece("government", "troops", 1, "")
				removed += 1
		var idx := int(state.tracks.get("us_alliance", 0))
		state.tracks["us_alliance"] = maxi(0, idx - 1)  # "1 box up" = verso Solida (indice minore)
		log.append("Batista Flees: Govt -10 Ris, -%d Truppe, Alleanza +1 verso Solida" % removed)
	else:
		state.tracks["aid"] = mini(49, int(state.tracks.get("aid", 0)) + 10)
		log.append("Batista Flees: Aiuti +10 (Spostamento Govt manuale)")
	return {"ok": true, "log": log}


## #16 Larrazábal
func _ev_16(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		var target: String = params.get("space", "")
		if target == "":
			for sid in state.game_def.space_ids():
				if state.space_state(sid).count("m26") > 0 and mod.can_place_base(state, sid, false):
					target = sid; break
		if target != "" and mod.can_place_base(state, target, false):
			state.place_from_available("m26", "base", target, 1)
			log.append("Larrazábal: Base 26 Luglio a %s" % target)
	else:
		for sid in state.game_def.space_ids():
			if state.space_state(sid).count("m26", "base") > 0:
				state.space_state(sid).remove_piece("m26", "base", 1, "")
				break
		state.add_resources("m26", -3)
		log.append("Larrazábal: rimossa 1 Base 26 Luglio, M26 -3 Ris")
	return {"ok": true, "log": log}


## #33 Carlos Prío
func _ev_33(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		var who: String = params.get("faction", "directorio")  # +5 DR o +5 26July
		state.add_resources(who, 5)
		log.append("Carlos Prío: +5 Risorse a %s" % who)
	else:
		var target: String = params.get("space", "")
		if target == "":
			for sid in state.game_def.space_ids():
				if state.space_state(sid).control != "government" and mod.can_place_base(state, sid, false):
					target = sid; break
		if target != "":
			state.place_from_available("directorio", "base", target, 1)
			state.set_support(target, CoinEnums.Support.NEUTRAL)
			log.append("Carlos Prío: Base DR a %s (Neutrale)" % target)
	return {"ok": true, "log": log}


## #34 US Speaking Tour
func _ev_34(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		var chosen: String = params.get("faction", faction)
		for fid in ["m26", "directorio", "syndicate"]:
			if fid == chosen:
				state.add_resources(fid, _roll(params))
			else:
				state.add_resources(fid, 2)
		log.append("US Speaking Tour: %s +1d6 Ris, altri insorgenti +2" % chosen)
	else:
		var aid := int(state.tracks.get("aid", 0))
		state.add_resources("government", mini(8, aid))
		state.tracks["aid"] = mini(49, aid + 8)
		log.append("US Speaking Tour: Govt +min(8,Aiuti), poi Aiuti +8")
	return {"ok": true, "log": log}


## #46 Sinatra
func _ev_46(side: String, faction: String, params: Dictionary) -> Dictionary:
	var log: Array = []
	if side == "unshaded":
		state.add_resources("syndicate", -6)
		log.append("Sinatra: Sindacato -6 Risorse")
	else:
		# Casinò aperto a Havana ignorando il raggruppamento, +1 Denaro con la Polizia
		state.space_state("havana").add_piece("syndicate", "casino", 1, "open")
		state.place_cash("havana", "syndicate", 1)
		log.append("Sinatra: Casinò aperto a Havana + 1 Denaro")
	return {"ok": true, "log": log}
