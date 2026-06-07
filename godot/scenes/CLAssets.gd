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


## Immagine della carta: number 1..48, oppure 0 = Propaganda.
static func card(number: int) -> Texture2D:
	if number <= 0:
		return tex("cards/prop.png")
	return tex("cards/%02d.png" % number)


static func cash() -> Texture2D: return tex("cash.png")
static func terror() -> Texture2D: return tex("terror.png")
static func sabotage() -> Texture2D: return tex("sabotage.png")

# Token/segnalini dei tracciati (immagini originali)
static func res_token(faction: String) -> Texture2D: return tex("token_%s.png" % faction)
static func aid_marker() -> Texture2D: return tex("aid.png")
static func alliance_marker() -> Texture2D: return tex("us_alliance.png")
static func vic_support() -> Texture2D: return tex("vic_support.png")
static func vic_opp_bases() -> Texture2D: return tex("vic_opp_bases.png")
static func vic_dr() -> Texture2D: return tex("vic_dr.png")
static func vic_casinos() -> Texture2D: return tex("vic_casinos.png")
