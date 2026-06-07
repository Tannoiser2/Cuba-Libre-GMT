class_name CLAssets
extends RefCounted

## Caricamento/cache delle texture (mappa, pezzi, marcatori) di Cuba Libre.

const DIR := "res://games/cuba_libre/assets/"
static var _cache: Dictionary = {}


static func tex(file: String) -> Texture2D:
	if not _cache.has(file):
		var path := DIR + file
		_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _cache[file]


static func map() -> Texture2D:
	return tex("map.jpg")


## Texture del pezzo (faction, type, state).
static func piece(faction: String, type: String, state: String) -> Texture2D:
	match type:
		"troops": return tex("troops.png")
		"police": return tex("police.png")
		"base": return tex("base_%s.png" % faction)
		"casino": return tex("casino_%s.png" % ("open" if state == "open" else "closed"))
		"guerrilla":
			var s := state if state != "" else "underground"
			return tex("guerrilla_%s_%s.png" % [faction, s])
	return null


static func control(faction: String) -> Texture2D:
	return tex("control_%s.png" % faction)


static func support(level: int) -> Texture2D:
	match level:
		2: return tex("support_active.png")
		1: return tex("support_passive.png")
		-1: return tex("opposition_passive.png")
		-2: return tex("opposition_active.png")
	return null


static func cash() -> Texture2D: return tex("cash.png")
static func terror() -> Texture2D: return tex("terror.png")
static func sabotage() -> Texture2D: return tex("sabotage.png")
