class_name TrackOverlay
extends Control

## Disegna i segnalini sui tracciati e nelle caselle, usando le coordinate ESATTE estratte dal
## modulo Vassal (board_layout.json): celle del tracciato perimetrale 0–49, caselle Available
## Forces, US Alliance, Eligible/Ineligible. Cilindri Risorse, Aiuti, marcatori di vittoria,
## Alleanza USA, pezzi disponibili e idoneità delle Fazioni.

const MK := 26.0       # dimensione segnalino su tracciato
const STACK := 20.0    # scostamento per segnalini sulla stessa cella
const AV_PC := 20.0    # dimensione pezzo in riserva

var _track: Dictionary = {}   # "0".."49" -> [x,y] normalizzati
var _box: Dictionary = {}     # nome -> [x0,y0,x1,y1] normalizzati
var _disp: Dictionary = {}    # chiave segnalino -> valore mostrato (float, animato)
var _target: Dictionary = {}  # chiave segnalino -> valore obiettivo (int)


func _ready() -> void:
	var f := FileAccess.open("res://games/cuba_libre/data/board_layout.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_track = d.get("track", {})
			_box = d.get("box", {})


func _cell(value: int) -> Vector2:
	var v := clampi(value, 0, 49)
	var p: Array = _track.get(str(v), [0.5, 0.5])
	return Vector2(p[0] * size.x, p[1] * size.y)


func _box_rect(name: String) -> Rect2:
	var b: Array = _box.get(name, [0, 0, 0, 0])
	return Rect2(b[0] * size.x, b[1] * size.y, (b[2] - b[0]) * size.x, (b[3] - b[1]) * size.y)


func _draw() -> void:
	var s: GameState = GameController.state
	if s == null or _track.is_empty():
		return
	var mod: CubaLibreModule = GameController.module
	var chips := [
		["res_government", s.get_resources("government"), CLAssets.res_token("government")],
		["res_m26", s.get_resources("m26"), CLAssets.res_token("m26")],
		["res_directorio", s.get_resources("directorio"), CLAssets.res_token("directorio")],
		["res_syndicate", s.get_resources("syndicate"), CLAssets.res_token("syndicate")],
		["aid", int(s.tracks.get("aid", 0)), CLAssets.aid_marker()],
		["vic_support", s.total_support(), CLAssets.vic_support()],
		["vic_opp", mod.opposition_plus_bases(s), CLAssets.vic_opp_bases()],
		["vic_dr", mod.dr_pop_plus_bases(s), CLAssets.vic_dr()],
		["vic_casinos", mod.open_casinos(s), CLAssets.vic_casinos()],
	]
	var counts := {}
	for ch in chips:
		var key: String = ch[0]
		var v := clampi(int(ch[1]), 0, 49)
		_target[key] = v
		if not _disp.has(key):
			_disp[key] = float(v)
		var idx := int(counts.get(v, 0))
		counts[v] = idx + 1
		# Posizione animata (scivola lungo le celle); impila se stesso valore.
		var c := _interp_cell(float(_disp[key]))
		if v <= 30:
			c.y += idx * STACK
		else:
			c.x -= idx * STACK
		_blit(ch[2], c)

	# Alleanza USA nella casella attiva
	var ai := int(s.tracks.get("us_alliance", 0))
	var abox: String = ["us_alliance_firm", "us_alliance_reluctant", "us_alliance_embargoed"][ai]
	_blit(CLAssets.alliance_marker(), _box_rect(abox).get_center())

	_draw_available(s)
	_draw_eligibility(s)


## Posizione (schermo) interpolata tra le celle per un valore frazionario lungo il tracciato.
func _interp_cell(v: float) -> Vector2:
	var lo := clampi(int(floor(v)), 0, 49)
	var hi := clampi(lo + 1, 0, 49)
	return _cell(lo).lerp(_cell(hi), v - float(lo))


## Anima i segnalini verso il valore obiettivo (scivolano lungo il tracciato).
func _process(delta: float) -> void:
	var moving := false
	for key in _target:
		var cur: float = float(_disp.get(key, _target[key]))
		var tgt := float(_target[key])
		if abs(cur - tgt) > 0.02:
			_disp[key] = cur + (tgt - cur) * minf(1.0, delta * 7.0)
			moving = true
		else:
			_disp[key] = tgt
	if moving:
		queue_redraw()


func _blit(t: Texture2D, center: Vector2) -> void:
	if t == null:
		return
	draw_texture_rect(t, Rect2(center - Vector2(MK, MK) * 0.5, Vector2(MK, MK)), false)


const AVAIL := {
	"available_government": {"faction": "government", "types": ["troops", "police", "base"]},
	"available_syndicate": {"faction": "syndicate", "types": ["guerrilla", "casino"]},
	"available_directorio": {"faction": "directorio", "types": ["guerrilla", "base"]},
	"available_m26": {"faction": "m26", "types": ["guerrilla", "base"]},
}


func _draw_available(s: GameState) -> void:
	var font := ThemeDB.fallback_font
	for box_name in AVAIL:
		var cfg: Dictionary = AVAIL[box_name]
		var r := _box_rect(box_name)
		var x := r.position.x + 10.0
		# Sotto il titolo del riquadro (non sopra le scritte).
		var y := r.position.y + maxf(30.0, r.size.y * 0.34)
		for t in cfg["types"]:
			var n := s.available(cfg["faction"], t)
			if n <= 0:
				continue
			var st := "closed" if t == "casino" else ("underground" if t == "guerrilla" else "")
			var tex := CLAssets.piece(cfg["faction"], t, st)
			if tex != null:
				draw_texture_rect(tex, Rect2(Vector2(x, y), Vector2(AV_PC, AV_PC)), false)
			var label := "x%d" % n
			draw_string(font, Vector2(x + AV_PC + 4, y + AV_PC - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
			draw_string(font, Vector2(x + AV_PC + 3, y + AV_PC - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			x += 60.0


const ELIG_SZ := 24.0


func _draw_eligibility(s: GameState) -> void:
	# I cilindri vanno: nelle caselle azione (1ª/2ª Op/Op+SA/Evento/LimOp/Pass) se la Fazione
	# ha agito su questa carta; altrimenti in Eligible/Ineligible Factions.
	var seq = GameController.seq
	var counts := {}
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var key := ""
		if seq != null and seq.action_box.has(fid):
			key = String(seq.action_box[fid])
		elif int(s.eligibility.get(fid, 0)) == 0:
			key = "eligible"
		else:
			key = "ineligible"
		var r := _box_rect(key)
		if r.size == Vector2.ZERO:
			continue
		var t := CLAssets.res_token(fid)
		if t == null:
			continue
		var idx := int(counts.get(key, 0))
		counts[key] = idx + 1
		# Impilamento VERTICALE (centrato in orizzontale) nella casella/colonna.
		var pos := Vector2(r.position.x + r.size.x * 0.5 - ELIG_SZ * 0.5,
			r.position.y + 8.0 + idx * (ELIG_SZ + 4.0))
		draw_texture_rect(t, Rect2(pos, Vector2(ELIG_SZ, ELIG_SZ)), false)
