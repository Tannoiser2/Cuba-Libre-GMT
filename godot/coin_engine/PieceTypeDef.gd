class_name PieceTypeDef
extends RefCounted

## Definizione (immutabile) di un tipo di pezzo, generica per la serie COIN.
## Esempi Cuba Libre: troops, police (cube); guerrilla (guerrilla); base, casino (base).

var id: String                      ## identificatore, es. "troops", "guerrilla", "casino"
var name: String                    ## nome leggibile
var category: CoinEnums.PieceCategory = CoinEnums.PieceCategory.OTHER
var is_base: bool = false           ## conta come Base ai fini di raggruppamento/protezione

## Stati possibili del pezzo (es. ["underground","active"] o ["open","closed"]).
## Vuoto se il pezzo non ha stati alternativi.
var states: PackedStringArray = PackedStringArray()
var default_state: String = ""      ## stato in cui il pezzo viene piazzato

## Stati in cui il pezzo NON conta per il Controllo (es. Casinò "closed").
var non_counting_states: PackedStringArray = PackedStringArray()


func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	name = p_name


## Costruisce da un dizionario (es. da JSON).
static func from_dict(d: Dictionary) -> PieceTypeDef:
	var pt := PieceTypeDef.new(d.get("id", ""), d.get("name", ""))
	match String(d.get("category", "other")).to_lower():
		"cube": pt.category = CoinEnums.PieceCategory.CUBE
		"guerrilla": pt.category = CoinEnums.PieceCategory.GUERRILLA
		"base": pt.category = CoinEnums.PieceCategory.BASE
		_: pt.category = CoinEnums.PieceCategory.OTHER
	pt.is_base = bool(d.get("is_base", pt.category == CoinEnums.PieceCategory.BASE))
	for s in d.get("states", []):
		pt.states.append(String(s))
	pt.default_state = String(d.get("default_state", pt.states[0] if pt.states.size() > 0 else ""))
	for s in d.get("non_counting_states", []):
		pt.non_counting_states.append(String(s))
	return pt


## Stato "non rilevante per il controllo"?
func state_counts_for_control(state: String) -> bool:
	return not non_counting_states.has(state)
