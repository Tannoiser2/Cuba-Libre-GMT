class_name PieceToken
extends Button

## Piccolo token che rappresenta un gruppo di pezzi (Fazione + tipo) in uno spazio.
## È sorgente di drag-and-drop: trascinandolo si avvia lo spostamento di 1 pezzo.

var from_id: String
var faction: String
var type: String
var pstate: String


var _tex: Texture2D


func setup(p_from: String, p_faction: String, p_type: String, p_state: String, label: String) -> void:
	from_id = p_from
	faction = p_faction
	type = p_type
	pstate = p_state
	_tex = CLAssets.piece(p_faction, p_type, p_state)
	if _tex != null:
		icon = _tex
		expand_icon = true
		custom_minimum_size = Vector2(27, 27)
		flat = true
		# Niente padding/bordo del Button: i pezzi restano compatti e adiacenti.
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, empty)
		add_theme_constant_override("h_separation", 0)
		tooltip_text = "%s - trascina per spostare 1 pezzo" % label
	else:
		text = label
		add_theme_font_size_override("font_size", 10)
		custom_minimum_size = Vector2(0, 18)
		add_theme_color_override("font_color", GameController.faction_color(p_faction))


func _get_drag_data(_pos: Vector2) -> Variant:
	if _tex != null:
		var preview := TextureRect.new()
		preview.texture = _tex
		preview.custom_minimum_size = Vector2(26, 26)
		preview.size = Vector2(26, 26)
		set_drag_preview(preview)
	else:
		var lbl := Label.new()
		lbl.text = text
		set_drag_preview(lbl)
	return {
		"kind": "piece",
		"from": from_id,
		"faction": faction,
		"type": type,
		"state": pstate,
	}
