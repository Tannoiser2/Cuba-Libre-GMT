class_name SidePanel
extends PanelContainer

## Colonna di destra: carta corrente e prossima (cliccabili per ingrandirle), sintesi
## dell'Evento, pannello Vittoria numerico e registro delle azioni.
##
## Si aggiorna da sé leggendo lo stato dal controller; alla scena resta solo da
## chiamare `refresh()` e da mostrare l'ingrandimento quando arriva `card_zoom_requested`
## (l'overlay va a schermo intero, quindi non può stare dentro questo pannello).

signal card_zoom_requested(texture: Texture2D)

const CARD_SIZE := Vector2(150, 200)
const MIN_WIDTH := 380.0

## Metrica di vittoria di ogni Fazione (nome breve mostrato nel pannello).
const VIC_LABEL := {
	"government": "Supporto", "m26": "Opp.+Basi",
	"directorio": "Pop.+Basi", "syndicate": "Casinò",
}
const ALLIANCE_NAMES := ["Salda", "Riluttante", "Embargo"]

var log_view: LogView          ## esposto: la scena ci collega i segnali del controller

var _card_img: TextureRect
var _next_card_img: TextureRect
var _card_label: RichTextLabel
var _vic: RichTextLabel


func _init() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	# Contenuto scrollabile: niente che esca dal riquadro.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# Carte: corrente e prossima, affiancate.
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 6)
	vb.add_child(cards_row)
	_card_img = _add_card_column(cards_row, "Corrente", CLTheme.ACCENT, 1.0)
	_next_card_img = _add_card_column(cards_row, "Prossima", CLTheme.TEXT_DIM, 0.75)

	_card_label = RichTextLabel.new()
	_card_label.bbcode_enabled = true
	_card_label.fit_content = true
	_card_label.add_theme_font_size_override("normal_font_size", 12)
	_card_label.custom_minimum_size = Vector2(330, 48)
	vb.add_child(_card_label)
	vb.add_child(HSeparator.new())

	# Pannello Vittoria: valore/soglia/margine di ogni Fazione + Risorse, sempre visibile.
	vb.add_child(_title("Vittoria"))
	_vic = RichTextLabel.new()
	_vic.bbcode_enabled = true
	_vic.fit_content = true
	_vic.scroll_active = false
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size",
			"bold_italics_font_size", "mono_font_size"]:
		_vic.add_theme_font_size_override(fs, 11)
	_vic.add_theme_constant_override("line_separation", 3)
	vb.add_child(_vic)
	vb.add_child(HSeparator.new())

	vb.add_child(_title("Log"))
	# Log ad altezza fissa, sempre visibile e scrollabile.
	log_view = LogView.new()
	log_view.custom_minimum_size = Vector2(340, 260)
	vb.add_child(log_view)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## Colonna con etichetta e anteprima cliccabile della carta.
func _add_card_column(row: HBoxContainer, title: String, color: Color, alpha: float) -> TextureRect:
	var col := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", color)
	col.add_child(lbl)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img.custom_minimum_size = CARD_SIZE
	img.modulate = Color(1, 1, 1, alpha)
	img.mouse_filter = Control.MOUSE_FILTER_STOP
	img.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	img.tooltip_text = "Clicca per ingrandire"
	img.gui_input.connect(_on_card_input.bind(img))
	col.add_child(img)
	row.add_child(col)
	return img


func _on_card_input(event: InputEvent, img: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if img.texture != null:
			emit_signal("card_zoom_requested", img.texture)


## Aggiorna carte, sintesi dell'Evento e pannello Vittoria dallo stato corrente.
func refresh() -> void:
	var s: GameState = GameController.state
	var cc: int = s.current_card
	_card_img.texture = CLAssets.card(cc) if cc >= 0 else null
	var nc: int = GameController.next_card()
	_next_card_img.texture = CLAssets.card(nc) if nc >= 0 else null
	_card_label.text = GameController.current_card_text()
	_refresh_victory(s)


## Per ogni Fazione valore/soglia (margine) e Risorse; sotto, Aiuti e Alleanza USA.
## Senza questo riquadro i numeri si leggerebbero solo contando le celle del tracciato.
func _refresh_victory(s: GameState) -> void:
	var vs: Dictionary = GameController.victory()
	var txt := ""
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var d: Dictionary = vs.get(fid, {})
		var m := int(d.get("margin", 0))
		var mcol := CLTheme.OK.to_html(false) if m >= 0 else CLTheme.ERR.to_html(false)
		# Le Fazioni NP che non tracciano Risorse mostrano un trattino, non uno zero.
		var res_txt := str(s.get_resources(fid)) if s.tracks_resources(fid) else "—"
		txt += "%s %s [b]%d[/b]/%d [color=#%s](%+d)[/color] · Risorse %s\n" % [
			CLTheme.faction_chip(CLNames.faction_short(fid), fid), VIC_LABEL.get(fid, ""),
			int(d.get("value", 0)), int(d.get("threshold", 0)), mcol, m, res_txt]
	var alliance: int = clampi(int(s.tracks.get("us_alliance", 0)), 0, 2)
	txt += "[color=#%s]Aiuti %d · Alleanza USA: %s[/color]" % [
		CLTheme.TEXT_DIM.to_html(false), int(s.tracks.get("aid", 0)), ALLIANCE_NAMES[alliance]]
	_vic.text = txt
