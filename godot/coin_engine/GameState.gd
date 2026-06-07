class_name GameState
extends RefCounted

## Stato mutabile completo di una partita COIN.
## Riferisce un GameDef immutabile e contiene gli stati degli spazi, le risorse delle
## Fazioni, i tracciati globali, la disponibilità (sequenza di gioco) e il mazzo.

var game_def: GameDef

var spaces: Dictionary = {}              ## space_id -> SpaceState
var resources: Dictionary = {}          ## faction_id -> int
var tracks: Dictionary = {}             ## track_id -> int (es. "aid", "us_alliance" idx)
var eligibility: Dictionary = {}        ## faction_id -> CoinEnums.Eligibility

# Mazzo / sequenza di gioco
var draw_deck: Array[int] = []          ## numeri carta (cima = ultimo)
var played_deck: Array[int] = []
var current_card: int = -1

## Capacità/Momentum attivi (id evento) — effetti duraturi.
var active_capabilities: PackedStringArray = PackedStringArray()
var active_momentum: PackedStringArray = PackedStringArray()


func _init(p_game_def: GameDef = null) -> void:
	game_def = p_game_def
	if game_def != null:
		for s in game_def.spaces:
			spaces[s.id] = SpaceState.new(s.id)
		for f in game_def.factions:
			resources[f.id] = 0
			eligibility[f.id] = CoinEnums.Eligibility.ELIGIBLE


func space_state(id: String) -> SpaceState:
	return spaces.get(id, null)


# ---------------------------------------------------------------------------
# Risorse
# ---------------------------------------------------------------------------

func get_resources(faction: String) -> int:
	return int(resources.get(faction, 0))


func add_resources(faction: String, delta: int, cap: int = 49) -> void:
	resources[faction] = clampi(get_resources(faction) + delta, 0, cap)


# ---------------------------------------------------------------------------
# Controllo (regola COIN standard: pezzi di una Fazione > somma di tutte le altre)
# I pezzi in stati "non rilevanti" (es. Casinò chiusi) non contano.
# ---------------------------------------------------------------------------

func control_count(faction: String, st: SpaceState) -> int:
	var total := 0
	if not st.pieces.has(faction):
		return 0
	for type_id in st.pieces[faction].keys():
		var pt: PieceTypeDef = game_def.piece_type(type_id)
		for state in st.pieces[faction][type_id].keys():
			if pt != null and not pt.state_counts_for_control(state):
				continue
			total += int(st.pieces[faction][type_id][state])
	return total


func recompute_control(space_id: String) -> void:
	var st: SpaceState = spaces[space_id]
	var sd: SpaceDef = game_def.space(space_id)
	# Gli EC tipicamente non hanno Controllo "politico" rilevante per la vittoria,
	# ma la regola generale di confronto resta valida; calcoliamo comunque.
	var best_faction := ""
	var best := 0
	var others_total := 0
	var counts: Dictionary = {}
	for f in game_def.factions:
		var c := control_count(f.id, st)
		counts[f.id] = c
		others_total += c
		if c > best:
			best = c
			best_faction = f.id
	# Controlla se best supera la somma di tutti gli altri.
	if best > 0 and best > (others_total - best):
		st.control = best_faction
	else:
		st.control = ""


func recompute_all_control() -> void:
	for sid in spaces.keys():
		recompute_control(sid)


# ---------------------------------------------------------------------------
# Totali di Supporto / Opposizione (meccanica COIN standard)
# ---------------------------------------------------------------------------

func total_support() -> int:
	var sum := 0
	for sid in spaces.keys():
		var sd: SpaceDef = game_def.space(sid)
		if not sd.has_population():
			continue
		var lvl: int = spaces[sid].support
		if lvl > 0:
			sum += lvl * sd.pop
	return sum


func total_opposition() -> int:
	var sum := 0
	for sid in spaces.keys():
		var sd: SpaceDef = game_def.space(sid)
		if not sd.has_population():
			continue
		var lvl: int = spaces[sid].support
		if lvl < 0:
			sum += (-lvl) * sd.pop
	return sum


# ---------------------------------------------------------------------------
# Conteggi di pezzi su tutta la mappa
# ---------------------------------------------------------------------------

func count_on_map(faction: String, type: String = "") -> int:
	var total := 0
	for sid in spaces.keys():
		total += spaces[sid].count(faction, type)
	return total


## Numero di Basi (pezzi is_base) di una Fazione sulla mappa, opzionalmente filtrando
## per stato non rilevante (es. Casinò chiusi non contano se exclude_non_counting=true).
func base_count(faction: String, exclude_non_counting: bool = false) -> int:
	var total := 0
	for sid in spaces.keys():
		var st: SpaceState = spaces[sid]
		if not st.pieces.has(faction):
			continue
		for type_id in st.pieces[faction].keys():
			var pt: PieceTypeDef = game_def.piece_type(type_id)
			if pt == null or not pt.is_base:
				continue
			for state in st.pieces[faction][type_id].keys():
				if exclude_non_counting and not pt.state_counts_for_control(state):
					continue
				total += int(st.pieces[faction][type_id][state])
	return total


## Popolazione totale degli spazi controllati da una Fazione.
func controlled_population(faction: String) -> int:
	var sum := 0
	for sid in spaces.keys():
		if spaces[sid].control == faction:
			sum += game_def.space(sid).pop
	return sum


# ---------------------------------------------------------------------------
# Serializzazione (save/load)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var sp := {}
	for sid in spaces.keys():
		sp[sid] = spaces[sid].to_dict()
	return {
		"version": 1,
		"spaces": sp,
		"resources": resources.duplicate(true),
		"tracks": tracks.duplicate(true),
		"eligibility": eligibility.duplicate(true),
		"draw_deck": draw_deck.duplicate(),
		"played_deck": played_deck.duplicate(),
		"current_card": current_card,
		"active_capabilities": Array(active_capabilities),
		"active_momentum": Array(active_momentum),
	}


## Crea un GameState da un dizionario salvato, dato il GameDef di riferimento.
static func from_dict(p_game_def: GameDef, d: Dictionary) -> GameState:
	var gs := GameState.new(p_game_def)
	var sp: Dictionary = d.get("spaces", {})
	for sid in sp.keys():
		if gs.spaces.has(sid):
			gs.spaces[sid].apply_dict(sp[sid])
	for k in d.get("resources", {}).keys():
		gs.resources[k] = int(d["resources"][k])
	gs.tracks = (d.get("tracks", {}) as Dictionary).duplicate(true)
	for k in d.get("eligibility", {}).keys():
		gs.eligibility[k] = int(d["eligibility"][k])
	gs.draw_deck.clear()
	for n in d.get("draw_deck", []):
		gs.draw_deck.append(int(n))
	gs.played_deck.clear()
	for n in d.get("played_deck", []):
		gs.played_deck.append(int(n))
	gs.current_card = int(d.get("current_card", -1))
	gs.active_capabilities = PackedStringArray(d.get("active_capabilities", []))
	gs.active_momentum = PackedStringArray(d.get("active_momentum", []))
	return gs


## Salva su file JSON. Restituisce true in caso di successo.
func save_to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Impossibile aprire per scrittura: %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


static func load_from_file(p_game_def: GameDef, path: String) -> GameState:
	if not FileAccess.file_exists(path):
		push_error("File di salvataggio non trovato: %s" % path)
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Salvataggio non valido: %s" % path)
		return null
	return GameState.from_dict(p_game_def, data)
