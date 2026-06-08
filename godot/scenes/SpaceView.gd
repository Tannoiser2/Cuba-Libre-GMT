class_name SpaceView
extends Panel

## Vista di uno spazio sovrapposta alla mappa reale: marcatori (Controllo/Supporto/Terrore)
## e sprite dei pezzi. Cliccabile (selezione guidata) e bersaglio del drag-and-drop.

signal space_clicked(space_id: String)
signal piece_dropped(from_id: String, to_id: String, faction: String, type: String)

var space_id: String
var space_def: SpaceDef

var _name_label: Label
var _markers: HBoxContainer
var _pieces: HFlowContainer
var _highlight := false


func setup(sd: SpaceDef) -> void:
	space_id = sd.id
	space_def = sd
	custom_minimum_size = Vector2(66, 34)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = sd.name

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 0)
	add_child(vb)

	# Riga marcatori (Controllo/Supporto/Terrore) - compatta
	_markers = HBoxContainer.new()
	_markers.add_theme_constant_override("separation", 1)
	vb.add_child(_markers)

	# Riga pezzi (sprite trascinabili)
	_pieces = HFlowContainer.new()
	_pieces.add_theme_constant_override("h_separation", 1)
	_pieces.add_theme_constant_override("v_separation", 1)
	vb.add_child(_pieces)


func refresh(state: GameState) -> void:
	var st: SpaceState = state.space_state(space_id)

	# Marcatori: Controllo, Supporto/Opposizione, Terrore/Sabotaggio
	for c in _markers.get_children():
		c.queue_free()
	if st.control != "":
		_add_marker(CLAssets.control(st.control))
	if space_def.has_population() and st.support != 0:
		_add_marker(CLAssets.support(st.support))
	for i in range(st.marker("terror")):
		_add_marker(CLAssets.terror())
	if st.marker("sabotage") > 0:
		_add_marker(CLAssets.sabotage())

	# Pezzi come sprite trascinabili
	for c in _pieces.get_children():
		c.queue_free()
	for fid in ["government", "m26", "directorio", "syndicate"]:
		for g in _piece_groups(st, fid):
			for k in range(g.count):
				var tok := PieceToken.new()
				_pieces.add_child(tok)
				tok.setup(space_id, fid, g.type, g.state, "%s %s" % [fid, g.type])
		var cash := st.cash_for(fid)
		for k in range(cash):
			_add_marker_to(_pieces, CLAssets.cash())

	_apply_style()


func _add_marker(t: Texture2D) -> void:
	_add_marker_to(_markers, t)


func _add_marker_to(parent: Node, t: Texture2D) -> void:
	if t == null:
		return
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(13, 13)
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
	_apply_style()


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)  # semitrasparente per lasciar vedere la mappa
	sb.set_border_width_all(2 if _highlight else 1)
	sb.border_color = Color("f1c40f") if _highlight else Color(1, 1, 1, 0.35)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("space_clicked", space_id)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "piece"


func _drop_data(_pos: Vector2, data: Variant) -> void:
	emit_signal("piece_dropped", data["from"], space_id, data["faction"], data["type"])
