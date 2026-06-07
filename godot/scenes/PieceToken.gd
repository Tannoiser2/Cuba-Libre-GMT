class_name PieceToken
extends Button

## Piccolo token che rappresenta un gruppo di pezzi (Fazione + tipo) in uno spazio.
## È sorgente di drag-and-drop: trascinandolo si avvia lo spostamento di 1 pezzo.

var from_id: String
var faction: String
var type: String
var pstate: String


func setup(p_from: String, p_faction: String, p_type: String, p_state: String, label: String) -> void:
	from_id = p_from
	faction = p_faction
	type = p_type
	pstate = p_state
	text = label
	add_theme_font_size_override("font_size", 10)
	custom_minimum_size = Vector2(0, 18)
	add_theme_color_override("font_color", GameController.faction_color(p_faction))
	tooltip_text = "Trascina per spostare 1 pezzo"


func _get_drag_data(_pos: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {
		"kind": "piece",
		"from": from_id,
		"faction": faction,
		"type": type,
		"state": pstate,
	}
