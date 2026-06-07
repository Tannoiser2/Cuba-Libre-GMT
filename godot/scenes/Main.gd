extends Control

## Scena principale: mappa interattiva + pannelli (fazioni, tracciati, log) + barra azioni
## con flusso guidato (selezione spazi / drag-and-drop dei pezzi).

# Centri normalizzati (0..1) degli spazi sull'immagine della mappa reale.
# Stimati dalla mappa; facilmente ritoccabili.
const LAYOUT := {
	"pinar_del_rio": Vector2(0.085, 0.47),
	"ec_pinar_habana": Vector2(0.15, 0.33),
	"havana": Vector2(0.225, 0.30),
	"la_habana": Vector2(0.205, 0.43),
	"matanzas": Vector2(0.305, 0.44),
	"ec_lasvillas_camaguey": Vector2(0.40, 0.40),
	"las_villas": Vector2(0.46, 0.46),
	"camaguey_province": Vector2(0.565, 0.41),
	"camaguey_city": Vector2(0.545, 0.66),
	"oriente": Vector2(0.715, 0.51),
	"ec_oriente_sierra": Vector2(0.77, 0.57),
	"sierra_maestra": Vector2(0.80, 0.61),
	"santiago_de_cuba": Vector2(0.875, 0.74),
}

const OP_NAMES := {
	"train": "Addestramento", "garrison": "Guarnigione", "sweep": "Perlustrazione",
	"assault": "Assalto", "rally": "Riorganizzazione", "march": "Marcia",
	"attack": "Attacco", "terror": "Terrorismo", "build": "Costruzione",
}
# Tipo di flusso per ogni Operazione.
const OP_KIND := {
	"train": "space_list", "assault": "space_list", "rally": "space_list",
	"attack": "space_list", "terror": "space_list", "build": "space_list",
	"sweep": "moves", "garrison": "moves", "march": "moves",
}

var _space_views: Dictionary = {}     # space_id -> SpaceView
var _board: Control
var _map: TextureRect
var _card_label: RichTextLabel
var _faction_label: RichTextLabel
var _track_label: RichTextLabel
var _log: RichTextLabel
var _instr: Label

# Stato del flusso azione
var _mode := "idle"                   # idle | select_spaces | moves
var _faction_select: OptionButton
var _action_select: OptionButton
var _cur_faction := "government"
var _cur_action := ""
var _selected: Array = []
var _pending_moves: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	GameController.state_changed.connect(_refresh)
	GameController.action_logged.connect(_on_log)
	_on_faction_changed(0)
	_refresh()


# ---------------------------------------------------------------------------
# Costruzione UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("12161c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Barra azioni in alto
	var bar := _build_action_bar()
	add_child(bar)

	# Area mappa (sinistra)
	_board = Control.new()
	_board.position = Vector2(8, 52)
	add_child(_board)

	# Sfondo: immagine reale della mappa
	_map = TextureRect.new()
	_map.texture = CLAssets.map()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_board.add_child(_map)

	for sid in LAYOUT.keys():
		var sd: SpaceDef = GameController.game_def.space(sid)
		var sv := SpaceView.new()
		sv.setup(sd)
		sv.space_clicked.connect(_on_space_clicked)
		sv.piece_dropped.connect(_on_piece_dropped)
		_board.add_child(sv)
		_space_views[sid] = sv

	# Pannello laterale (destra)
	var side := _build_side_panel()
	add_child(side)

	resized.connect(_layout_board)
	_layout_board()


func _build_action_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 10)
	bar.add_theme_constant_override("separation", 6)

	_faction_select = OptionButton.new()
	for f in GameController.game_def.factions:
		_faction_select.add_item(f.name)
		_faction_select.set_item_metadata(_faction_select.item_count - 1, f.id)
	_faction_select.item_selected.connect(_on_faction_changed)
	bar.add_child(_faction_select)

	_action_select = OptionButton.new()
	bar.add_child(_action_select)

	var btn_start := Button.new()
	btn_start.text = "Avvia"
	btn_start.pressed.connect(_on_start)
	bar.add_child(btn_start)

	var btn_exec := Button.new()
	btn_exec.text = "Esegui"
	btn_exec.pressed.connect(_on_execute)
	bar.add_child(btn_exec)

	var btn_cancel := Button.new()
	btn_cancel.text = "Annulla"
	btn_cancel.pressed.connect(_on_cancel)
	bar.add_child(btn_cancel)

	var sep := VSeparator.new()
	bar.add_child(sep)

	var btn_step := Button.new()
	btn_step.text = "Avanza carta"
	btn_step.pressed.connect(func(): GameController.step_card())
	bar.add_child(btn_step)

	var btn_auto := Button.new()
	btn_auto.text = "Auto: partita"
	btn_auto.pressed.connect(func(): GameController.run_full_game())
	bar.add_child(btn_auto)

	var btn_bot := Button.new()
	btn_bot.text = "Gioca Bot (fazione sel.)"
	btn_bot.pressed.connect(func(): GameController.run_bot_turn(_cur_faction))
	bar.add_child(btn_bot)

	var btn_bots := Button.new()
	btn_bots.text = "Tutti i Bot"
	btn_bots.pressed.connect(_on_all_bots)
	bar.add_child(btn_bots)

	var btn_prop := Button.new()
	btn_prop.text = "Round Propaganda"
	btn_prop.pressed.connect(func(): GameController.run_propaganda())
	bar.add_child(btn_prop)

	var btn_new := Button.new()
	btn_new.text = "Nuova Partita"
	btn_new.pressed.connect(func(): GameController.new_game())
	bar.add_child(btn_new)

	_instr = Label.new()
	_instr.add_theme_color_override("font_color", Color("f1c40f"))
	bar.add_child(_instr)
	return bar


func _build_side_panel() -> Control:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	var vb := VBoxContainer.new()
	pc.add_child(vb)

	_card_label = RichTextLabel.new()
	_card_label.bbcode_enabled = true
	_card_label.fit_content = true
	_card_label.custom_minimum_size = Vector2(360, 70)
	vb.add_child(_card_label)
	vb.add_child(HSeparator.new())

	_faction_label = RichTextLabel.new()
	_faction_label.bbcode_enabled = true
	_faction_label.fit_content = true
	_faction_label.custom_minimum_size = Vector2(360, 150)
	vb.add_child(_faction_label)

	vb.add_child(HSeparator.new())

	_track_label = RichTextLabel.new()
	_track_label.bbcode_enabled = true
	_track_label.fit_content = true
	_track_label.custom_minimum_size = Vector2(360, 120)
	vb.add_child(_track_label)

	vb.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Log"
	vb.add_child(log_title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(360, 360)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_log)

	pc.custom_minimum_size = Vector2(380, 0)
	return pc


func _layout_board() -> void:
	var side_w := 388.0
	var bw: float = maxf(400.0, size.x - side_w - 16.0)
	var bh: float = maxf(300.0, size.y - 60.0)
	# Dimensiona la mappa mantenendo le proporzioni (2640x2040)
	var aspect := 2040.0 / 2640.0
	var mw := bw
	var mh := mw * aspect
	if mh > bh:
		mh = bh
		mw = mh / aspect
	if _map != null:
		_map.position = Vector2.ZERO
		_map.size = Vector2(mw, mh)
	# Posiziona gli spazi centrati sulle coordinate normalizzate della mappa
	for sid in _space_views.keys():
		var p: Vector2 = LAYOUT[sid]
		var sv: SpaceView = _space_views[sid]
		sv.position = Vector2(p.x * mw - sv.size.x * 0.5, p.y * mh - sv.size.y * 0.5)


# ---------------------------------------------------------------------------
# Aggiornamento viste
# ---------------------------------------------------------------------------

func _refresh() -> void:
	for sid in _space_views.keys():
		_space_views[sid].refresh(GameController.state)
	_refresh_side()


func _refresh_side() -> void:
	var s: GameState = GameController.state
	_card_label.text = GameController.current_card_text()
	var vic := GameController.victory()
	var txt := "[b]Fazioni[/b]\n"
	for f in GameController.game_def.factions:
		var col := GameController.faction_color(f.id).to_html(false)
		var elig := "Disp." if s.eligibility[f.id] == CoinEnums.Eligibility.ELIGIBLE else "Non disp."
		var margin: int = vic[f.id].margin
		txt += "[color=#%s]●[/color] %s — Ris %d · %s · margine %+d\n" % \
			[col, f.short_name, s.get_resources(f.id), elig, margin]
	_faction_label.text = txt

	var alliance: String = ["Solida", "Vacillante", "Embargo"][int(s.tracks.get("us_alliance", 0))]
	_track_label.text = "[b]Tracciati[/b]\n" + \
		"Totale Supporto: %d\nOpp + Basi (M26): %d\nDR Pop + Basi: %d\nCasinò aperti: %d\nAiuti: %d\nAlleanza USA: %s" % [
			s.total_support(),
			GameController.module.opposition_plus_bases(s),
			GameController.module.dr_pop_plus_bases(s),
			GameController.module.open_casinos(s),
			int(s.tracks.get("aid", 0)),
			alliance,
		]


func _on_log(text: String) -> void:
	_log.append_text(text + "\n")


# ---------------------------------------------------------------------------
# Flusso azione guidato
# ---------------------------------------------------------------------------

func _on_faction_changed(idx: int) -> void:
	_cur_faction = _faction_select.get_item_metadata(idx)
	_action_select.clear()
	for op in GameController.game_def.faction(_cur_faction).operations:
		_action_select.add_item(OP_NAMES.get(op, op))
		_action_select.set_item_metadata(_action_select.item_count - 1, op)
	_on_cancel()


func _on_start() -> void:
	if _action_select.item_count == 0:
		return
	_cur_action = _action_select.get_item_metadata(_action_select.selected)
	_selected.clear()
	_pending_moves.clear()
	_mode = OP_KIND.get(_cur_action, "space_list")
	_clear_highlights()
	for sid in _valid_spaces(_cur_faction, _cur_action):
		_space_views[sid].set_highlight(true)
	if _mode == "moves":
		_instr.text = "%s: trascina i pezzi tra gli spazi, poi Esegui" % OP_NAMES.get(_cur_action, _cur_action)
	else:
		_instr.text = "%s: clicca gli spazi evidenziati, poi Esegui" % OP_NAMES.get(_cur_action, _cur_action)


func _on_space_clicked(sid: String) -> void:
	if _mode != "select_spaces" and _mode != "space_list":
		return
	if not _space_views[sid]._highlight and not _selected.has(sid):
		return
	if _selected.has(sid):
		_selected.erase(sid)
		_space_views[sid].set_highlight(true)
	else:
		_selected.append(sid)
		_space_views[sid].modulate = Color(1.3, 1.3, 1.0)
	_instr.text = "Selezionati: %s" % ", ".join(_selected)


func _on_piece_dropped(from_id: String, to_id: String, faction: String, type: String) -> void:
	if _mode != "moves":
		return
	_pending_moves.append({"from": from_id, "to": to_id, "count": 1, "type": type})
	_instr.text = "%d spostamenti in coda" % _pending_moves.size()


func _on_execute() -> void:
	if _cur_action == "":
		return
	var params := _build_params()
	GameController.run_operation(_cur_action, params)
	_on_cancel()


func _on_all_bots() -> void:
	# Esegue il turno di tutte le Fazioni Disponibili nell'ordine predefinito.
	for f in GameController.game_def.factions:
		if GameController.state.eligibility[f.id] == CoinEnums.Eligibility.ELIGIBLE:
			GameController.run_bot_turn(f.id)


func _on_cancel() -> void:
	_mode = "idle"
	_selected.clear()
	_pending_moves.clear()
	_clear_highlights()
	_instr.text = ""


func _clear_highlights() -> void:
	for sid in _space_views.keys():
		_space_views[sid].set_highlight(false)
		_space_views[sid].modulate = Color.WHITE


func _build_params() -> Dictionary:
	match _cur_action:
		"sweep":
			var dests := {}
			for m in _pending_moves:
				dests[m["to"]] = true
			return {"spaces": dests.keys(), "moves": _pending_moves}
		"garrison":
			return {"moves": _pending_moves}
		"march":
			return {"faction": _cur_faction, "moves": _pending_moves}
		"rally":
			return {"faction": _cur_faction, "spaces": _selected}
		"attack", "terror":
			return {"faction": _cur_faction, "spaces": _selected}
		"assault":
			return {"spaces": _selected}
		"build":
			var choices := {}
			for sid in _selected:
				choices[sid] = "new"
			return {"spaces": _selected, "choices": choices}
		"train":
			return {"spaces": _selected}
		_:
			return {"spaces": _selected, "faction": _cur_faction}


# Spazi validi (best-effort per evidenziazione; il motore valida comunque all'esecuzione).
func _valid_spaces(faction: String, op: String) -> Array:
	var s: GameState = GameController.state
	var out: Array = []
	for sid in _space_views.keys():
		var sd: SpaceDef = GameController.game_def.space(sid)
		var st: SpaceState = s.space_state(sid)
		var ok := false
		match op:
			"train":
				ok = sd.has_population()
			"assault", "garrison", "sweep", "march":
				ok = true
			"rally":
				ok = sd.has_population()
				if faction == "m26" and st.support > 0: ok = false
				if faction == "directorio" and abs(st.support) == 2: ok = false
			"attack":
				ok = st.count(faction, "guerrilla") > 0
			"terror":
				ok = st.count(faction, "guerrilla", "underground") > 0
			"build":
				ok = sd.has_population() and (st.control == "government" or st.control == "syndicate")
		if ok:
			out.append(sid)
	return out
