class_name BottomStrip
extends HBoxContainer

## Striscia sotto la mappa: carta corrente (e prossima), Risorse, Vittoria e registro.
## Sostituisce la vecchia colonna laterale (SidePanel): stessi contenuti, ma su fogli
## di carta affiancati, così la colonna di destra resta tutta per il pannello azione.
##
## Si aggiorna da sé leggendo lo stato dal controller; alla scena resta solo da
## chiamare `refresh()` e da mostrare l'ingrandimento quando arriva `card_zoom_requested`.

signal card_zoom_requested(texture: Texture2D)

const HEIGHT := 152.0
const FACTIONS := ["government", "m26", "directorio", "syndicate"]
## Metrica di vittoria di ogni Fazione (nome breve mostrato nel pannello).
const VIC_LABEL := {
	"government": "Supporto", "m26": "Opp. + Basi",
	"directorio": "Pop DR + Basi", "syndicate": "Casinò aperti",
}
const ALLIANCE_NAMES := ["Salda", "Riluttante", "Embargo"]

var log_view: LogView          ## esposto: la scena ci collega i segnali del controller

var _card_img: TextureRect
var _card_head: Label
var _card_title: Label
var _card_text: Label
var _next_img: TextureRect
var _next_lbl: Label
var _res_rows: Dictionary = {}    ## fid -> {bar, val}
var _vic_rows: Dictionary = {}    ## fid -> {bar, val}
var _aid_lbl: Label
var _alliance_lbl: Label


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_constant_override("separation", 8)
	add_child(_build_card())
	add_child(_build_resources())
	add_child(_build_victory())
	add_child(_build_log())


func _paper(min_w: float, stretch: float) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = CLTheme.paper_theme()
	pc.add_theme_stylebox_override("panel", CLTheme.paper_box(10.0))
	pc.custom_minimum_size = Vector2(min_w, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = stretch
	pc.clip_contents = true
	return pc


func _build_card() -> Control:
	var pc := _paper(250, 1.15)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	_card_img = TextureRect.new()
	_card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_img.custom_minimum_size = Vector2(94, 130)
	_card_img.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_img.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_card_img.tooltip_text = "Clicca per ingrandire"
	_card_img.gui_input.connect(_on_card_input.bind(_card_img))
	h.add_child(_card_img)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_card_head = CLTheme.label("", CLTheme.INK_DIM, 12, CLTheme.ui_bold())
	v.add_child(_card_head)
	_card_title = CLTheme.label("", CLTheme.INK, 23, CLTheme.display())
	_card_title.clip_text = true
	v.add_child(_card_title)
	_card_text = CLTheme.label("", CLTheme.INK, 12, CLTheme.typewriter())
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_text.clip_text = true
	_card_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card_text.custom_minimum_size = Vector2(120, 0)
	v.add_child(_card_text)
	var nx := HBoxContainer.new()
	nx.add_theme_constant_override("separation", 6)
	v.add_child(nx)
	_next_img = TextureRect.new()
	_next_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_next_img.custom_minimum_size = Vector2(25, 34)
	_next_img.mouse_filter = Control.MOUSE_FILTER_STOP
	_next_img.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_next_img.tooltip_text = "Prossima carta: clicca per ingrandire"
	_next_img.gui_input.connect(_on_card_input.bind(_next_img))
	nx.add_child(_next_img)
	_next_lbl = CLTheme.label("", CLTheme.INK_DIM, 13)
	_next_lbl.clip_text = true
	_next_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nx.add_child(_next_lbl)
	return pc


func _build_resources() -> Control:
	var pc := _paper(200, 0.85)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	v.add_child(CLTheme.section_title("Risorse"))
	for fid in FACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var tok := TextureRect.new()
		tok.texture = CLAssets.res_token(fid)
		tok.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tok.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tok.custom_minimum_size = Vector2(14, 18)
		row.add_child(tok)
		var nl := CLTheme.label(CLNames.faction_tile(fid), CLTheme.INK, 14)
		nl.custom_minimum_size = Vector2(66, 0)
		row.add_child(nl)
		var bar := MeterBar.new()
		bar.color = CLTheme.faction_ink(fid)
		bar.max_value = 49
		bar.bar_height = 7
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var val := CLTheme.label("", CLTheme.INK, 15, CLTheme.ui_heavy())
		val.custom_minimum_size = Vector2(22, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		v.add_child(row)
		_res_rows[fid] = {"bar": bar, "val": val}
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 5)
	foot.add_child(_icon(CLAssets.aid_marker(), 18))
	_aid_lbl = CLTheme.label("", CLTheme.INK_DIM, 13)
	foot.add_child(_aid_lbl)
	foot.add_child(_icon(CLAssets.alliance_marker(), 18))
	_alliance_lbl = CLTheme.label("", CLTheme.INK_DIM, 13)
	_alliance_lbl.clip_text = true
	_alliance_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_alliance_lbl)
	v.add_child(foot)
	return pc


func _build_victory() -> Control:
	var pc := _paper(210, 0.95)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	var t := CLTheme.section_title("Vittoria")
	t.tooltip_text = "La tacca nera è la soglia da superare"
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(t)
	for fid in FACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var nl := CLTheme.label(VIC_LABEL[fid], CLTheme.INK, 14)
		nl.custom_minimum_size = Vector2(78, 0)
		nl.clip_text = true
		row.add_child(nl)
		var bar := MeterBar.new()
		bar.color = CLTheme.faction_ink(fid)
		bar.bar_height = 12
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var val := CLTheme.label("", CLTheme.INK, 15, CLTheme.ui_heavy())
		val.custom_minimum_size = Vector2(40, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		v.add_child(row)
		_vic_rows[fid] = {"bar": bar, "val": val, "row": row}
	return pc


func _build_log() -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", CLTheme.dark_box(CLTheme.LOG_BG, CLTheme.LOG_EDGE))
	pc.custom_minimum_size = Vector2(220, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = 1.15
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	v.add_child(CLTheme.section_title("Registro", CLTheme.BRASS))
	log_view = LogView.new()
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 60)
	v.add_child(log_view)
	return pc


func _icon(tex: Texture2D, h: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(h, h)
	return r


func _on_card_input(event: InputEvent, img: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if img.texture != null:
			card_zoom_requested.emit(img.texture)


## Aggiorna carte, Risorse e Vittoria dallo stato corrente.
func refresh() -> void:
	var gc = GameController
	var s: GameState = gc.state
	if s == null:
		return
	var cc: int = s.current_card
	_card_img.texture = CLAssets.card(cc) if cc >= 0 else null
	if gc.game_over:
		_card_head.text = "PARTITA CONCLUSA"
		_card_title.text = "Vince %s" % gc.faction_name(gc.winner) if gc.winner != "" else "Fine"
		_card_text.text = ""
	elif cc == -1:
		_card_head.text = "MAZZO"
		_card_title.text = "Mazzo esaurito"
		_card_text.text = ""
	elif cc == 0:
		_card_head.text = "CARTA CORRENTE"
		_card_title.text = "Propaganda (%d/4)" % (gc.propaganda_played + 1)
		_card_text.text = "Round di Propaganda: vittoria, risorse, supporto, spostamento e ripristino."
	else:
		var c: CardDef = gc.game_def.card(cc)
		var tag := ""
		if c.is_capability: tag = " · CAPACITÀ"
		elif c.is_momentum: tag = " · MOMENTUM"
		_card_head.text = "CARTA CORRENTE · %d%s" % [c.number, tag]
		_card_title.text = c.title
		_card_text.text = c.translation
		_card_text.tooltip_text = c.translation
	var nc: int = gc.next_card()
	_next_img.texture = CLAssets.card(nc) if nc >= 0 else null
	if nc > 0:
		_next_lbl.text = "Prossima: %d · %s" % [nc, gc.game_def.card(nc).title]
	elif nc == 0:
		_next_lbl.text = "Prossima: Propaganda"
	else:
		_next_lbl.text = "Nessun'altra carta"
	# Risorse
	for fid in FACTIONS:
		var r: Dictionary = _res_rows[fid]
		var tracks := s.tracks_resources(fid)
		(r["val"] as Label).text = str(s.get_resources(fid)) if tracks else "—"
		(r["bar"] as MeterBar).set_values(s.get_resources(fid) if tracks else 0, -1)
	_aid_lbl.text = "Aiuti %d" % int(s.tracks.get("aid", 0))
	var alliance: int = clampi(int(s.tracks.get("us_alliance", 0)), 0, 2)
	_alliance_lbl.text = "Alleanza USA: %s" % ALLIANCE_NAMES[alliance]
	# Vittoria
	var vs: Dictionary = gc.victory()
	for fid in FACTIONS:
		var d: Dictionary = vs.get(fid, {})
		var val := int(d.get("value", 0))
		var thr := int(d.get("threshold", 0))
		var r2: Dictionary = _vic_rows[fid]
		var bar: MeterBar = r2["bar"]
		bar.max_value = maxf(thr * 1.45, val + 2.0)
		bar.set_values(val, thr)
		(r2["val"] as Label).text = "%d/%d" % [val, thr]
		(r2["row"] as Control).tooltip_text = "%s: %d (soglia %d, margine %+d)" % [
			gc.faction_name(fid), val, thr, int(d.get("margin", 0))]


## Barra orizzontale con tacca di soglia facoltativa (Risorse, Vittoria).
class MeterBar:
	extends Control

	var color := Color.WHITE
	var max_value := 26.0
	var bar_height := 10.0
	var _value := 0.0
	var _threshold := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(30, bar_height + 6)

	func set_values(v: float, thr: float) -> void:
		_value = v
		_threshold = thr
		queue_redraw()

	func _draw() -> void:
		var y := (size.y - bar_height) * 0.5
		var r := Rect2(0, y, size.x, bar_height)
		draw_rect(r, Color("d8caa6"))
		var frac := clampf(_value / maxf(1.0, max_value), 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(0, y, size.x * frac, bar_height), color)
		if _threshold >= 0.0:
			var tx := size.x * clampf(_threshold / maxf(1.0, max_value), 0.0, 1.0)
			draw_rect(Rect2(tx - 1, y - 3, 2, bar_height + 6), CLTheme.INK)
