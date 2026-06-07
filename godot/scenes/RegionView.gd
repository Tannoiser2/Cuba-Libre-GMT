class_name RegionView
extends Control

## Zona di uno spazio sagomata sui contorni della mappa. Il Control copre l'intera mappa
## ma reagisce (clic/drag-and-drop) solo dentro il poligono, grazie a `_has_point()`.
## Disegna l'evidenziazione lungo il contorno e tinge il territorio col colore del controllante.
## I pezzi e i marcatori sono impilati sull'`anchor`.

signal space_clicked(space_id: String)
signal piece_dropped(from_id: String, to_id: String, faction: String, type: String)

var space_id: String
var space_def: SpaceDef
var _poly_norm: PackedVector2Array = PackedVector2Array()
var _anchor_norm := Vector2(0.5, 0.5)
var _highlight := false
var _control := ""

var _stack: VBoxContainer


func setup(sd: SpaceDef, poly: Array, anchor: Vector2) -> void:
	space_id = sd.id
	space_def = sd
	_anchor_norm = anchor
	for p in poly:
		_poly_norm.append(Vector2(p[0], p[1]))
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = sd.name

	# Contenitore pezzi/marcatori (posizionato sull'anchor in _relayout)
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 0)
	_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_stack)


func _scaled_poly() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _poly_norm:
		out.append(Vector2(p.x * size.x, p.y * size.y))
	return out


# Definisce la regione cliccabile: solo dentro il poligono.
func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _scaled_poly())


func relayout() -> void:
	# Posiziona lo stack centrato sull'anchor
	_stack.reset_size()
	var a := Vector2(_anchor_norm.x * size.x, _anchor_norm.y * size.y)
	_stack.position = a - _stack.size * 0.5
	queue_redraw()


func refresh(state: GameState) -> void:
	var st: SpaceState = state.space_state(space_id)
	_control = st.control
	for c in _stack.get_children():
		c.queue_free()

	# Marcatori
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 1)
	mrow.mouse_filter = Control.MOUSE_FILTER_PASS
	_stack.add_child(mrow)
	if st.control != "":
		_add_marker(mrow, CLAssets.control(st.control))
	if space_def.has_population() and st.support != 0:
		_add_marker(mrow, CLAssets.support(st.support))
	for i in range(st.marker("terror")):
		_add_marker(mrow, CLAssets.terror())
	if st.marker("sabotage") > 0:
		_add_marker(mrow, CLAssets.sabotage())

	# Pezzi (sprite trascinabili)
	var prow := HFlowContainer.new()
	prow.add_theme_constant_override("h_separation", 1)
	prow.add_theme_constant_override("v_separation", 1)
	prow.custom_minimum_size = Vector2(72, 0)
	prow.mouse_filter = Control.MOUSE_FILTER_PASS
	_stack.add_child(prow)
	for fid in ["government", "m26", "directorio", "syndicate"]:
		for g in _piece_groups(st, fid):
			for k in range(g.count):
				var tok := PieceToken.new()
				prow.add_child(tok)
				tok.setup(space_id, fid, g.type, g.state, "%s %s" % [fid, g.type])
		for k in range(st.cash_for(fid)):
			_add_marker(prow, CLAssets.cash())

	call_deferred("relayout")


func _add_marker(parent: Node, t: Texture2D) -> void:
	if t == null:
		return
	var tr := TextureRect.new()
	tr.texture = t
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(13, 13)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)


func _piece_groups(st: SpaceState, fid: String) -> Array:
	var groups: Array = []
	var defs := [
		["troops", ""], ["police", ""], ["base", ""],
		["guerrilla", "underground"], ["guerrilla", "active"],
		["casino", "open"], ["casino", "closed"],
	]
	for d in defs:
		var n := st.count(fid, d[0], d[1] if d[1] != "" else null)
		if n > 0:
			groups.append({"type": d[0], "state": d[1], "count": n})
	return groups


func set_highlight(on: bool) -> void:
	_highlight = on
	queue_redraw()


func _draw() -> void:
	var poly := _scaled_poly()
	if poly.size() < 3:
		return
	# Tinta del territorio secondo il controllante
	if _control != "":
		var col := GameController.faction_color(_control)
		col.a = 0.22
		draw_colored_polygon(poly, col)
	# Contorno (giallo se evidenziato)
	var line := poly + PackedVector2Array([poly[0]])
	draw_polyline(line, Color("f1c40f") if _highlight else Color(1, 1, 1, 0.35),
		3.0 if _highlight else 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("space_clicked", space_id)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "piece"


func _drop_data(_pos: Vector2, data: Variant) -> void:
	emit_signal("piece_dropped", data["from"], space_id, data["faction"], data["type"])
