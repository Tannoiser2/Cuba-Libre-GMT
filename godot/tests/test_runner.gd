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
