class_name CubaLibreModule
extends RulesModule

## Modulo di gioco "Cuba Libre" (Serie COIN Vol. II) per il motore COIN generico.

const DATA_DIR := "res://games/cuba_libre/data/"

## Mappatura delle chiavi usate nei dati di schieramento -> (piece_type, state).
const SETUP_FORCE_MAP := {
	"troops": ["troops", ""],
	"police": ["police", ""],
	"bases": ["base", ""],
	"guerrillas": ["guerrilla", "underground"],
	"casinos_open": ["casino", "open"],
	"casinos_closed": ["casino", "closed"],
}

const SUPPORT_KEY_MAP := {
	"active_support": CoinEnums.Support.ACTIVE_SUPPORT,
	"passive_support": CoinEnums.Support.PASSIVE_SUPPORT,
	"neutral": CoinEnums.Support.NEUTRAL,
	"passive_opposition": CoinEnums.Support.PASSIVE_OPPOSITION,
	"active_opposition": CoinEnums.Support.ACTIVE_OPPOSITION,
}


# ---------------------------------------------------------------------------
# Costruzione della definizione di gioco
# ---------------------------------------------------------------------------

func build_game_def() -> GameDef:
	var gd := GameDef.new()
	gd.title = "Cuba Libre"

	_register_piece_types(gd)

	# Spazi
	var spaces_data: Dictionary = _load_json(DATA_DIR + "spaces.json")
	for s in spaces_data.get("spaces", []):
		gd.add_space(SpaceDef.from_dict(s))

	# Fazioni
	var factions_data: Dictionary = _load_json(DATA_DIR + "factions.json")
	for f in factions_data.get("factions", []):
		gd.add_faction(FactionDef.from_dict(f))

	# Tracciati globali
	gd.tracks = {
		"aid": {"min": 0, "max": 49},
		"total_support": {"min": 0, "max": 50},
		"opposition_plus_bases": {"min": 0, "max": 50},
		"dr_pop_plus_bases": {"min": 0, "max": 50},
		"open_casinos": {"min": 0, "max": 10},
	}
	return gd


func _register_piece_types(gd: GameDef) -> void:
	var troops := PieceTypeDef.new("troops", "Truppe")
	troops.category = CoinEnums.PieceCategory.CUBE
	gd.add_piece_type(troops)

	var police := PieceTypeDef.new("police", "Polizia")
	police.category = CoinEnums.PieceCategory.CUBE
	gd.add_piece_type(police)

	var base := PieceTypeDef.new("base", "Base")
	base.category = CoinEnums.PieceCategory.BASE
	base.is_base = true
	gd.add_piece_type(base)

	var guerrilla := PieceTypeDef.new("guerrilla", "Guerriglia")
	guerrilla.category = CoinEnums.PieceCategory.GUERRILLA
	guerrilla.states = PackedStringArray(["underground", "active"])
	guerrilla.default_state = "underground"
	gd.add_piece_type(guerrilla)

	var casino := PieceTypeDef.new("casino", "Casinò")
	casino.category = CoinEnums.PieceCategory.BASE
	casino.is_base = true
	casino.states = PackedStringArray(["open", "closed"])
	casino.default_state = "open"
	casino.non_counting_states = PackedStringArray(["closed"])  # i Casinò chiusi non contano per il Controllo
	gd.add_piece_type(casino)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func apply_setup(state: GameState, scenario_id: String = "standard") -> void:
	var setup: Dictionary = _load_json(DATA_DIR + "setup_standard.json")

	# Marker / tracciati / risorse
	var markers: Dictionary = setup.get("markers", {})
	var res: Dictionary = markers.get("resources", {})
	for fid in res.keys():
		state.resources[fid] = int(res[fid])
	state.tracks["aid"] = int(markers.get("aid", 0))
	state.tracks["us_alliance"] = _alliance_index(String(markers.get("usAlliance", "solid")))

	# Supporto / Opposizione
	var so: Dictionary = setup.get("supportOpposition", {})
	for key in so.keys():
		if not SUPPORT_KEY_MAP.has(key):
			continue
		for sid in so[key]:
			if state.spaces.has(sid):
				state.spaces[sid].support = SUPPORT_KEY_MAP[key]

	# Forze
	var forces: Dictionary = setup.get("forces", {})
	for fid in forces.keys():
		for sid in forces[fid].keys():
			var stacks: Dictionary = forces[fid][sid]
			for force_key in stacks.keys():
				if not SETUP_FORCE_MAP.has(force_key):
					push_warning("Chiave forza sconosciuta nel setup: %s" % force_key)
					continue
				var mapping: Array = SETUP_FORCE_MAP[force_key]
				state.spaces[sid].add_piece(fid, mapping[0], int(stacks[force_key]), mapping[1])

	# Disponibilità: tutte Disponibili
	for f in state.game_def.factions:
		state.eligibility[f.id] = CoinEnums.Eligibility.ELIGIBLE

	# Calcola il Controllo dalle forze
	state.recompute_all_control()

	# Tracciati di vittoria iniziali
	_refresh_victory_tracks(state)


func _alliance_index(s: String) -> int:
	match s:
		"solid": return 0
		"wavering": return 1
		"embargo": return 2
		_: return 0


# ---------------------------------------------------------------------------
# Metriche / Vittoria specifiche di Cuba Libre
# ---------------------------------------------------------------------------

func open_casinos(state: GameState) -> int:
	var total := 0
	for sid in state.spaces.keys():
		total += state.spaces[sid].count("syndicate", "casino", "open")
	return total


func opposition_plus_bases(state: GameState) -> int:
	return state.total_opposition() + state.base_count("m26")


func dr_pop_plus_bases(state: GameState) -> int:
	return state.controlled_population("directorio") + state.base_count("directorio")


## Aggiorna i tracciati di bordo mappa dai conteggi correnti.
func _refresh_victory_tracks(state: GameState) -> void:
	state.tracks["total_support"] = state.total_support()
	state.tracks["opposition_plus_bases"] = opposition_plus_bases(state)
	state.tracks["dr_pop_plus_bases"] = dr_pop_plus_bases(state)
	state.tracks["open_casinos"] = open_casinos(state)


func all_cities_active_support(state: GameState) -> bool:
	for sid in state.spaces.keys():
		var sd: SpaceDef = state.game_def.space(sid)
		if sd.type == CoinEnums.SpaceType.CITY:
			if state.spaces[sid].support != CoinEnums.Support.ACTIVE_SUPPORT:
				return false
	return true


func victory_status(state: GameState) -> Dictionary:
	_refresh_victory_tracks(state)
	var ts := state.total_support()
	var opb := opposition_plus_bases(state)
	var drp := dr_pop_plus_bases(state)
	var casinos := open_casinos(state)
	var syn_res := state.get_resources("syndicate")

	var out := {}
	out["government"] = {
		"value": ts, "threshold": 18,
		"margin": ts - 18,
		"won": ts > 18 and all_cities_active_support(state),
	}
	out["m26"] = {
		"value": opb, "threshold": 15,
		"margin": opb - 15,
		"won": opb > 15,
	}
	out["directorio"] = {
		"value": drp, "threshold": 9,
		"margin": drp - 9,
		"won": drp > 9,
	}
	# Sindacato: margine = minore tra (Casinò - 7) e (Risorse - 30)
	var syn_margin: int = min(casinos - 7, syn_res - 30)
	out["syndicate"] = {
		"value": casinos, "threshold": 7,
		"resources": syn_res,
		"margin": syn_margin,
		"won": casinos > 7 and syn_res > 30,
	}
	return out


func tiebreak_order() -> PackedStringArray:
	# In caso di parità: Non-giocatore, poi Sindacato, Directorio, 26 Luglio (Governo ultimo).
	return PackedStringArray(["syndicate", "directorio", "m26", "government"])


# ---------------------------------------------------------------------------
# Utilità
# ---------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("File dati non trovato: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON non valido: %s" % path)
		return {}
	return data
