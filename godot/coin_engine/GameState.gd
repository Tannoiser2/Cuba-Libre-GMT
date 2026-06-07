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
# Forze disponibili (fuori mappa) e primitive di manipolazione
# ---------------------------------------------------------------------------

## Pezzi di un tipo ancora disponibili fuori mappa (pool totale - in gioco).
func available(faction: String, type: String) -> int:
	var f: FactionDef = game_def.faction(faction)
	if f == null:
		return 0
	var pool := int(f.force_pool.get(type, 0))
	return max(0, pool - count_on_map(faction, type))


## Piazza pezzi prelevandoli dalle forze disponibili. Restituisce quanti piazzati.
func place_from_available(faction: String, type: String, space_id: String,
		count: int = 1, state: String = "__default__") -> int:
	if not spaces.has(space_id) or count <= 0:
		return 0
	var st_str := _resolve_state(type, state)
	var n: int = min(count, available(faction, type))
	if n <= 0:
		return 0
	spaces[space_id].add_piece(faction, type, n, st_str)
	return n


## Rimuove pezzi dalla mappa (tornano disponibili). Restituisce quanti rimossi.
func remove_to_available(faction: String, type: String, space_id: String,
		count: int = 1, state = null) -> int:
	if not spaces.has(space_id):
		return 0
	var st: SpaceState = spaces[space_id]
	if state != null:
		return st.remove_piece(faction, type, count, String(state))
	# Rimuove indistintamente dagli stati disponibili fino a `count`.
	var removed := 0
	var pt: PieceTypeDef = game_def.piece_type(type)
	var states := pt.states if (pt != null and pt.states.size() > 0) else PackedStringArray([""])
	for s in states:
		if removed >= count:
			break
		removed += st.remove_piece(faction, type, count - removed, s)
	return removed


## Sposta pezzi da uno spazio all'altro. Restituisce quanti spostati.
func move_pieces(faction: String, type: String, from_id: String, to_id: String,
		count: int = 1, state: String = "") -> int:
	if not spaces.has(from_id) or not spaces.has(to_id):
		return 0
	var src: SpaceState = spaces[from_id]
	var dst: SpaceState = spaces[to_id]
	var moved := src.remove_piece(faction, type, count, state)
	if moved > 0:
		dst.add_piece(faction, type, moved, state)
	return moved


## Cambia lo stato di pezzi in uno spazio (es. Guerriglia underground->active). Restituisce quanti.
func flip_pieces(faction: String, type: String, space_id: String,
		from_state: String, to_state: String, count: int = -1) -> int:
	if not spaces.has(space_id):
		return 0
	var st: SpaceState = spaces[space_id]
	var have := st.count(faction, type, from_state)
	var n: int = have if count < 0 else mini(count, have)
	if n <= 0:
		return 0
	st.remove_piece(faction, type, n, from_state)
	st.add_piece(faction, type, n, to_state)
	return n


func set_support(space_id: String, level: CoinEnums.Support) -> void:
	if spaces.has(space_id):
		spaces[space_id].support = level


# ---------------------------------------------------------------------------
# Denaro (Cash) — limite globale 4 segnalini sulla mappa (Cuba Libre 4.5.2)
# ---------------------------------------------------------------------------

const CASH_LIMIT := 4

func total_cash_on_map() -> int:
	var total := 0
	for sid in spaces.keys():
		for fid in spaces[sid].cash.keys():
			total += int(spaces[sid].cash[fid])
	return total


## Piazza `n` segnalini Denaro per una Fazione (dal pool), entro il limite. Restituisce piazzati.
func place_cash(space_id: String, faction: String, n: int = 1) -> int:
	if not spaces.has(space_id):
		return 0
	var room := CASH_LIMIT - total_cash_on_map()
	var k: int = clampi(n, 0, room)
	if k > 0:
		spaces[space_id].add_cash(faction, k)
	return k


## Sposta la proprietà del Denaro a un'altra Fazione nello stesso spazio (Requisizione/Riscatto).
func transfer_cash(space_id: String, from_faction: String, to_faction: String, n: int = 1) -> int:
	if not spaces.has(space_id):
		return 0
	var st: SpaceState = spaces[space_id]
	var k: int = mini(n, st.cash_for(from_faction))
	if k > 0:
		st.add_cash(from_faction, -k)
		st.add_cash(to_faction, k)
	return k


func remove_cash(space_id: String, faction: String, n: int = 1) -> int:
	if not spaces.has(space_id):
		return 0
	var st: SpaceState = spaces[space_id]
	var k: int = mini(n, st.cash_for(faction))
	st.add_cash(faction, -k)
	return k


func _resolve_state(type: String, state: String) -> String:
	if state != "__default__":
		return state
	var pt: PieceTypeDef = game_def.piece_type(type)
	return pt.default_state if pt != null else ""


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
