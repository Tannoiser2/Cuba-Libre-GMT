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
