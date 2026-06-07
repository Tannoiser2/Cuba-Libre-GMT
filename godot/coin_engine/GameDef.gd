class_name GameDef
extends RefCounted

## Definizione completa (immutabile) di un gioco COIN: fazioni, spazi, tipi di pezzo,
## tracciati. Popolata da un modulo di gioco (es. CubaLibreModule).

var title: String = ""

var factions: Array[FactionDef] = []          ## in ordine di gioco predefinito
var spaces: Array[SpaceDef] = []
var piece_types: Array[PieceTypeDef] = []
var cards: Array[CardDef] = []                ## mazzo (carte Evento)

## Tracciati globali: id -> { "min": int, "max": int }.
var tracks: Dictionary = {}

# --- indici per accesso rapido ---
var _faction_by_id: Dictionary = {}
var _space_by_id: Dictionary = {}
var _piece_by_id: Dictionary = {}
var _card_by_number: Dictionary = {}


func add_faction(f: FactionDef) -> void:
	factions.append(f)
	_faction_by_id[f.id] = f


func add_space(s: SpaceDef) -> void:
	spaces.append(s)
	_space_by_id[s.id] = s


func add_piece_type(p: PieceTypeDef) -> void:
	piece_types.append(p)
	_piece_by_id[p.id] = p


func add_card(c: CardDef) -> void:
	cards.append(c)
	_card_by_number[c.number] = c


func card(number: int) -> CardDef:
	return _card_by_number.get(number, null)


func faction(id: String) -> FactionDef:
	return _faction_by_id.get(id, null)


func space(id: String) -> SpaceDef:
	return _space_by_id.get(id, null)


func piece_type(id: String) -> PieceTypeDef:
	return _piece_by_id.get(id, null)


func faction_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in factions:
		out.append(f.id)
	return out


func space_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in spaces:
		out.append(s.id)
	return out
