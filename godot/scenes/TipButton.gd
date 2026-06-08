class_name TipButton
extends Button

## Tasto con tooltip OPACO e a CAPO (il tooltip di default è trasparente e su una sola
## riga lunghissima, illeggibile).

func _make_custom_tooltip(for_text: String) -> Object:
	return TipButton.build_tip(for_text)


static func build_tip(for_text: String) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("11151c")            # sfondo pieno (non trasparente)
	sb.set_border_width_all(1)
	sb.border_color = Color("6f8197")
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = for_text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # va a capo
	l.custom_minimum_size = Vector2(320, 0)            # larghezza max -> più righe
	l.add_theme_color_override("font_color", Color("e6edf3"))
	l.add_theme_font_size_override("font_size", 12)
	pc.add_child(l)
	return pc
