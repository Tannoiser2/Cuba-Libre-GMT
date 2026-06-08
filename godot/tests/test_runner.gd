extends SceneTree

## Esecuzione test headless:
##   godot4 --headless --path godot -s res://tests/test_runner.gd
## Esce con codice 0 se tutti i test passano, 1 altrimenti.

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("== COIN Engine — Test Cuba Libre ==")
	_test_game_def()
	_test_setup_forces()
	_test_setup_tracks()
	_test_control()
	_test_victory_initial()
	_test_sequence_basic()
	_test_sequence_pass_cascade()
	_test_sequence_all_pass()
	_test_sequence_eligibility_filter()
	_test_sequence_final_card()
	_test_serialization()
	_test_op_train()
	_test_op_sweep()
	_test_op_assault()
	_test_op_rally()
	_test_op_march()
	_test_op_attack()
	_test_op_terror()
	_test_op_build()
	_test_sa_government()
	_test_sa_m26()
	_test_sa_directorio()
	_test_sa_syndicate()
	_test_propaganda_resources()
	_test_propaganda_support_reset()
	_test_propaganda_victory()
	_test_cards_data()
	_test_events()
	_test_all_events()
	_test_capabilities()
	_test_game_loop()

	_test_calixto_data()
	_test_calixto_deck()
	_test_calixto_engine()
	_test_calixto_bot()

	print("\n-- Risultato: %d passati, %d falliti --" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------------------
# Helper di asserzione
# ---------------------------------------------------------------------------

func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  [OK]   %s" % name)
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _eq(name: String, got, want) -> void:
	_check("%s (atteso %s, ottenuto %s)" % [name, str(want), str(got)], got == want)


func _new_game() -> Array:
	var mod := CubaLibreModule.new()
	var gd := mod.build_game_def()
	var state := GameState.new(gd)
	mod.apply_setup(state, "standard")
	return [mod, gd, state]


# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------

func _test_game_def() -> void:
	print("\n[GameDef]")
	var mod := CubaLibreModule.new()
	var gd := mod.build_game_def()
	_eq("numero spazi", gd.spaces.size(), 13)
	_eq("numero fazioni", gd.factions.size(), 4)
	_eq("numero tipi di pezzo", gd.piece_types.size(), 5)
	# Econ totale degli EC = 8 (regola 6.2.1)
	var econ := 0
	for s in gd.spaces:
		econ += s.econ
	_eq("Econ totale EC", econ, 8)
	# Havana è una Città con Pop 6
	_eq("Havana Pop", gd.space("havana").pop, 6)


func _test_setup_forces() -> void:
	print("\n[Setup — Forze]")
	var r := _new_game()
	var state: GameState = r[2]
	# Forze del Governo a Havana: 6 Truppe, 4 Polizia
	_eq("Havana Truppe Govt", state.space_state("havana").count("government", "troops"), 6)
	_eq("Havana Polizia Govt", state.space_state("havana").count("government", "police"), 4)
	# 26 Luglio in Sierra Maestra: 2 Guerriglie + 1 Base
	_eq("Sierra Guerriglie M26", state.space_state("sierra_maestra").count("m26", "guerrilla"), 2)
	_eq("Sierra Basi M26", state.space_state("sierra_maestra").count("m26", "base"), 1)
	# Le Guerriglie iniziano Clandestine
	_eq("M26 Guerriglie Clandestine in Sierra",
		state.space_state("sierra_maestra").count("m26", "guerrilla", "underground"), 2)
	# Casinò aperti totali = 3
	_eq("Casinò aperti totali", state.count_on_map("syndicate", "casino"), 3)


func _test_setup_tracks() -> void:
	print("\n[Setup — Tracciati]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	_eq("Totale Supporto", state.total_support(), 16)
	_eq("Totale Opposizione", state.total_opposition(), 6)
	_eq("Opposizione + Basi", mod.opposition_plus_bases(state), 7)
	_eq("DR Pop + Basi", mod.dr_pop_plus_bases(state), 1)
	_eq("Casinò aperti", mod.open_casinos(state), 3)
	# Risorse iniziali
	_eq("Risorse Governo", state.get_resources("government"), 15)
	_eq("Risorse Sindacato", state.get_resources("syndicate"), 15)
	_eq("Risorse 26 Luglio", state.get_resources("m26"), 10)
	_eq("Risorse Directorio", state.get_resources("directorio"), 5)
	_eq("Aiuti", int(state.tracks.get("aid", -1)), 15)


func _test_control() -> void:
	print("\n[Controllo]")
	var r := _new_game()
	var state: GameState = r[2]
	_eq("Havana controllata da Govt", state.space_state("havana").control, "government")
	_eq("Las Villas controllata da Govt", state.space_state("las_villas").control, "government")
	_eq("Sierra Maestra controllata da M26", state.space_state("sierra_maestra").control, "m26")
	_eq("Camagüey Prov. controllata da DR", state.space_state("camaguey_province").control, "directorio")
	_eq("Pinar del Río controllata da Sindacato", state.space_state("pinar_del_rio").control, "syndicate")
	# La Habana: parità M26/Sindacato -> Incontrollata
	_eq("La Habana incontrollata", state.space_state("la_habana").control, "")
	_eq("Matanzas incontrollata", state.space_state("matanzas").control, "")


const A := CoinEnums.ActionType


func _card(order: Array) -> CardDef:
	var c := CardDef.new(99, "Test")
	c.faction_order = PackedStringArray(order)
	return c


func _test_sequence_basic() -> void:
	print("\n[Sequenza — base: Op+SA poi Evento]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var card := _card(["government", "m26", "syndicate", "directorio"])
	var seq := SequenceOfPlay.new(state, mod, card)

	_eq("1ª in sospeso", seq.pending_faction(), "government")
	_check("1ª può fare Evento", seq.is_legal(A.EVENT))
	_check("Op+SA legale", seq.is_legal(A.OPERATION_WITH_SPECIAL))
	seq.act(A.OPERATION_WITH_SPECIAL)
	_eq("2ª in sospeso", seq.pending_faction(), "m26")
	# Dopo Op+SA della 1ª, la 2ª può solo Evento (o Passare)
	_check("2ª può fare Evento", seq.is_legal(A.EVENT))
	_check("2ª NON può fare Operazione", not seq.is_legal(A.OPERATION))
	seq.act(A.EVENT)
	_check("carta conclusa", seq.is_done())
	seq.finish()
	_eq("government Non Disponibile", state.eligibility["government"], CoinEnums.Eligibility.INELIGIBLE)
	_eq("m26 Non Disponibile", state.eligibility["m26"], CoinEnums.Eligibility.INELIGIBLE)
	_eq("syndicate Disponibile", state.eligibility["syndicate"], CoinEnums.Eligibility.ELIGIBLE)
	_eq("directorio Disponibile", state.eligibility["directorio"], CoinEnums.Eligibility.ELIGIBLE)


func _test_sequence_pass_cascade() -> void:
	print("\n[Sequenza — Passare a cascata]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var m26_before := state.get_resources("m26")
	var card := _card(["m26", "government", "directorio", "syndicate"])
	var seq := SequenceOfPlay.new(state, mod, card)

	_eq("1ª in sospeso", seq.pending_faction(), "m26")
	seq.act_pass()  # m26 passa, +1
	_eq("dopo il pass la 1ª è government", seq.pending_faction(), "government")
	_check("government ancora 1ª", seq.is_first_slot())
	seq.act(A.OPERATION)  # government Op semplice
	_eq("2ª in sospeso è directorio", seq.pending_faction(), "directorio")
	# Dopo Op semplice della 1ª, la 2ª può solo Operazione Limitata
	_check("2ª può Op Limitata", seq.is_legal(A.LIMITED_OPERATION))
	_check("2ª NON può Evento", not seq.is_legal(A.EVENT))
	seq.act(A.LIMITED_OPERATION)
	seq.finish()
	_eq("m26 ha ricevuto +1 dal pass", state.get_resources("m26"), m26_before + 1)
	_eq("m26 resta Disponibile", state.eligibility["m26"], CoinEnums.Eligibility.ELIGIBLE)
	_eq("government Non Disponibile", state.eligibility["government"], CoinEnums.Eligibility.INELIGIBLE)
	_eq("directorio Non Disponibile", state.eligibility["directorio"], CoinEnums.Eligibility.INELIGIBLE)


func _test_sequence_all_pass() -> void:
	print("\n[Sequenza — tutti Passano]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var gov_before := state.get_resources("government")
	var card := _card(["government", "m26", "directorio", "syndicate"])
	var seq := SequenceOfPlay.new(state, mod, card)
	while not seq.is_done():
		seq.act_pass()
	seq.finish()
	_eq("government +3 dal pass", state.get_resources("government"), gov_before + 3)
	_eq("tutte restano Disponibili (government)",
		state.eligibility["government"], CoinEnums.Eligibility.ELIGIBLE)
	_eq("tutte restano Disponibili (syndicate)",
		state.eligibility["syndicate"], CoinEnums.Eligibility.ELIGIBLE)


func _test_sequence_eligibility_filter() -> void:
	print("\n[Sequenza — fazioni Non Disponibili saltate]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	state.eligibility["government"] = CoinEnums.Eligibility.INELIGIBLE
	var card := _card(["government", "m26", "directorio", "syndicate"])
	var seq := SequenceOfPlay.new(state, mod, card)
	_eq("1ª in sospeso salta government", seq.pending_faction(), "m26")


func _test_sequence_final_card() -> void:
	print("\n[Sequenza — Carta Evento Finale: solo LimOp]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var card := _card(["government", "m26", "directorio", "syndicate"])
	var seq := SequenceOfPlay.new(state, mod, card)
	seq.final_event_card = true
	_check("1ª NON può Evento", not seq.is_legal(A.EVENT))
	_check("1ª può solo Op Limitata", seq.is_legal(A.LIMITED_OPERATION))
	_check("1ª non può Op piena", not seq.is_legal(A.OPERATION))


func _test_serialization() -> void:
	print("\n[Serializzazione save/load]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var gd: GameDef = r[1]
	var state: GameState = r[2]
	# Modifica lo stato
	state.add_resources("m26", 7)
	state.space_state("matanzas").add_piece("m26", "guerrilla", 2, "active")
	state.eligibility["directorio"] = CoinEnums.Eligibility.INELIGIBLE
	# Round-trip in memoria
	var d := state.to_dict()
	var state2 := GameState.from_dict(gd, d)
	_eq("Risorse m26 conservate", state2.get_resources("m26"), state.get_resources("m26"))
	_eq("Guerriglie m26 a Matanzas conservate",
		state2.space_state("matanzas").count("m26", "guerrilla", "active"), 2)
	_eq("Disponibilità directorio conservata",
		state2.eligibility["directorio"], CoinEnums.Eligibility.INELIGIBLE)
	_eq("Truppe Govt a Havana conservate",
		state2.space_state("havana").count("government", "troops"), 6)
	# Round-trip su file
	var path := "user://test_save.json"
	_check("salvataggio su file", state.save_to_file(path))
	var state3 := GameState.load_from_file(gd, path)
	_check("caricamento da file non nullo", state3 != null)
	if state3 != null:
		_eq("file: Risorse m26", state3.get_resources("m26"), state.get_resources("m26"))
		_eq("file: Totale Supporto", state3.total_support(), 16)


func _ops() -> Array:
	# [mod, gd, state, ops]
	var r := _new_game()
	var ops := CubaLibreOperations.new(r[2], r[0])
	return [r[0], r[1], r[2], ops]


func _test_op_train() -> void:
	print("\n[Operazione — Train]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# Piazza 2 Truppe + 2 Polizia a Havana (Città). Costo 2 (Alleanza Solida).
	var res = ops.train({"spaces": ["havana"], "place": {"havana": {"troops": 2, "police": 2}}})
	_check("train ok", res.ok)
	_eq("costo train", res.cost, 2)
	_eq("Risorse Govt dopo train", state.get_resources("government"), 13)
	_eq("Truppe a Havana", state.space_state("havana").count("government", "troops"), 8)
	_eq("Polizia a Havana", state.space_state("havana").count("government", "police"), 6)
	# Azione speciale "base" a Havana: rimuove 2 cubi, +1 Base
	var r2 := _ops()
	var st2: GameState = r2[2]
	var ops2: CubaLibreOperations = r2[3]
	var res2 = ops2.train({"spaces": ["havana"], "special": {"type": "base", "space": "havana"}})
	_check("train base ok", res2.ok)
	_eq("Base Govt a Havana", st2.space_state("havana").count("government", "base"), 1)


func _test_op_sweep() -> void:
	print("\n[Operazione — Sweep]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# Matanzas (prateria): 3 Truppe Govt, 2 Guerriglie M26 clandestine
	state.space_state("matanzas").add_piece("government", "troops", 3)
	state.space_state("matanzas").add_piece("m26", "guerrilla", 2, "underground")
	var res = ops.sweep({"spaces": ["matanzas"]})
	_check("sweep ok", res.ok)
	_eq("Guerriglie attivate (prateria, 3 cubi)",
		state.space_state("matanzas").count("m26", "guerrilla", "active"), 2)
	# Foresta: Las Villas (3 Truppe setup) +1 = 4 cubi -> attiva floor(4/2)=2
	var r2 := _ops()
	var st2: GameState = r2[2]
	var ops2: CubaLibreOperations = r2[3]
	st2.space_state("las_villas").add_piece("government", "troops", 1)  # ora 4 cubi
	st2.space_state("las_villas").add_piece("m26", "guerrilla", 3, "underground")
	ops2.sweep({"spaces": ["las_villas"]})
	_eq("Guerriglie attivate (foresta, 4 cubi)",
		st2.space_state("las_villas").count("m26", "guerrilla", "active"), 2)


func _test_op_assault() -> void:
	print("\n[Operazione — Assault]")
	# Provincia prateria: 3 Truppe -> capacità 3
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	state.space_state("matanzas").add_piece("government", "troops", 3)
	state.space_state("matanzas").add_piece("m26", "guerrilla", 3, "active")
	ops.assault({"spaces": ["matanzas"]})
	_eq("Assalto prateria rimuove 3 attive",
		state.space_state("matanzas").count("m26", "guerrilla", "active"), 0)
	# Montagna: 4 Truppe -> capacità floor(4/2)=2
	var r2 := _ops()
	var st2: GameState = r2[2]
	var ops2: CubaLibreOperations = r2[3]
	st2.space_state("oriente").add_piece("government", "troops", 4)
	st2.space_state("oriente").add_piece("m26", "guerrilla", 4, "active")
	ops2.assault({"spaces": ["oriente"]})
	_eq("Assalto montagna rimuove solo 2", st2.space_state("oriente").count("m26", "guerrilla", "active"), 2)
	# Protezione Base: 2 Truppe, 1 Guerriglia attiva + 1 Base -> rimuove guerriglia poi base
	var r3 := _ops()
	var st3: GameState = r3[2]
	var ops3: CubaLibreOperations = r3[3]
	st3.space_state("matanzas").add_piece("government", "troops", 2)
	st3.space_state("matanzas").add_piece("m26", "guerrilla", 1, "active")
	st3.space_state("matanzas").add_piece("m26", "base", 1)
	ops3.assault({"spaces": ["matanzas"]})
	_eq("Assalto: guerriglia rimossa", st3.space_state("matanzas").count("m26", "guerrilla"), 0)
	_eq("Assalto: base rimossa dopo guerriglia", st3.space_state("matanzas").count("m26", "base"), 0)


func _test_op_rally() -> void:
	print("\n[Operazione — Rally]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# M26 Rally "extra" in Sierra Maestra (ha 1 Base, Pop 1): limite 2*1+2*1=4
	var before := state.space_state("sierra_maestra").count("m26", "guerrilla")
	var res = ops.rally({"faction": "m26", "spaces": ["sierra_maestra"], "choices": {"sierra_maestra": "extra"}})
	_check("rally extra ok", res.ok)
	_eq("Guerriglie M26 dopo extra a Sierra",
		state.space_state("sierra_maestra").count("m26", "guerrilla"), before + 4)
	# Vincolo: M26 non può Rally in spazio con Supporto (Havana = Supporto Attivo)
	var r2 := _ops()
	var ops2: CubaLibreOperations = r2[3]
	var res2 = ops2.rally({"faction": "m26", "spaces": ["havana"]})
	_check("rally M26 vietato in Supporto", not res2.ok)


func _test_op_march() -> void:
	print("\n[Operazione — March]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# 3 Guerriglie M26 clandestine in La Habana marciano a Havana (Supporto Attivo, 10 cubi)
	state.space_state("la_habana").add_piece("m26", "guerrilla", 2, "underground")  # ora 3
	var res = ops.march({"faction": "m26", "moves": [{"from": "la_habana", "to": "havana", "count": 3}]})
	_check("march ok", res.ok)
	_eq("costo march (Havana è Città)", res.cost, 1)
	_eq("Guerriglie attivate entrando in Supporto",
		state.space_state("havana").count("m26", "guerrilla", "active"), 3)


func _test_op_attack() -> void:
	print("\n[Operazione — Attack]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	state.space_state("matanzas").add_piece("m26", "guerrilla", 2, "underground")
	state.space_state("matanzas").add_piece("government", "police", 1)
	# tiro 2 <= 2 guerriglie -> successo
	var res = ops.attack({"faction": "m26", "spaces": ["matanzas"], "die_rolls": {"matanzas": 2}})
	_check("attack ok", res.ok)
	_eq("Polizia rimossa dall'attacco", state.space_state("matanzas").count("government", "police"), 0)
	# tiro 1 -> successo + cattura (1 guerriglia in più)
	var r2 := _ops()
	var st2: GameState = r2[2]
	var ops2: CubaLibreOperations = r2[3]
	st2.space_state("matanzas").add_piece("m26", "guerrilla", 1, "underground")
	st2.space_state("matanzas").add_piece("government", "troops", 1)
	var g_before := st2.count_on_map("m26", "guerrilla")
	ops2.attack({"faction": "m26", "spaces": ["matanzas"], "die_rolls": {"matanzas": 1}})
	_eq("cattura: +1 Guerriglia M26 sulla mappa", st2.count_on_map("m26", "guerrilla"), g_before + 1)


func _test_op_terror() -> void:
	print("\n[Operazione — Terror]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# Matanzas: Opposizione Passiva (-1). M26 ha guerriglia clandestina -> verso Opp Attiva (-2)
	state.space_state("matanzas").add_piece("m26", "guerrilla", 1, "underground")
	var res = ops.terror({"faction": "m26", "spaces": ["matanzas"]})
	_check("terror ok", res.ok)
	_eq("Supporto a Matanzas verso Opp Attiva",
		state.space_state("matanzas").support, CoinEnums.Support.ACTIVE_OPPOSITION)
	_eq("segnalino Terrore a Matanzas", state.space_state("matanzas").marker("terror"), 1)


func _test_op_build() -> void:
	print("\n[Operazione — Build]")
	var r := _ops()
	var state: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	# Pinar del Río è controllata dal Sindacato. Costruisci nuovo Casinò (chiuso). Costo 5.
	var before := state.space_state("pinar_del_rio").count("syndicate", "casino")
	var res = ops.build({"spaces": ["pinar_del_rio"], "choices": {"pinar_del_rio": "new"}})
	_check("build ok", res.ok)
	_eq("costo build", res.cost, 5)
	_eq("Risorse Sindacato dopo build", state.get_resources("syndicate"), 10)
	_eq("nuovo Casinò chiuso a Pinar",
		state.space_state("pinar_del_rio").count("syndicate", "casino", "closed"), 1)
	_eq("Casinò totali a Pinar", state.space_state("pinar_del_rio").count("syndicate", "casino"), before + 1)


func _sa() -> Array:
	# [mod, gd, state, specials]
	var r := _new_game()
	var sa := CubaLibreSpecials.new(r[2], r[0])
	return [r[0], r[1], r[2], sa]


func _test_sa_government() -> void:
	print("\n[Att.Speciale — Governo]")
	# Transport
	var r := _sa()
	var state: GameState = r[2]
	var sa: CubaLibreSpecials = r[3]
	var res = sa.transport({"from": "havana", "to": "la_habana", "count": 3})
	_check("transport ok", res.ok)
	_eq("Truppe a Havana dopo Transport", state.space_state("havana").count("government", "troops"), 3)
	_eq("Truppe a La Habana dopo Transport", state.space_state("la_habana").count("government", "troops"), 3)
	# Air Strike normale
	var r2 := _sa()
	var st2: GameState = r2[2]
	var sa2: CubaLibreSpecials = r2[3]
	st2.space_state("matanzas").add_piece("m26", "guerrilla", 1, "active")
	var res2 = sa2.air_strike({"space": "matanzas"})
	_check("air strike ok", res2.ok)
	_eq("Guerriglia rimossa da Air Strike", st2.space_state("matanzas").count("m26", "guerrilla"), 0)
	# Air Strike vietato in Embargo
	var r3 := _sa()
	var st3: GameState = r3[2]
	var sa3: CubaLibreSpecials = r3[3]
	st3.tracks["us_alliance"] = 2
	st3.space_state("matanzas").add_piece("m26", "guerrilla", 1, "active")
	var res3 = sa3.air_strike({"space": "matanzas"})
	_check("air strike bloccato in Embargo", not res3.ok)
	# Reprisal
	var r4 := _sa()
	var st4: GameState = r4[2]
	var sa4: CubaLibreSpecials = r4[3]
	st4.space_state("matanzas").add_piece("government", "troops", 2)  # Govt controlla, Opp Passiva (-1)
	st4.space_state("matanzas").add_piece("m26", "guerrilla", 1, "active")
	st4.recompute_all_control()
	var res4 = sa4.reprisal({"space": "matanzas", "move": {"faction": "m26", "to": "la_habana"}})
	_check("reprisal ok", res4.ok)
	_eq("Reprisal: Terrore a Matanzas", st4.space_state("matanzas").marker("terror"), 1)
	_eq("Reprisal: Opposizione -> Neutrale", st4.space_state("matanzas").support, CoinEnums.Support.NEUTRAL)
	# La Habana ha già 1 Guerriglia M26 nello schieramento iniziale -> dopo lo spostamento 2
	_eq("Reprisal: Guerriglia spostata a La Habana", st4.space_state("la_habana").count("m26", "guerrilla"), 2)
	_eq("Reprisal: Guerriglia rimossa da Matanzas", st4.space_state("matanzas").count("m26", "guerrilla"), 0)


func _test_sa_m26() -> void:
	print("\n[Att.Speciale — 26 Luglio]")
	# Infiltrate
	var r := _sa()
	var state: GameState = r[2]
	var sa: CubaLibreSpecials = r[3]
	state.space_state("oriente").add_piece("government", "police", 1)
	state.space_state("oriente").add_piece("m26", "guerrilla", 1, "underground")
	var res = sa.infiltrate({"space": "oriente"})
	_check("infiltrate ok", res.ok)
	_eq("Polizia rimossa da Infiltrazione", state.space_state("oriente").count("government", "police"), 0)
	_eq("Guerriglia M26 piazzata", state.space_state("oriente").count("m26", "guerrilla"), 2)
	# Ambush
	var r2 := _sa()
	var st2: GameState = r2[2]
	var sa2: CubaLibreSpecials = r2[3]
	st2.space_state("matanzas").add_piece("m26", "guerrilla", 1, "underground")
	st2.space_state("matanzas").add_piece("government", "police", 2)
	var res2 = sa2.ambush("m26", {"space": "matanzas"})
	_check("ambush ok", res2.ok)
	_eq("Ambush rimuove 2 Polizia", st2.space_state("matanzas").count("government", "police"), 0)
	# Kidnap con tiro
	var r3 := _sa()
	var st3: GameState = r3[2]
	var sa3: CubaLibreSpecials = r3[3]
	st3.space_state("havana").add_piece("m26", "guerrilla", 5, "underground")  # 5 > 4 Polizia
	var gov_before := st3.get_resources("government")
	var m26_before := st3.get_resources("m26")
	var res3 = sa3.kidnap({"space": "havana", "target": "government", "die": 4})
	_check("kidnap ok", res3.ok)
	_eq("Kidnap: -4 Risorse Govt", st3.get_resources("government"), gov_before - 4)
	_eq("Kidnap: +4 Risorse M26", st3.get_resources("m26"), m26_before + 4)
	_eq("Kidnap: Casinò chiuso a Havana", st3.space_state("havana").count("syndicate", "casino", "closed"), 1)
	# Kidnap con Denaro del Riscatto
	var r4 := _sa()
	var st4: GameState = r4[2]
	var sa4: CubaLibreSpecials = r4[3]
	st4.space_state("havana").add_piece("m26", "guerrilla", 5, "underground")
	st4.place_cash("havana", "syndicate", 1)
	sa4.kidnap({"space": "havana", "target": "syndicate"})
	_eq("Kidnap: Denaro trasferito a M26", st4.space_state("havana").cash_for("m26"), 1)


func _test_sa_directorio() -> void:
	print("\n[Att.Speciale — Directorio]")
	# Subvert (Camagüey Provincia: DR controllata, Pop 1, Opp Passiva)
	var r := _sa()
	var state: GameState = r[2]
	var sa: CubaLibreSpecials = r[3]
	var dr_before := state.get_resources("directorio")
	var res = sa.subvert({"space": "camaguey_province"})
	_check("subvert ok", res.ok)
	_eq("Subvert: +1 Risorse DR", state.get_resources("directorio"), dr_before + 1)
	_eq("Subvert: spazio Neutrale", state.space_state("camaguey_province").support, CoinEnums.Support.NEUTRAL)
	# Assassinate
	var r2 := _sa()
	var st2: GameState = r2[2]
	var sa2: CubaLibreSpecials = r2[3]
	st2.space_state("camaguey_province").add_piece("government", "troops", 1)  # bersaglio
	var res2 = sa2.assassinate({"space": "camaguey_province"})
	_check("assassinate ok", res2.ok)
	_eq("Assassinio rimuove la Truppa", st2.space_state("camaguey_province").count("government", "troops"), 0)


func _test_sa_syndicate() -> void:
	print("\n[Att.Speciale — Sindacato]")
	# Profit cash
	var r := _sa()
	var state: GameState = r[2]
	var sa: CubaLibreSpecials = r[3]
	var res = sa.profit({"mode": "cash", "spaces": ["havana"]})
	_check("profit cash ok", res.ok)
	_eq("Denaro Sindacato a Havana", state.space_state("havana").cash_for("syndicate"), 1)
	# Profit convert (chiude Casinò a Pinar -> +3)
	var r2 := _sa()
	var st2: GameState = r2[2]
	var sa2: CubaLibreSpecials = r2[3]
	var syn_before := st2.get_resources("syndicate")
	sa2.profit({"mode": "convert", "close": ["pinar_del_rio"]})
	_eq("Profit convert: +3 Risorse", st2.get_resources("syndicate"), syn_before + 3)
	_eq("Casinò chiuso a Pinar", st2.space_state("pinar_del_rio").count("syndicate", "casino", "closed"), 1)
	# Muscle (Polizia verso Havana, Città con Casinò aperto)
	var r3 := _sa()
	var st3: GameState = r3[2]
	var sa3: CubaLibreSpecials = r3[3]
	var res3 = sa3.muscle({"type": "police", "from": "camaguey_city", "to": "havana", "count": 2})
	_check("muscle ok", res3.ok)
	_eq("Polizia mossa a Havana", st3.space_state("havana").count("government", "police"), 6)
	# Bribe (rimuove 2 cubi, -3 Risorse)
	var r4 := _sa()
	var st4: GameState = r4[2]
	var sa4: CubaLibreSpecials = r4[3]
	st4.space_state("matanzas").add_piece("government", "troops", 2)
	var syn4 := st4.get_resources("syndicate")
	var res4 = sa4.bribe({"space": "matanzas", "action": "cubes", "count": 2})
	_check("bribe ok", res4.ok)
	_eq("Bribe: -3 Risorse Sindacato", st4.get_resources("syndicate"), syn4 - 3)
	_eq("Bribe: 2 Truppe rimosse", st4.space_state("matanzas").count("government", "troops"), 0)


func _prop() -> Array:
	var r := _new_game()
	var prop := CubaLibrePropaganda.new(r[2], r[0])
	return [r[0], r[1], r[2], prop]


func _test_propaganda_resources() -> void:
	print("\n[Propaganda — Risorse]")
	var r := _prop()
	var state: GameState = r[2]
	var prop: CubaLibrePropaganda = r[3]
	prop.resources_phase()
	# Govt: 15 + (Econ 8 + Aiuti 15) + Cresta 2 (Havana, controllo Govt) = 40
	_eq("Risorse Governo dopo Risorse", state.get_resources("government"), 40)
	# M26: 10 + Basi(1) = 11
	_eq("Risorse M26 dopo Risorse", state.get_resources("m26"), 11)
	# DR: 5 + spazi con pezzi DR (Havana, Camagüey Prov) = 7
	_eq("Risorse DR dopo Risorse", state.get_resources("directorio"), 7)
	# Sindacato: 15 + 2*Casinò aperti(3) - Cresta 2 = 19
	_eq("Risorse Sindacato dopo Risorse", state.get_resources("syndicate"), 19)


func _test_propaganda_support_reset() -> void:
	print("\n[Propaganda — Supporto + Sistemazione]")
	var r := _prop()
	var state: GameState = r[2]
	var prop: CubaLibrePropaganda = r[3]
	# Supporto: Totale Supporto 16 <= 18 -> Alleanza scende, Aiuti -10
	prop.support_phase()
	_eq("Alleanza USA scesa a Vacillante", int(state.tracks.get("us_alliance", 0)), 1)
	_eq("Aiuti dopo -10", int(state.tracks.get("aid", 0)), 5)
	# Sistemazione: Guerriglie -> Clandestine, Casinò -> aperti, marker rimossi, Disponibili
	state.space_state("sierra_maestra").add_piece("m26", "guerrilla", 1, "active")
	state.flip_pieces("syndicate", "casino", "pinar_del_rio", "open", "closed")
	state.space_state("matanzas").add_marker("terror", 2)
	state.eligibility["government"] = CoinEnums.Eligibility.INELIGIBLE
	prop.reset_phase()
	_eq("Guerriglie tornate Clandestine",
		state.space_state("sierra_maestra").count("m26", "guerrilla", "active"), 0)
	_eq("Casinò riaperti a Pinar",
		state.space_state("pinar_del_rio").count("syndicate", "casino", "open"), 1)
	_eq("Terrore rimosso", state.space_state("matanzas").marker("terror"), 0)
	_eq("Disponibilità ripristinata", state.eligibility["government"], CoinEnums.Eligibility.ELIGIBLE)


func _test_propaganda_victory() -> void:
	print("\n[Propaganda — Vittoria]")
	var r := _prop()
	var state: GameState = r[2]
	var prop: CubaLibrePropaganda = r[3]
	# All'inizio nessun vincitore
	_eq("Nessun vincitore iniziale", prop.victory_phase().winner, "")
	# Forza vittoria M26: porta più spazi a Opposizione Attiva (Tot Opp + Basi > 15)
	for sid in ["oriente", "las_villas", "la_habana", "matanzas", "camaguey_province", "sierra_maestra"]:
		state.set_support(sid, CoinEnums.Support.ACTIVE_OPPOSITION)
	# Tot Opp = 2*(2+2+1+1+1+1)=16 ; +1 Base M26 = 17 > 15
	var vp := prop.victory_phase()
	_eq("Vincitore M26", vp.winner, "m26")


func _test_cards_data() -> void:
	print("\n[Carte — dati]")
	var mod := CubaLibreModule.new()
	var gd := mod.build_game_def()
	_eq("48 carte Evento caricate", gd.cards.size(), 48)
	_eq("Ordine fazioni #1 (1ª)", gd.card(1).faction_order[0], "government")
	_eq("Ordine fazioni #1 (2ª)", gd.card(1).faction_order[1], "m26")
	_eq("Ordine fazioni #7 (1ª)", gd.card(7).faction_order[0], "government")
	_eq("Ordine fazioni #13 (1ª)", gd.card(13).faction_order[0], "m26")
	_eq("Ordine fazioni #48 (1ª)", gd.card(48).faction_order[0], "syndicate")
	_eq("Titolo #18", gd.card(18).title, "Pact of Caracas")


func _test_events() -> void:
	print("\n[Eventi]")
	# #7 Election (unshaded): 1 Guerriglia M26 in ogni Città
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var ev := CubaLibreEvents.new(state, mod)
	var before := state.count_on_map("m26", "guerrilla")
	var res := ev.apply(7, "unshaded", "m26")
	_check("Election ok", res.ok)
	_eq("Election: +3 Guerriglie M26 (3 Città)", state.count_on_map("m26", "guerrilla"), before + 3)

	# #11 Batista Flees (unshaded), die=3
	var r2 := _new_game()
	var st2: GameState = r2[2]
	var ev2 := CubaLibreEvents.new(st2, r2[0])
	var t_before := st2.count_on_map("government", "troops")
	ev2.apply(11, "unshaded", "government", {"die": 3})
	_eq("Batista Flees: Govt -10 Ris", st2.get_resources("government"), 5)
	_eq("Batista Flees: -3 Truppe", st2.count_on_map("government", "troops"), t_before - 3)

	# #34 US Speaking Tour (shaded): Govt +min(8,Aiuti), Aiuti +8
	var r3 := _new_game()
	var st3: GameState = r3[2]
	var ev3 := CubaLibreEvents.new(st3, r3[0])
	ev3.apply(34, "shaded", "government")
	_eq("US Speaking Tour: Govt +8", st3.get_resources("government"), 23)
	_eq("US Speaking Tour: Aiuti 23", int(st3.tracks.get("aid", 0)), 23)

	# #46 Sinatra (shaded): Casinò aperto a Havana + Denaro
	var r4 := _new_game()
	var st4: GameState = r4[2]
	var ev4 := CubaLibreEvents.new(st4, r4[0])
	ev4.apply(46, "shaded", "syndicate")
	_eq("Sinatra: 2 Casinò aperti a Havana", st4.space_state("havana").count("syndicate", "casino", "open"), 2)
	_eq("Sinatra: 1 Denaro a Havana", st4.space_state("havana").cash_for("syndicate"), 1)

	# Capacità: #18 Pact of Caracas registra la Capacità (effetto manuale)
	var r5 := _new_game()
	var st5: GameState = r5[2]
	var ev5 := CubaLibreEvents.new(st5, r5[0])
	var res5 := ev5.apply(18, "unshaded", "m26")
	_check("Pact of Caracas registra Capacità", st5.active_capabilities.has("Pact of Caracas"))

	# Tutti i 48 eventi ora sono automatizzati (nessun fallback manuale)
	var r6 := _new_game()
	var ev6 := CubaLibreEvents.new(r6[2], r6[0])
	var res6 := ev6.apply(25, "unshaded", "directorio")
	_check("Evento #25 ora automatizzato (non manuale)", not res6.get("manual", false))


func _test_all_events() -> void:
	print("\n[Eventi — smoke test 1..48 entrambi i lati]")
	var auto_count := 0
	var manual_count := 0
	var fail := 0
	for n in range(1, 49):
		for side in ["unshaded", "shaded"]:
			var r := _new_game()
			var mod: CubaLibreModule = r[0]
			var st: GameState = r[2]
			var ev := CubaLibreEvents.new(st, mod)
			var first := mod.build_game_def().card(n).faction_order[0]
			var res := ev.apply(n, side, first)
			if not res.get("ok", false):
				fail += 1
				print("  [FAIL] #%d %s: %s" % [n, side, res.get("log", [])])
			elif res.get("manual", false):
				manual_count += 1
			else:
				auto_count += 1
	_check("Tutti gli eventi eseguono senza errori (fail=%d)" % fail, fail == 0)
	_eq("Eventi automatizzati (96 lati attesi)", auto_count, 96)
	print("  (automatizzati=%d, manuali=%d)" % [auto_count, manual_count])


func _test_capabilities() -> void:
	print("\n[Modificatori Capacità/Momentum]")
	# Sánchez Mosquera: Assalto in Montagna come Città (capacità 4+2 invece di 2)
	var r := _ops()
	var st: GameState = r[2]
	var ops: CubaLibreOperations = r[3]
	st.active_momentum.append("Sánchez Mosquera")
	st.space_state("oriente").add_piece("government", "troops", 4)
	st.space_state("oriente").add_piece("m26", "guerrilla", 4, "active")
	ops.assault({"spaces": ["oriente"]})
	_eq("Sánchez Mosquera: Assalto montagna rimuove 4", st.space_state("oriente").count("m26", "guerrilla", "active"), 0)

	# S.I.M.: la Polizia conta come Truppe nell'Assalto
	var r2 := _ops()
	var st2: GameState = r2[2]
	var ops2: CubaLibreOperations = r2[3]
	st2.active_momentum.append("S.I.M.")
	st2.space_state("matanzas").add_piece("government", "troops", 1)
	st2.space_state("matanzas").add_piece("government", "police", 3)
	st2.space_state("matanzas").add_piece("m26", "guerrilla", 4, "active")
	ops2.assault({"spaces": ["matanzas"]})
	_eq("S.I.M.: Polizia conta come Truppe (rimosse 4)", st2.space_state("matanzas").count("m26", "guerrilla", "active"), 0)

	# Guantánamo Bay: Attacco Aereo rimuove 2
	var r3 := _ops()
	var st3: GameState = r3[2]
	var sa3 := CubaLibreSpecials.new(st3, r3[0])
	st3.active_momentum.append("Guantánamo Bay")
	st3.space_state("matanzas").add_piece("m26", "guerrilla", 2, "active")
	sa3.air_strike({"space": "matanzas"})
	_eq("Guantánamo: Attacco Aereo rimuove 2", st3.space_state("matanzas").count("m26", "guerrilla"), 0)

	# Morgan: il DR può Marciare entro 2 spazi (pinar -> matanzas via la_habana)
	var r4 := _ops()
	var st4: GameState = r4[2]
	var ops4: CubaLibreOperations = r4[3]
	st4.space_state("pinar_del_rio").add_piece("directorio", "guerrilla", 1, "underground")
	var res_no := ops4.march({"faction": "directorio", "moves": [{"from": "pinar_del_rio", "to": "matanzas", "count": 1}]})
	_check("Senza Morgan: Marcia a 2 spazi vietata", not res_no.ok)
	st4.active_capabilities.append("Morgan")
	var res_yes := ops4.march({"faction": "directorio", "moves": [{"from": "pinar_del_rio", "to": "matanzas", "count": 1}]})
	_check("Con Morgan: Marcia a 2 spazi consentita", res_yes.ok)

	# El Che: il 1º gruppo 26July che Marcia resta Clandestino
	var r5 := _ops()
	var st5: GameState = r5[2]
	var ops5: CubaLibreOperations = r5[3]
	st5.active_capabilities.append("El Che")
	st5.space_state("la_habana").add_piece("m26", "guerrilla", 3, "underground")  # ora 4
	ops5.march({"faction": "m26", "moves": [{"from": "la_habana", "to": "havana", "count": 3}]})
	_eq("El Che: Guerriglie restano Clandestine a Havana", st5.space_state("havana").count("m26", "guerrilla", "active"), 0)

	# Guantánamo Bay (Capacità): 26July può Sequestrare a Sierra Maestra come fosse Città
	var r6 := _ops()
	var st6: GameState = r6[2]
	var sa6 := CubaLibreSpecials.new(st6, r6[0])
	st6.space_state("sierra_maestra").remove_piece("government", "police", 9, "")
	st6.space_state("sierra_maestra").add_piece("m26", "guerrilla", 2, "underground")
	var k_no := sa6.kidnap({"space": "sierra_maestra", "target": "government", "die": 3})
	_check("Senza Guantánamo: Sequestro a Sierra Maestra vietato", not k_no.ok)
	st6.active_capabilities.append("Guantánamo Bay")
	var k_yes := sa6.kidnap({"space": "sierra_maestra", "target": "government", "die": 3})
	_check("Con Guantánamo: Sequestro a Sierra Maestra consentito", k_yes.ok)

	# Pact of Caracas (Capacità): l'Imboscata di 26July non rimuove i pezzi del Directorio
	var r7 := _ops()
	var st7: GameState = r7[2]
	var sa7 := CubaLibreSpecials.new(st7, r7[0])
	st7.space_state("matanzas").add_piece("m26", "guerrilla", 1, "underground")
	st7.space_state("matanzas").add_piece("directorio", "guerrilla", 1, "active")
	st7.space_state("matanzas").add_piece("government", "troops", 1)
	st7.active_capabilities.append("Pact of Caracas")
	sa7.ambush("m26", {"space": "matanzas"})
	_eq("Pact of Caracas: l'Imboscata 26J NON tocca le Guerriglie DR", st7.space_state("matanzas").count("directorio", "guerrilla"), 1)
	_eq("Pact of Caracas: l'Imboscata 26J rimuove comunque il cubo Govt", st7.space_state("matanzas").count("government", "troops"), 0)

	# Mafia Offensive (Capacità): il Sindacato può Assassinare, ignorando la Polizia
	var r8 := _ops()
	var st8: GameState = r8[2]
	var sa8 := CubaLibreSpecials.new(st8, r8[0])
	st8.space_state("matanzas").add_piece("syndicate", "guerrilla", 1, "underground")
	st8.space_state("matanzas").add_piece("government", "police", 2)
	st8.space_state("matanzas").add_piece("m26", "guerrilla", 1, "active")
	var a_no := sa8.assassinate({"space": "matanzas", "faction": "syndicate"})
	_check("Senza Mafia Offensive: il Sindacato non può Assassinare", not a_no.ok)
	st8.active_capabilities.append("Mafia Offensive")
	var a_yes := sa8.assassinate({"space": "matanzas", "faction": "syndicate"})
	_check("Con Mafia Offensive: il Sindacato Assassina ignorando la Polizia", a_yes.ok)


func _test_game_loop() -> void:
	print("\n[Loop di gioco — partita automatica]")
	var gc = load("res://scenes/GameController.gd").new()
	gc.new_game()
	_eq("Carte rimaste dopo la prima pesca", gc.cards_left(), 51)
	gc.run_full_game()
	_check("La partita automatica termina (game_over)", gc.game_over)
	_check("Al più 4 Propaganda giocate", gc.propaganda_played <= 4)
	gc.free()


func _test_victory_initial() -> void:
	print("\n[Vittoria iniziale]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var vs := mod.victory_status(state)
	_check("Nessuna Fazione ha vinto all'inizio",
		not (vs["government"].won or vs["m26"].won or vs["directorio"].won or vs["syndicate"].won))
	_eq("Margine Governo", vs["government"].margin, -2)
	_eq("Margine 26 Luglio", vs["m26"].margin, -8)
	_eq("Margine Directorio", vs["directorio"].margin, -8)
	_eq("Margine Sindacato", vs["syndicate"].margin, -15)


# ---------------------------------------------------------------------------
# Calixto (motore NP generico)
# ---------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _test_calixto_data() -> void:
	var cards := _load_json("res://games/cuba_libre/data/calixto_cards.json")
	var factions := ["government", "m26", "directorio", "syndicate"]
	for fac in factions:
		_check("Calixto: 6 carte %s" % fac, cards.has(fac) and cards[fac].size() == 6)
		for letter in cards.get(fac, {}):
			var c: Dictionary = cards[fac][letter]
			_check("Calixto %s-%s fronte+retro" % [fac, letter], c.has("front") and c.has("back"))
	# AN insorti presenti
	var an_ok := true
	for fac in ["m26", "directorio", "syndicate"]:
		for letter in cards.get(fac, {}):
			if cards[fac][letter]["front"].get("an", null) == null:
				an_ok = false
	_check("Calixto: AN insorti presenti", an_ok)
	var tables := _load_json("res://games/cuba_libre/data/calixto_tables.json")
	_check("Calixto: tabella eligibility", tables.has("eligibility"))
	_check("Calixto: space_selection 4 fazioni", tables.has("space_selection")
		and tables["space_selection"].has("government") and tables["space_selection"].has("syndicate"))
	_check("Calixto: move_priorities", tables.has("move_priorities"))


func _test_calixto_deck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var deck := CalixtoDeck.new({
		"government": ["U", "Y", "Z", "X", "W", "V"],
		"m26": ["G", "H", "J", "K", "L", "M"],
	}, rng)
	_eq("Deck: 12 carte", deck.size(), 12)
	var top := deck.draw_for("m26")
	_check("Deck: pesca carta 26J", top in ["G", "H", "J", "K", "L", "M"])
	var nxt := deck.draw_next("m26")
	_check("Deck: pesca successiva 26J", nxt in ["G", "H", "J", "K", "L", "M"])


func _test_calixto_engine() -> void:
	var side := {
		"flow": [
			{"cond": "a", "t": "next", "f": "draw"},
			{"cond": "b", "t": "op:sweep", "f": "flip"}
		],
		"ops": {"sweep": {"type": "sweep"}},
		"special": [{"sa": "transport"}]
	}
	var all_true := func(_n): return true
	var r1 = CalixtoEngine.walk(side, all_true)
	_eq("Engine: a&b veri -> op sweep", r1["op_id"], "sweep")
	var a_false := func(n): return n.get("cond", "") != "a"
	var r2 = CalixtoEngine.walk(side, a_false)
	_eq("Engine: a falso -> draw", r2["result"], "draw")
	var b_false := func(n): return n.get("cond", "") != "b"
	var r3 = CalixtoEngine.walk(side, b_false)
	_eq("Engine: b falso -> flip", r3["result"], "flip")
	# incondizionata: usa prima op
	var uncond := {"flow": [{"t": "op:train"}], "ops": {"train": {}}}
	var r4 = CalixtoEngine.walk(uncond, all_true)
	_eq("Engine: incondizionata -> train", r4["op_id"], "train")
	# special_by_branch
	var side2 := {"special_by_branch": {"march": [{"sa": "infiltrate"}], "terror": [{"sa": "kidnap"}]}}
	_eq("Engine: specials ramo march", CalixtoEngine.specials_for(side2, "march")[0]["sa"], "infiltrate")


func _test_calixto_bot() -> void:
	print("\n[Calixto Bot]")
	var r := _new_game()
	var mod: CubaLibreModule = r[0]
	var state: GameState = r[2]
	var bot := CLCalixto.new(state, mod)
	for fac in ["government", "m26", "directorio", "syndicate"]:
		var res := bot.take_turn(fac)
		_check("Calixto bot %s azione valida" % fac,
			res.has("action") and res.has("log") and String(res["action"]) != "")
	# Una manciata di turni non deve generare errori
	var ok := true
	for i in range(8):
		var res2 := bot.take_turn(["government", "m26", "directorio", "syndicate"][i % 4])
		if not res2.has("action"):
			ok = false
	_check("Calixto bot: turni multipli stabili", ok)
	# Scelta Evento: restituisce una decisione valida e non corrompe lo stato originale
	var before := state.to_dict()
	var ec := bot.event_choice("m26", 5)
	_check("Calixto event_choice valido", ec.has("play"))
	_check("Calixto event_choice non muta lo stato", state.to_dict().hash() == before.hash())
