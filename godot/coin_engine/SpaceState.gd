class_name SpaceState
extends RefCounted

## Stato mutabile di un singolo spazio: pezzi presenti, Supporto/Opposizione,
## Controllo, marker (Terrore/Sabotaggio, ecc.).

var space_id: String

## Pezzi: pieces[faction_id][piece_type_id][state] = conteggio.
## Per i pezzi senza stati alternativi si usa lo stato "" .
var pieces: Dictionary = {}

## Livello di Supporto/Opposizione (solo spazi con Popolazione).
var support: CoinEnums.Support = CoinEnums.Support.NEUTRAL

## Fazione che Controlla lo spazio ("" = Incontrollato).
var control: String = ""

## Marker generici: nome -> conteggio (es. "terror", "sabotage").
var markers: Dictionary = {}

## Segnalini Denaro (Cash) presenti nello spazio: faction_id -> conteggio.
## (Posti "sotto" una Guerriglia/cubo della Fazione; qui ne tracciamo proprietà e luogo.)
var cash: Dictionary = {}


func _init(p_space_id: String = "") -> void:
	space_id = p_space_id


# ---------------------------------------------------------------------------
# Gestione pezzi
# ---------------------------------------------------------------------------

func add_piece(faction: String, type: String, count: int = 1, state: String = "") -> void:
	if count == 0:
		return
	if not pieces.has(faction):
		pieces[faction] = {}
	if not pieces[faction].has(type):
		pieces[faction][type] = {}
	var cur: int = pieces[faction][type].get(state, 0)
	pieces[faction][type][state] = cur + count


func remove_piece(faction: String, type: String, count: int = 1, state: String = "") -> int:
	## Rimuove fino a `count` pezzi; restituisce quanti effettivamente rimossi.
	if not _has(faction, type, state):
		return 0
	var cur: int = pieces[faction][type][state]
	var removed: int = min(cur, count)
	pieces[faction][type][state] = cur - removed
	if pieces[faction][type][state] <= 0:
		pieces[faction][type].erase(state)
	return removed


func _has(faction: String, type: String, state: String) -> bool:
	return pieces.has(faction) and pieces[faction].has(type) and pieces[faction][type].has(state)


## Conteggio di un tipo di pezzo (qualsiasi stato, o uno stato specifico se dato).
func count(faction: String, type: String = "", state = null) -> int:
	if not pieces.has(faction):
		return 0
	var total := 0
	for t in pieces[faction].keys():
		if type != "" and t != type:
			continue
		for st in pieces[faction][t].keys():
			if state != null and st != state:
				continue
			total += int(pieces[faction][t][st])
	return total


## Totale dei pezzi di una Fazione nello spazio.
func total_for(faction: String) -> int:
	return count(faction)


## Restituisce tutte le Fazioni con almeno un pezzo nello spazio.
func factions_present() -> PackedStringArray:
	var out := PackedStringArray()
	for f in pieces.keys():
		if count(f) > 0:
			out.append(f)
	return out


# ---------------------------------------------------------------------------
# Marker
# ---------------------------------------------------------------------------

func marker(name: String) -> int:
	return int(markers.get(name, 0))


func set_marker(name: String, value: int) -> void:
	if value <= 0:
		markers.erase(name)
	else:
		markers[name] = value


func add_marker(name: String, delta: int = 1) -> void:
	set_marker(name, marker(name) + delta)


# ---------------------------------------------------------------------------
# Serializzazione
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"space_id": space_id,
		"pieces": pieces.duplicate(true),
		"support": int(support),
		"control": control,
		"markers": markers.duplicate(true),
		"cash": cash.duplicate(true),
	}


func apply_dict(d: Dictionary) -> void:
	space_id = String(d.get("space_id", space_id))
	pieces = (d.get("pieces", {}) as Dictionary).duplicate(true)
	support = int(d.get("support", CoinEnums.Support.NEUTRAL))
	control = String(d.get("control", ""))
	markers = (d.get("markers", {}) as Dictionary).duplicate(true)
	cash = (d.get("cash", {}) as Dictionary).duplicate(true)


func cash_for(faction: String) -> int:
	return int(cash.get(faction, 0))


func add_cash(faction: String, n: int = 1) -> void:
	var v := cash_for(faction) + n
	if v <= 0:
		cash.erase(faction)
	else:
		cash[faction] = v
