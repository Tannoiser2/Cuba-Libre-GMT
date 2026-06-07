class_name FactionDef
extends RefCounted

## Definizione (immutabile) di una Fazione COIN.

var id: String                  ## es. "government", "m26", "directorio", "syndicate"
var name: String
var short_name: String
var color: String               ## nome/hex del colore della Fazione
var role: CoinEnums.FactionRole = CoinEnums.FactionRole.INSURGENT

## Forze totali disponibili: piece_type_id -> conteggio massimo.
var force_pool: Dictionary = {}

## Operazioni e Attività Speciali disponibili (id).
var operations: PackedStringArray = PackedStringArray()
var special_activities: PackedStringArray = PackedStringArray()

## Soglia di vittoria (semantica definita dal modulo di gioco).
var victory_threshold: int = 0
var victory_metric: String = ""


func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	name = p_name


static func from_dict(d: Dictionary) -> FactionDef:
	var f := FactionDef.new(d.get("id", ""), d.get("name", ""))
	f.short_name = String(d.get("shortName", d.get("short_name", f.name)))
	f.color = String(d.get("color", "white"))
	f.role = CoinEnums.FactionRole.COIN if String(d.get("type", "insurgent")) == "counterinsurgent" \
		else CoinEnums.FactionRole.INSURGENT
	for k in d.get("forces", {}).keys():
		f.force_pool[String(k)] = int(d["forces"][k])
	for op in d.get("operations", []):
		f.operations.append(String(op))
	for sa in d.get("specialActivities", d.get("special_activities", [])):
		f.special_activities.append(String(sa))
	var vic: Dictionary = d.get("victory", {})
	f.victory_metric = String(vic.get("metric", ""))
	f.victory_threshold = int(vic.get("threshold", 0))
	return f
