class_name CubaLibreEvents
extends RefCounted

## Motore degli Eventi di Cuba Libre (cap. 5). Ogni carta ha un gestore `_ev_<n>(side, faction, params)`.
## - Gli effetti concreti (Risorse, Aiuti, Alleanza, Supporto, piazzare/rimuovere/sostituire pezzi)
##   sono applicati direttamente.
## - Gli effetti DURATURI (Capacità Insorgenti / Momentum del Governo "fino a Propaganda")
##   vengono registrati come marcatori in `state.active_capabilities/active_momentum`;
##   l'applicazione di tali modificatori nelle Operazioni è progressiva.
## - Dove serve una scelta, si usa `params` con un default automatico ragionevole.
##
## side: "unshaded" | "shaded"  ·  faction: id della Fazione che svolge l'Evento.

var state: GameState
var mod: CubaLibreModule
var ops: CubaLibreOperations
var specials: CubaLibreSpecials


func _init(p_state: GameState, p_module: CubaLibreModule) -> void:
	state = p_state
	mod = p_module
	ops = CubaLibreOperations.new(p_state, p_module)
	specials = CubaLibreSpecials.new(p_state, p_module)


func apply(number: int, side: String, faction: String, params: Dictionary = {}) -> Dictionary:
	var card: CardDef = state.game_def.card(number)
	if card == null:
		return {"ok": false, "manual": false, "log": ["Carta %d inesistente" % number]}
	var log: Array = []
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

	log.append("Evento «%s» (%s): da applicare manualmente." % [card.title, side])
	return {"ok": true, "manual": true, "log": log}


# ---------------------------------------------------------------------------
# Helper generici
# ---------------------------------------------------------------------------

func _ids() -> Array: return Array(state.game_def.space_ids())
func _sd(sid: String) -> SpaceDef: return state.game_def.space(sid)
func _st(sid: String) -> SpaceState: return state.space_state(sid)

func _cities() -> Array:
	return _ids().filter(func(s): return _sd(s).type == CoinEnums.SpaceType.CITY)

func _provinces() -> Array:
	return _ids().filter(func(s): return _sd(s).type == CoinEnums.SpaceType.PROVINCE)

func _mountains() -> Array:
	return _ids().filter(func(s): return _sd(s).terrain == "mountain")

func _roll(params: Dictionary) -> int:
	return int(params.get("die", randi() % 6 + 1))

func _ins(faction: String, fallback: String = "m26") -> String:
	return faction if (faction == "m26" or faction == "directorio") else fallback

func _shift(sid: String, steps: int) -> void:
	# steps>0 verso Supporto, <0 verso Opposizione
	var st := _st(sid)
	st.support = clampi(st.support + steps, CoinEnums.Support.ACTIVE_OPPOSITION, CoinEnums.Support.ACTIVE_SUPPORT) as CoinEnums.Support

func _setsup(sid: String, lvl: CoinEnums.Support) -> void:
	_st(sid).support = lvl

func _aid(delta: int) -> void:
	state.tracks["aid"] = clampi(int(state.tracks.get("aid", 0)) + delta, 0, 49)

func _alliance(up: bool) -> void:
	# up = verso Solida (indice minore); down = verso Embargo (indice maggiore)
	var idx := int(state.tracks.get("us_alliance", 0))
	state.tracks["us_alliance"] = clampi(idx + (-1 if up else 1), 0, 2)

func _place_g(faction: String, sid: String, n: int = 1) -> int:
	return state.place_from_available(faction, "guerrilla", sid, n)

func _pick(arr: Array, params: Dictionary, key: String = "space") -> String:
	if params.has(key) and arr.has(params[key]):
		return params[key]
	return arr[0] if arr.size() > 0 else ""

func _spaces_with(faction: String, type: String = "") -> Array:
	return _ids().filter(func(s): return _st(s).count(faction, type) > 0)

func _counterpart(faction: String) -> String:
	return "directorio" if faction == "m26" else "m26"

## Sostituisce 1 pezzo (from) con il pezzo equivalente di to_faction.
func _replace_piece(sid: String, from_faction: String, to_faction: String) -> bool:
	var st := _st(sid)
	for t in ["base", "guerrilla"]:
		for state_s in (["underground", "active"] if t == "guerrilla" else [""]):
			if st.count(from_faction, t, state_s) > 0:
				st.remove_piece(from_faction, t, 1, state_s)
				if t == "guerrilla":
					state.place_from_available(to_faction, "guerrilla", sid, 1)
				else:
					if mod.can_place_base(state, sid, false):
						state.place_from_available(to_faction, "base", sid, 1)
				return true
	return false

func _ok(log: Array) -> Dictionary: return {"ok": true, "log": log}


# ===========================================================================
# GESTORI EVENTI 1–48
# ===========================================================================

## #1 Armored Cars — Momentum (shaded). Unshaded: 26July/DR Imboscata gratuita.
func _ev_1(side, faction, params):
	if side == "shaded":
		return _ok(["Armored Cars: Momentum (Truppe verso spazi di Assalto fino a Propaganda)"])
	var f := _ins(faction)
	for sid in _spaces_with(f, "guerrilla"):
		var st := _st(sid)
		if st.count("government") > 0 and st.count(f, "guerrilla", "underground") > 0:
			specials.ambush(f, {"space": sid})
			return _ok(["Armored Cars: Imboscata gratuita di %s a %s" % [f, sid]])
	return _ok(["Armored Cars: nessuna Imboscata possibile"])

## #2 Guantánamo Bay — Chiaro: Capacità (26J Sequestra a Sierra Maestra come Città).
## Ombr.: Momentum del Governo (Attacco Aereo rimuove 2 pezzi fino a Propaganda).
func _ev_2(side, faction, params):
	if side == "unshaded":
		return _ok(["Guantánamo Bay: Capacità (26J può Sequestrare a Sierra Maestra come Città)"])
	return _ok(["Guantánamo Bay: Momentum (l'Attacco Aereo rimuove 2 pezzi fino a Propaganda)"])

## #3 Eulogio Cantillo
func _ev_3(side, faction, params):
	if side == "unshaded":
		for sid in _spaces_with("government", "troops"):
			var f := _ins(faction)
			if _st(sid).count(f, "guerrilla") > 0:
				var adj = _sd(sid).adjacent
				if adj.size() > 0:
					state.move_pieces(f, "guerrilla", sid, adj[0], 99, "active")
					state.move_pieces(f, "guerrilla", sid, adj[0], 99, "underground")
					state.flip_pieces(f, "guerrilla", adj[0], "active", "underground")
				return _ok(["Eulogio Cantillo: %s evacua le Guerriglie da %s" % [f, sid]])
		return _ok(["Eulogio Cantillo: nessuna Guerriglia da spostare"])
	else:
		var sp := _spaces_with("government", "troops")
		if sp.size() > 0:
			mod.activate_guerrillas(state, sp[0], 99)
			var r := ops._assault_in_space(sp[0])
			return _ok(["Eulogio Cantillo: Sweep+Assalto gratis a %s (rimossi %d)" % [sp[0], r]])
		return _ok(["Eulogio Cantillo: nessuno spazio con Truppe"])

## #4 S.I.M. — Momentum (shaded). Unshaded: rimuovi Supporto da spazio senza Polizia.
func _ev_4(side, faction, params):
	if side == "shaded":
		return _ok(["S.I.M.: Momentum (Polizia agisce come Truppe fino a Propaganda)"])
	for sid in _ids():
		if _sd(sid).has_population() and _st(sid).support > 0 and _st(sid).count("government", "police") == 0:
			_setsup(sid, CoinEnums.Support.NEUTRAL)
			return _ok(["S.I.M.: rimosso Supporto da %s" % sid])
	return _ok(["S.I.M.: nessun bersaglio"])

## #5 Rolando Masferrer — Momentum (shaded). Unshaded: 1 Provincia con Truppe + 1 adiacente a Opp Passiva.
func _ev_5(side, faction, params):
	if side == "shaded":
		return _ok(["Rolando Masferrer: Momentum (Sweep può Assaltare gratis)"])
	for sid in _provinces():
		if _st(sid).count("government", "troops") > 0:
			_setsup(sid, CoinEnums.Support.PASSIVE_OPPOSITION)
			for adj in _sd(sid).adjacent:
				if _sd(adj).type == CoinEnums.SpaceType.PROVINCE:
					_setsup(adj, CoinEnums.Support.PASSIVE_OPPOSITION); break
			return _ok(["Rolando Masferrer: %s e 1 adiacente a Opp Passiva" % sid])
	return _ok(["Rolando Masferrer: nessuna Provincia con Truppe"])

## #6 Sánchez Mosquera — Momentum (shaded). Unshaded: rimuovi tutte le Truppe da una Montagna.
func _ev_6(side, faction, params):
	if side == "shaded":
		return _ok(["Sánchez Mosquera: Momentum (Assalto tratta Montagna come Città)"])
	for sid in _mountains():
		if _st(sid).count("government", "troops") > 0:
			var n := _st(sid).count("government", "troops")
			_st(sid).remove_piece("government", "troops", n, "")
			return _ok(["Sánchez Mosquera: rimosse %d Truppe da %s" % [n, sid]])
	return _ok(["Sánchez Mosquera: nessuna Truppa in Montagna"])

## #7 Election
func _ev_7(side, faction, params):
	if side == "unshaded":
		var log := []
		for c in _cities():
			if _place_g(faction, c, 1) > 0: log.append("+1 Guerriglia %s a %s" % [faction, c])
		return _ok(log)
	var t := _pick(_cities(), params)
	_setsup(t, CoinEnums.Support.NEUTRAL); _aid(10)
	return _ok(["Election: %s Neutrale, Aiuti +10" % t])

## #8 General Strike
func _ev_8(side, faction, params):
	if side == "unshaded":
		var log := []
		for c in _cities():
			_shift(c, -1)  # verso Neutrale (se Supporto) — semplificato verso Opp
			_place_g(faction, c, 1)
		return _ok(["General Strike: Città spostate verso Neutrale + 1 Guerriglia ciascuna"])
	var t := _pick(_cities(), params)
	_setsup(t, CoinEnums.Support.ACTIVE_SUPPORT)
	mod.activate_guerrillas(state, t, 99)
	for sid in _ids():
		if state.flip_pieces("syndicate", "casino", sid, "closed", "open", 1) > 0: break
	return _ok(["General Strike: %s Supporto Attivo, Guerriglie attivate, 1 Casinò aperto" % t])

## #9 Coup
func _ev_9(side, faction, params):
	if side == "unshaded":
		for sid in _ids():
			if _st(sid).control == "government": _shift(sid, -1)
		_alliance(true)
		return _ok(["Coup: Controllo Govt verso Neutrale, Alleanza +1"])
	for sid in _cities():
		var st := _st(sid)
		if st.count("government", "troops") + st.count("government", "police") > 0 and st.count("directorio", "guerrilla") > 0:
			mod.activate_guerrillas(state, sid, 99, "")
			ops._assault_in_space(sid)
	_alliance(false)
	return _ok(["Coup: DR attivati/assaltati nelle Città, Alleanza -1"])

## #10 MAP — Momentum (shaded). Unshaded: sostituisci 1 cubo con 2 Guerriglie.
func _ev_10(side, faction, params):
	if side == "shaded":
		return _ok(["MAP: Momentum (Govt accompagna LimOp con Att. Speciale gratis)"])
	var f := _ins(faction)
	for sid in _ids():
		var st := _st(sid)
		if st.count("government", "police") > 0:
			st.remove_piece("government", "police", 1, ""); _place_g(f, sid, 2)
			return _ok(["MAP: a %s 1 Polizia -> 2 Guerriglie %s" % [sid, f]])
		if st.count("government", "troops") > 0:
			st.remove_piece("government", "troops", 1, ""); _place_g(f, sid, 2)
			return _ok(["MAP: a %s 1 Truppa -> 2 Guerriglie %s" % [sid, f]])
	return _ok(["MAP: nessun cubo da sostituire"])

## #11 Batista Flees
func _ev_11(side, faction, params):
	if side == "unshaded":
		state.add_resources("government", -10)
		var n := _roll(params); var removed := 0
		for sid in _ids():
			while removed < n and _st(sid).count("government", "troops") > 0:
				_st(sid).remove_piece("government", "troops", 1, ""); removed += 1
		_alliance(true)
		return _ok(["Batista Flees: Govt -10, -%d Truppe, Alleanza +1" % removed])
	_aid(10)
	var log := ["Batista Flees: Aiuti +10"]
	log.append_array(CubaLibrePropaganda.new(state, mod).redeploy_phase())  # Redeploy come in Propaganda
	return _ok(log)

## #12 BRAC
func _ev_12(side, faction, params):
	if side == "unshaded":
		var removed := 0
		for sid in _ids():
			for f in ["m26", "directorio", "syndicate"]:
				while removed < 2 and _st(sid).count(f, "guerrilla") > 0:
					state.remove_to_available(f, "guerrilla", sid, 1); removed += 1
		return _ok(["BRAC: rimosse %d Guerriglie" % removed])
	var t := _pick(_ids(), params)
	state.place_from_available("government", "police", t, 1)
	state.add_resources("government", mini(6, int(state.tracks.get("aid", 0))))
	return _ok(["BRAC: +1 Polizia a %s, Govt +min(6,Aiuti)" % t])

## #13 El Che — Capacità (registrata).
func _ev_13(side, faction, params):
	return _ok(["El Che: Capacità registrata (1º gruppo che Marcia resta Clandestino)"])

## #14 Operation Fisherman
func _ev_14(side, faction, params):
	if side == "unshaded":
		if mod.can_place_base(state, "pinar_del_rio", false):
			state.place_from_available("m26", "base", "pinar_del_rio", 1)
		_place_g("m26", "pinar_del_rio", 1)
		return _ok(["Operation Fisherman: Base+Guerriglia 26July a Pinar del Río"])
	_shift("pinar_del_rio", 2)
	return _ok(["Operation Fisherman: Pinar del Río +2 verso Supporto Attivo"])

## #15 Come Comerades!
func _ev_15(side, faction, params):
	if side == "unshaded":
		var t := _pick(_ids(), params); _place_g("m26", t, 3)
		return _ok(["Come Comerades!: 3 Guerriglie 26July a %s" % t])
	state.add_resources("government", mini(10, int(state.tracks.get("aid", 0)))); _aid(5)
	return _ok(["Come Comerades!: Govt +min(10,Aiuti), Aiuti +5"])

## #16 Larrazábal
func _ev_16(side, faction, params):
	if side == "unshaded":
		var sp := _spaces_with("m26").filter(func(s): return mod.can_place_base(state, s, false))
		if sp.size() > 0:
			state.place_from_available("m26", "base", sp[0], 1)
			return _ok(["Larrazábal: Base 26July a %s" % sp[0]])
		return _ok(["Larrazábal: nessuno spazio valido"])
	for sid in _spaces_with("m26", "base"):
		_st(sid).remove_piece("m26", "base", 1, ""); break
	state.add_resources("m26", -3)
	return _ok(["Larrazábal: -1 Base 26July, M26 -3"])

## #17 Alberto Bayo
func _ev_17(side, faction, params):
	if side == "unshaded":
		var f := _ins(faction)
		for sid in _spaces_with(f, "base"):
			var pop := _sd(sid).pop
			_place_g(f, sid, _st(sid).count(f, "base") + pop)
		return _ok(["Alberto Bayo: Rally gratis di %s nelle sue Basi" % f])
	for sid in _ids():
		state.flip_pieces("m26", "guerrilla", sid, "underground", "active")
	state.eligibility["m26"] = CoinEnums.Eligibility.INELIGIBLE
	return _ok(["Alberto Bayo: tutte le Guerriglie 26July Attive, 26July Non Disponibile"])

## #18 Pact of Caracas — Capacità (registrata). Esecutore resta Disponibile.
func _ev_18(side, faction, params):
	state.eligibility[faction] = CoinEnums.Eligibility.ELIGIBLE
	return _ok(["Pact of Caracas: Capacità registrata; esecutore resta Disponibile"])

## #19 Sierra Maestra Manifesto
func _ev_19(side, faction, params):
	var log := []
	for f in state.game_def.card(19).faction_order:
		var sp := _spaces_with(f)
		if sp.size() > 0:
			if f == "government":
				state.place_from_available("government", "police", sp[0], 2)
			else:
				_place_g(f, sp[0], 2)
			log.append("%s piazza 2 pezzi a %s" % [f, sp[0]])
	state.eligibility[faction] = CoinEnums.Eligibility.ELIGIBLE
	return _ok(log)

## #20 The Twelve
func _ev_20(side, faction, params):
	if side == "unshaded":
		var f := _ins(faction)
		for sid in _spaces_with(f, "guerrilla"):
			for adj in _sd(sid).adjacent:
				if _sd(adj).has_population():
					state.move_pieces(f, "guerrilla", sid, adj, 1, "underground")
					_place_g(f, adj, 1)
					return _ok(["The Twelve: %s Marcia+Rally a %s" % [f, adj]])
		return _ok(["The Twelve: nessuna Marcia possibile"])
	# shaded: rimuovi metà (per eccesso) Guerriglie dallo spazio con più Guerriglie
	var best := ""; var bn := 0
	for sid in _ids():
		var tot := _st(sid).count("m26", "guerrilla") + _st(sid).count("directorio", "guerrilla") + _st(sid).count("syndicate", "guerrilla")
		if tot > bn: bn = tot; best = sid
	if best != "":
		var f: String = "m26"
		for ff in ["m26", "directorio", "syndicate"]:
			if _st(best).count(ff, "guerrilla") > 0: f = ff; break
		var rem := int(ceil(_st(best).count(f, "guerrilla") / 2.0))
		state.remove_to_available(f, "guerrilla", best, rem)
		return _ok(["The Twelve: rimosse %d Guerriglie da %s" % [rem, best]])
	return _ok(["The Twelve: nessuna Guerriglia"])

## #21 Fangio
func _ev_21(side, faction, params):
	if side == "unshaded":
		var t := _pick(_cities(), params)
		var step := 2 if _st(t).count("m26") > 0 else 1
		_shift(t, -step)
		return _ok(["Fangio: %s -%d verso Opp Attiva" % [t, step]])
	var done := 0
	for sid in _ids():
		if done >= 2: break
		if _st(sid).count("syndicate", "casino") > 0:
			if state.flip_pieces("syndicate", "casino", sid, "closed", "open", 1) == 0:
				state.place_cash(sid, "syndicate", 1)
			done += 1
	return _ok(["Fangio: %d Casinò aperti/Denaro" % done])

## #22 Raúl — Momentum (shaded) / unshaded capacità reroll (registrata via testo).
func _ev_22(side, faction, params):
	return _ok(["Raúl: effetto duraturo registrato"])

## #23 Radio Rebelde
func _ev_23(side, faction, params):
	if side == "unshaded":
		var n := 0
		for sid in _provinces():
			if n >= 2: break
			_shift(sid, -1); n += 1
		return _ok(["Radio Rebelde: %d Province -1 verso Opp Attiva" % n])
	for sid in _provinces():
		if _st(sid).count("m26", "base") > 0:
			_st(sid).remove_piece("m26", "base", 1, "")
			return _ok(["Radio Rebelde: -1 Base 26July da %s" % sid])
	return _ok(["Radio Rebelde: nessuna Base 26July in Provincia"])

## #24 Vilma Espín
func _ev_24(side, faction, params):
	if side == "unshaded":
		var cand := ["sierra_maestra"] + Array(_sd("sierra_maestra").adjacent)
		var t := _pick(cand.filter(func(s): return _sd(s).has_population()), params)
		if t != "": _setsup(t, CoinEnums.Support.ACTIVE_OPPOSITION)
		return _ok(["Vilma Espín: %s a Opposizione Attiva" % t])
	for c in _cities():
		if c == "havana": continue
		if _st(c).count("m26") > 0:
			_st(c).pieces.erase("m26")
			return _ok(["Vilma Espín: rimossi i pezzi 26July da %s" % c])
	return _ok(["Vilma Espín: nessun pezzo 26July in Città (≠Havana)"])

## #25 Escapade
func _ev_25(side, faction, params):
	if side == "unshaded":
		var t := _pick(["camaguey_province", "oriente"], params)
		if mod.can_place_base(state, t, false): state.place_from_available("directorio", "base", t, 1)
		_place_g("directorio", t, 1)
		return _ok(["Escapade: Base+Guerriglia DR a %s" % t])
	for sid in _spaces_with("directorio", "base"):
		_st(sid).remove_piece("directorio", "base", 1, ""); break
	return _ok(["Escapade: -1 Base DR"])

## #26 Rodríguez Loeches
func _ev_26(side, faction, params):
	if side == "unshaded":
		var t := _pick(_ids(), params); _place_g("directorio", t, 1)
		return _ok(["Rodríguez Loeches: +1 Guerriglia DR a %s (March/Rally/Ambush gratis)" % t])
	for sid in _spaces_with("directorio", "guerrilla"):
		state.remove_to_available("directorio", "guerrilla", sid, 1); break
	state.add_resources("directorio", -5)
	return _ok(["Rodríguez Loeches: -1 Guerriglia DR, DR -5"])

## #27 Echeverría
func _ev_27(side, faction, params):
	if side == "unshaded":
		var t := _pick(_ids(), params); _place_g("directorio", t, 2)
		_setsup("havana", CoinEnums.Support.NEUTRAL)
		state.eligibility["directorio"] = CoinEnums.Eligibility.ELIGIBLE
		return _ok(["Echeverría: +2 Guerriglie DR, Havana Neutrale, DR Disponibile"])
	# rimuovi i 2 pezzi DR più vicini a Havana (semplificato: Havana poi gli altri spazi)
	var removed := 0
	for sid in (["havana"] + _ids()):
		while removed < 2 and _st(sid).count("directorio") > 0:
			if state.remove_to_available("directorio", "guerrilla", sid, 1) == 0:
				_st(sid).remove_piece("directorio", "base", 1, "")
			removed += 1
	state.add_resources("directorio", -3)
	return _ok(["Echeverría: rimossi %d pezzi DR, DR -3" % removed])

## #28 Morgan — Capacità (registrata). Shaded: spazio con Guerriglia DR a Supporto Attivo.
func _ev_28(side, faction, params):
	if side == "unshaded":
		return _ok(["Morgan: Capacità registrata (DR Marcia 2 spazi)"])
	for sid in _spaces_with("directorio", "guerrilla"):
		if _sd(sid).has_population(): _setsup(sid, CoinEnums.Support.ACTIVE_SUPPORT); break
	return _ok(["Morgan: spazio con Guerriglia DR a Supporto Attivo"])

## #29 Fauré Chomón
func _ev_29(side, faction, params):
	if side == "unshaded":
		var f := _ins(faction)
		if mod.can_place_base(state, "las_villas", false): state.place_from_available(f, "base", "las_villas", 1)
		_place_g(f, "las_villas", 2)
		return _ok(["Fauré Chomón: Base+2 Guerriglie %s a Las Villas" % f])
	for sid in _spaces_with("directorio"):
		if _replace_piece(sid, "directorio", "m26"):
			return _ok(["Fauré Chomón: 1 pezzo DR -> 26July a %s" % sid])
	return _ok(["Fauré Chomón: nessun pezzo DR"])

## #30 The Guerrilla Life — Capacità (registrata). Shaded: gira DR Clandestine + 1 in Città.
func _ev_30(side, faction, params):
	if side == "unshaded":
		return _ok(["The Guerrilla Life: Capacità registrata (Rally 26July gira Clandestine)"])
	for sid in _ids():
		state.flip_pieces("directorio", "guerrilla", sid, "active", "underground")
	_place_g("directorio", _pick(_cities(), params), 1)
	return _ok(["The Guerrilla Life: DR Clandestine + 1 Guerriglia DR in Città"])

## #31 Escopeteros
func _ev_31(side, faction, params):
	if side == "unshaded":
		var f := _ins(faction)
		var t := _pick(_mountains(), params)
		if mod.can_place_base(state, t, false): state.place_from_available(f, "base", t, 1)
		_place_g(f, t, 1)
		return _ok(["Escopeteros: Base+Guerriglia %s in Montagna (%s)" % [f, t]])
	for sid in _mountains():
		_shift(sid, 1); break
	return _ok(["Escopeteros: 1 Montagna +1 verso Supporto Attivo"])

## #32 Resistencia Cívica
func _ev_32(side, faction, params):
	var from_f := "directorio" if side == "unshaded" else "m26"
	var to_f := "m26" if side == "unshaded" else "directorio"
	for c in _cities():
		if _st(c).count(from_f) > 0:
			while _replace_piece(c, from_f, to_f): pass
			return _ok(["Resistencia Cívica: a %s pezzi %s -> %s" % [c, from_f, to_f]])
	return _ok(["Resistencia Cívica: nessun bersaglio"])

## #33 Carlos Prío
func _ev_33(side, faction, params):
	if side == "unshaded":
		var who := String(params.get("faction", "directorio"))
		state.add_resources(who, 5)
		return _ok(["Carlos Prío: +5 Risorse a %s" % who])
	var sp := _ids().filter(func(s): return _st(s).control != "government" and mod.can_place_base(state, s, false))
	if sp.size() > 0:
		state.place_from_available("directorio", "base", sp[0], 1); _setsup(sp[0], CoinEnums.Support.NEUTRAL)
		return _ok(["Carlos Prío: Base DR a %s (Neutrale)" % sp[0]])
	return _ok(["Carlos Prío: nessuno spazio valido"])

## #34 US Speaking Tour
func _ev_34(side, faction, params):
	if side == "unshaded":
		var chosen := String(params.get("faction", _ins(faction, "m26")))
		for fid in ["m26", "directorio", "syndicate"]:
			state.add_resources(fid, _roll(params) if fid == chosen else 2)
		return _ok(["US Speaking Tour: %s +1d6, altri insorgenti +2" % chosen])
	state.add_resources("government", mini(8, int(state.tracks.get("aid", 0)))); _aid(8)
	return _ok(["US Speaking Tour: Govt +min(8,Aiuti), Aiuti +8"])

## #35 Defections — sostituisci 2 pezzi nemici con i propri (faction esecutore).
func _ev_35(side, faction, params):
	var enemies := ["government", "m26", "directorio", "syndicate"]; enemies.erase(faction)
	for sid in _ids():
		if _st(sid).count(faction) == 0: continue
		var replaced := 0
		for e in enemies:
			while replaced < 2 and _replace_piece(sid, e, faction): replaced += 1
		if replaced > 0:
			return _ok(["Defections: a %s sostituiti %d pezzi nemici" % [sid, replaced]])
	return _ok(["Defections: nessuno spazio con pezzi propri + nemici"])

## #36 Eloy Gutiérrez Menoyo
func _ev_36(side, faction, params):
	if side == "unshaded":
		var cand := ["las_villas"] + Array(_sd("las_villas").adjacent)
		for sid in cand:
			for e in ["government", "m26"]:
				if e == "m26" and _st(sid).count("m26", "guerrilla") > 0:
					if state.remove_to_available("m26", "guerrilla", sid, 1) > 0:
						_place_g("directorio", sid, 2)
						return _ok(["Eloy G. Menoyo: a %s 1 Guerriglia -> 2 DR" % sid])
				elif e == "government":
					if state.remove_to_available("government", "police", sid, 1) > 0 or state.remove_to_available("government", "troops", sid, 1) > 0:
						_place_g("directorio", sid, 2)
						return _ok(["Eloy G. Menoyo: a %s 1 cubo -> 2 DR" % sid])
		return _ok(["Eloy G. Menoyo: nessun bersaglio vicino a Las Villas"])
	for sid in _spaces_with("directorio", "guerrilla"):
		state.remove_to_available("directorio", "guerrilla", sid, 1); _place_g("m26", sid, 1)
		return _ok(["Eloy G. Menoyo: 1 Guerriglia DR -> 26July a %s" % sid])
	return _ok(["Eloy G. Menoyo: nessuna Guerriglia DR"])

## #37 Herbert Matthews
func _ev_37(side, faction, params):
	if side == "unshaded":
		state.add_resources("m26", 5); _aid(-6)
		return _ok(["Herbert Matthews: 26July +5, Aiuti -6"])
	_aid(10); state.add_resources("directorio", 3); state.add_resources("syndicate", 5)
	return _ok(["Herbert Matthews: Aiuti +10, DR +3, Sindacato +5"])

## #38 Meyer Lansky
func _ev_38(side, faction, params):
	if side == "shaded":
		for sid in _ids():
			state.flip_pieces("syndicate", "casino", sid, "closed", "open")
		return _ok(["Meyer Lansky: tutti i Casinò aperti (ricollocazione semplificata)"])
	# Chiaro: trasferisci il Denaro presente in uno spazio alla Fazione che gioca l'Evento.
	for sid in _ids():
		for other in ["government", "m26", "directorio", "syndicate"]:
			if other == faction:
				continue
			var c := _st(sid).cash_for(other)
			if c > 0:
				state.transfer_cash(sid, other, faction, c)
				return _ok(["Meyer Lansky: %d Denaro da %s a %s a %s" % [c, other, faction, sid]])
	return _ok(["Meyer Lansky: nessun Denaro da trasferire"])

## #39 Turismo
func _ev_39(side, faction, params):
	if side == "unshaded":
		for sid in _ids():
			if _st(sid).count("syndicate", "casino", "open") > 0 and _sd(sid).has_population():
				_shift(sid, -1)
		return _ok(["Turismo: -1 Supporto verso Neutrale negli spazi con Casinò"])
	var n := 0
	for sid in _ids():
		if _st(sid).count("syndicate", "casino", "open") > 0 and _st(sid).count("government", "police") > 0: n += 1
	state.add_resources("government", 3 * n); state.add_resources("syndicate", 3 * n)
	return _ok(["Turismo: Govt e Sindacato +%d" % (3 * n)])

## #40 Ambassador Smith
func _ev_40(side, faction, params):
	if side == "unshaded":
		_alliance(false)
		return _ok(["Ambassador Smith: Alleanza -1 (Aiuti invariati)"])
	_alliance(true); _aid(9)
	state.add_resources("syndicate", mini(9, int(state.tracks.get("aid", 0)) / 2))
	return _ok(["Ambassador Smith: Alleanza +1, Aiuti +9, Sindacato +min(9, metà Aiuti)"])

## #41 Fat Butcher
func _ev_41(side, faction, params):
	if side == "unshaded":
		var closed := false
		for sid in _ids():
			if state.flip_pieces("syndicate", "casino", sid, "open", "closed", 1) > 0: closed = true; break
		if not closed: _aid(-8)
		return _ok(["Fat Butcher: chiuso 1 Casinò" if closed else "Fat Butcher: Aiuti -8"])
	for sid in _spaces_with("syndicate", "guerrilla"):
		if _st(sid).count("syndicate", "guerrilla", "underground") > 0:
			specials.ambush("syndicate", {"space": sid})
			break
	for sid in _ids():
		if state.flip_pieces("syndicate", "casino", sid, "closed", "open", 1) > 0: break
	return _ok(["Fat Butcher: Imboscata Sindacato + 1 Casinò aperto"])

## #42 Llano
func _ev_42(side, faction, params):
	if side == "unshaded":
		var t := _pick(_cities(), params)
		if mod.can_place_base(state, t, false): state.place_from_available("m26", "base", t, 1)
		_place_g("m26", t, 1)
		return _ok(["Llano: Base+Guerriglia 26July a %s" % t])
	var t := _pick(_cities(), params)
	if _st(t).support < 0: _setsup(t, CoinEnums.Support.NEUTRAL)
	if mod.can_place_base(state, t, true): state.place_from_available("syndicate", "casino", t, 1, "open")
	return _ok(["Llano: %s senza Opposizione + Casinò aperto" % t])

## #43 Mafia Offensive — Capacità (shaded registrata). Unshaded: LimOp gratis usando 1 pezzo Sindacato.
func _ev_43(side, faction, params):
	if side == "shaded":
		return _ok(["Mafia Offensive: Capacità registrata (Sindacato può Assassinare)"])
	# Chiaro: 26J o DR esegue un'Op Limitata gratis (Rally) trattando 1 pezzo del Sindacato come proprio.
	var f := _ins(faction)
	var cand := _spaces_with(f).filter(func(s): return _sd(s).has_population())
	if cand.is_empty():
		cand = _ids().filter(func(s): return _sd(s).has_population() and _st(s).count("syndicate", "guerrilla") > 0)
	var t := _pick(cand, params)
	if t == "":
		return _ok(["Mafia Offensive: nessuno spazio valido per l'Op Limitata"])
	var log: Array = []
	if _replace_piece(t, "syndicate", f):
		log.append("Mafia Offensive: 1 pezzo del Sindacato trattato come %s a %s" % [f, t])
	var amt := 1
	if _st(t).count(f, "base") > 0:
		amt = (2 * _st(t).count(f, "base") + 2 * _sd(t).pop) if f == "m26" else (_st(t).count(f, "base") + _sd(t).pop)
	_place_g(f, t, amt)
	log.append("Mafia Offensive: Op Limitata gratis (Rally) di %s a %s (+%d Guerriglie)" % [f, t, amt])
	return _ok(log)

## #44 Rebel Air Force
func _ev_44(side, faction, params):
	if side == "unshaded":
		var f := _ins(faction)
		for sid in _spaces_with(f, "guerrilla"):
			if _st(sid).count("government") > 0:
				specials.ambush(f, {"space": sid})
				return _ok(["Rebel Air Force: Imboscata gratuita di %s a %s" % [f, sid]])
		return _ok(["Rebel Air Force: nessuna Imboscata possibile"])
	var f := _ins(faction)
	var amt := _roll(params); var moved := mini(amt, state.get_resources(f))
	state.add_resources(f, -moved); state.add_resources("syndicate", moved)
	return _ok(["Rebel Air Force: %d Risorse da %s al Sindacato" % [moved, f]])

## #45 Anastasia
func _ev_45(side, faction, params):
	if side == "unshaded":
		state.flip_pieces("syndicate", "casino", "havana", "open", "closed")
		state.add_resources("syndicate", -5)
		return _ok(["Anastasia: Casinò di Havana chiusi, Sindacato -5"])
	state.add_resources("syndicate", 10)
	return _ok(["Anastasia: Sindacato +10"])

## #46 Sinatra
func _ev_46(side, faction, params):
	if side == "unshaded":
		state.add_resources("syndicate", -6)
		return _ok(["Sinatra: Sindacato -6"])
	_st("havana").add_piece("syndicate", "casino", 1, "open")
	state.place_cash("havana", "syndicate", 1)
	return _ok(["Sinatra: Casinò aperto a Havana + 1 Denaro"])

## #47 Pact of Miami
func _ev_47(side, faction, params):
	if side == "unshaded":
		var removed := 0
		for sid in _ids():
			for f in ["m26", "directorio", "syndicate"]:
				while removed < 2 and _st(sid).count(f, "guerrilla") > 0:
					state.remove_to_available(f, "guerrilla", sid, 1); removed += 1
		state.eligibility["government"] = CoinEnums.Eligibility.INELIGIBLE
		return _ok(["Pact of Miami: rimosse %d Guerriglie, Govt Non Disponibile" % removed])
	state.add_resources("m26", -3); state.add_resources("directorio", -3)
	state.eligibility["m26"] = CoinEnums.Eligibility.INELIGIBLE
	state.eligibility["directorio"] = CoinEnums.Eligibility.INELIGIBLE
	return _ok(["Pact of Miami: 26July e DR -3 e Non Disponibili"])

## #48 Santo Trafficante Jr — Capacità (shaded registrata). Unshaded: Sindacato -10, Guerriglie Attive.
func _ev_48(side, faction, params):
	if side == "unshaded":
		state.add_resources("syndicate", -10)
		for sid in _ids():
			state.flip_pieces("syndicate", "guerrilla", sid, "underground", "active")
		return _ok(["Santo Trafficante Jr: Sindacato -10, Guerriglie Sindacato Attive"])
	return _ok(["Santo Trafficante Jr: Capacità registrata (Clandestine bloccano la Cresta)"])
