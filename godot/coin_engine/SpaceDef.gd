class_name SpaceDef
extends RefCounted

## Definizione (immutabile) di uno spazio della mappa.

var id: String
var name: String
var type: CoinEnums.SpaceType = CoinEnums.SpaceType.PROVINCE
var terrain: String = ""            ## "forest","grassland","mountain" o "" (Città/EC)
var pop: int = 0                    ## Popolazione (Province/Città)
var econ: int = 0                   ## valore Economico (EC)
var adjacent: PackedStringArray = PackedStringArray()


func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	name = p_name


static func type_from_string(s: String) -> CoinEnums.SpaceType:
	match s.to_lower():
		"city": return CoinEnums.SpaceType.CITY
		"ec", "economic": return CoinEnums.SpaceType.ECONOMIC
		"loc": return CoinEnums.SpaceType.LOC
		"country": return CoinEnums.SpaceType.COUNTRY
		_: return CoinEnums.SpaceType.PROVINCE


static func from_dict(d: Dictionary) -> SpaceDef:
	var s := SpaceDef.new(d.get("id", ""), d.get("name", ""))
	s.type = type_from_string(String(d.get("type", "province")))
	s.terrain = String(d.get("terrain", "")) if d.get("terrain") != null else ""
	s.pop = int(d.get("pop", 0))
	s.econ = int(d.get("econ", 0))
	for a in d.get("adjacent", []):
		s.adjacent.append(String(a))
	return s


## Può contenere Supporto/Opposizione? (Province e Città con Popolazione)
func has_population() -> bool:
	return type == CoinEnums.SpaceType.PROVINCE or type == CoinEnums.SpaceType.CITY


## È un Centro Economico?
func is_economic() -> bool:
	return type == CoinEnums.SpaceType.ECONOMIC
