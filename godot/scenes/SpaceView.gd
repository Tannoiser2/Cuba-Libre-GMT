class_name SpaceView
extends Panel

## Vista di un singolo spazio della mappa. Mostra nome, Supporto/Opposizione, Controllo
## e i pezzi presenti. Cliccabile (per la selezione guidata) e bersaglio del drag-and-drop.

signal space_clicked(space_id: String)
signal piece_dropped(from_id: String, to_id: String, faction: String, type: String)

var space_id: String
var space_def: SpaceDef

var _name_label: Label
var _info_label: Label
var _pieces_box: VBoxContainer
var _highlight := false


func setup(sd: SpaceDef) -> void:
	space_id = sd.id
	space_def = sd
	custom_minimum_size = Vector2(150, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 1)
	add_child(vb)

	_name_label = Label.new()
	_name_label.text = sd.name
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_name_label)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 10)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info_label)

	_pieces_box = VBoxContainer.new()
	_pieces_box.add_theme_constant_override("separation", 0)
	vb.add_child(_pieces_box)


func refresh(state: GameState) -> void:
	var st: SpaceState = state.space_state(space_id)
	# Info: tipo/terreno + Pop/Econ, Supporto, Controllo
	var bits: Array = []
	if space_def.has_population():
		bits.append("Pop %d" % space_def.pop)
		bits.append(_support_text(st.support))
	elif space_def.is_economic():
		bits.append("Econ %d" % space_def.econ)
	if st.control != "":
		bits.append("▣ %s" % _short(st.control))
	if st.marker("terror") > 0:
		bits.append("T%d" % st.marker("terror"))
	if st.marker("sabotage") > 0:
		bits.append("SAB")
	_info_label.text = " · ".join(bits)

	# Pezzi per Fazione (token trascinabili)
	for c in _pieces_box.get_children():
		c.queue_free()
	for fid in ["government", "m26", "directorio", "syndicate"]:
		for group in _piece_groups(st, fid):
			var tok := PieceToken.new()
			_pieces_box.add_child(tok)
			tok.setup(space_id, fid, group.type, group.state,
				"%s %s×%d" % [_short(fid), group.label, group.count])

	# Colore di sfondo secondo il terreno/tipo
	_apply_style()


## Restituisce i gruppi di pezzi di una Fazione: [{type,state,count,label}].
func _piece_groups(st: SpaceState, fid: String) -> Array:
	var groups: Array = []
	var defs := [
		["troops", "", "T"], ["police", "", "P"], ["base", "", "B"],
		["guerrilla", "underground", "g"], ["guerrilla", "active", "G"],
		["casino", "open", "Ca"], ["casino", "closed", "Cx"],
	]
	for d in defs:
		var n := st.count(fid, d[0], d[1] if d[1] != "" else null)
		if n > 0:
			groups.append({"type": d[0], "state": d[1], "count": n, "label": d[2]})
	return groups


func _support_text(s: int) -> String:
	match s:
		2: return "Sup++"
		1: return "Sup+"
		0: return "Neu"
		-1: return "Opp-"
		-2: return "Opp--"
		_: return ""


func _short(fid: String) -> String:
	match fid:
		"government": return "Gov"
		"m26": return "M26"
		"directorio": return "DR"
		"syndicate": return "Syn"
		_: return fid


func set_highlight(on: bool) -> void:
	_highlight = on
	_apply_style()


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	var bg := Color("2b2b2b")
	match space_def.terrain:
		"forest": bg = Color("1f3a24")
		"grassland": bg = Color("33401f")
		"mountain": bg = Color("3a2f24")
	if space_def.type == CoinEnums.SpaceType.CITY:
		bg = Color("2a3550")
	elif space_def.is_economic():
		bg = Color("3a2f3a")
	sb.bg_color = bg
	sb.set_border_width_all(2 if _highlight else 1)
	sb.border_color = Color("f1c40f") if _highlight else Color("555555")
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)


# --- Interazione ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("space_clicked", space_id)


# Drag-and-drop: si trascina un descrittore di pezzo verso un altro SpaceView.
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "piece"


func _drop_data(_pos: Vector2, data: Variant) -> void:
	emit_signal("piece_dropped", data["from"], space_id, data["faction"], data["type"])
