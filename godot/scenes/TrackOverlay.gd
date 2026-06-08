class_name TrackOverlay
extends Control

## Disegna i segnalini sui tracciati e nelle caselle, usando le coordinate ESATTE estratte dal
## modulo Vassal (board_layout.json): celle del tracciato perimetrale 0-49, caselle Available
## Forces, US Alliance, Eligible/Ineligible. Cilindri Risorse, Aiuti, marcatori di vittoria,
## Alleanza USA, pezzi disponibili e idoneità delle Fazioni.

const MK := 26.0       # dimensione segnalino su tracciato
const STACK := 20.0    # scostamento per segnalini sulla stessa cella

var _track: Dictionary = {}    # "0".."49" -> [x,y] normalizzati
var _box: Dictionary = {}      # nome -> [x0,y0,x1,y1] normalizzati
var _circles: Dictionary = {}  # fazione -> [[x,y],...] centri dei cerchietti basi/casinò (Vassal)
var _loose: Dictionary = {}    # fazione -> tipo -> [x0,y0,x1,y1] area dei pezzi sciolti
var _disp: Dictionary = {}     # chiave segnalino -> valore mostrato (float, animato)
var _target: Dictionary = {}   # chiave segnalino -> valore obiettivo (int)


func _ready() -> void:
	var f := FileAccess.open("res://games/cuba_libre/data/board_layout.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_track = d.get("track", {})
			_box = d.get("box", {})
			_circles = d.get("avail_circles", {})
			_loose = d.get("avail_loose", {})


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
	_draw_capabilities(s)


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


# Quale "Base" sta sul tracciato a cerchietti di ogni box (le Basi/Casinò sono tonde
# e nel gioco reale si posano nei cerchietti numerati = quante ce ne sono sulla mappa).
const BASE_TRACK := {
	"government": "base", "syndicate": "casino", "m26": "base", "directorio": "base",
}


func _draw_available(s: GameState) -> void:
	var tok := size.x * 0.028
	# 1) Pezzi sciolti (cubi/guerriglie): ognuno disegnato singolarmente nell'area aperta del box.
	for fac in _loose:
		for t in _loose[fac]:
			var n := s.available(fac, t)
			if n <= 0:
				continue
			var st := "underground" if t == "guerrilla" else ""
			_fill_pieces(_rect_from(_loose[fac][t]), n, CLAssets.piece(fac, t, st), tok)
	# 2) Basi/Casinò: posate nei cerchietti, dal numero (Basi sulla mappa)+1 in su.
	#    Così il cerchietto vuoto più alto = quante Basi/Casinò ci sono sulla mappa.
	for fac in BASE_TRACK:
		var bt: String = BASE_TRACK[fac]
		var fdef: FactionDef = s.game_def.faction(fac)
		if fdef == null:
			continue
		var total := int(fdef.force_pool.get(bt, 0))
		var on_map := total - s.available(fac, bt)
		var circles: Array = _circles.get(fac, [])
		var st := "closed" if bt == "casino" else ""
		var tex := CLAssets.piece(fac, bt, st)
		var ctok := tok * 1.2
		for i in range(on_map + 1, total + 1):
			if i < 0 or i >= circles.size() or tex == null:
				continue
			var p: Array = circles[i]
			var c := Vector2(p[0] * size.x, p[1] * size.y)
			draw_texture_rect(tex, Rect2(c - Vector2(ctok, ctok) * 0.5, Vector2(ctok, ctok)), false)


func _rect_from(a: Array) -> Rect2:
	return Rect2(a[0] * size.x, a[1] * size.y, (a[2] - a[0]) * size.x, (a[3] - a[1]) * size.y)


## Distribuisce n copie del pezzo in una griglia adattiva dentro `rect` (impila in verticale
## se i pezzi disponibili sono molti, come le pedine ammucchiate nella scatola).
func _fill_pieces(rect: Rect2, n: int, tex: Texture2D, tok: float) -> void:
	if n <= 0 or tex == null:
		return
	var cols := maxi(1, int(rect.size.x / (tok * 0.9)))
	var rows := int(ceil(float(n) / float(cols)))
	var stepx := tok * 0.9
	var stepy := minf(tok * 0.9, rect.size.y / float(maxi(1, rows)))
	for i in n:
		var r := i / cols
		var c := i % cols
		var cx := rect.position.x + tok * 0.5 + c * stepx
		var cy := rect.position.y + tok * 0.5 + r * stepy
		draw_texture_rect(tex, Rect2(Vector2(cx - tok * 0.5, cy - tok * 0.5), Vector2(tok, tok)), false)


# Fazione a cui appartiene ogni Capacità Insorgente (per il colore del chip).
const CAP_FACTION := {
	"Guantánamo Bay": "m26", "El Che": "m26", "The Guerrilla Life": "m26",
	"Pact of Caracas": "directorio", "Morgan": "directorio",
	"Mafia Offensive": "syndicate", "Santo Trafficante Jr": "syndicate",
}


## Capacità Insorgenti attive: chip colorati nel box "Insurgent Capabilities" in basso.
func _draw_capabilities(s: GameState) -> void:
	var r := _box_rect("insurgent_capabilities")
	if r.size == Vector2.ZERO or s.active_capabilities.is_empty():
		return
	var font := ThemeDB.fallback_font
	var n := s.active_capabilities.size()
	# Altezza dei chip adattiva: tutti entrano sotto il titolo stampato del box.
	var top := r.position.y + r.size.y * 0.36
	var avail_h := r.size.y * 0.60
	var slot := avail_h / float(n)
	var ch := minf(20.0, slot - 3.0)
	var y := top
	for title in s.active_capabilities:
		var fac: String = CAP_FACTION.get(title, "m26")
		var chip := Rect2(r.position.x + r.size.x * 0.04, y, r.size.x * 0.92, ch)
		draw_rect(chip, GameController.faction_color(fac), true)
		draw_string(font, Vector2(chip.position.x + 8, y + ch * 0.76), String(title),
			HORIZONTAL_ALIGNMENT_LEFT, chip.size.x - 14, clampi(int(ch * 0.74), 9, 16), Color.WHITE)
		y += slot


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
