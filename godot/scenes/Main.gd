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
var _board: ScrollContainer
var _map_wrap: Control
var _map: TextureRect
var _bar: VBoxContainer
var _side: PanelContainer
var _track_overlay: TrackOverlay
var _card_img: TextureRect
var _next_card_img: TextureRect
var _zoom := 1.0
var _card_label: RichTextLabel
var _faction_label: RichTextLabel
var _track_label: RichTextLabel
var _log: RichTextLabel
var _instr: Label
var _turn_banner: Label
var _btn_end: Button
var _btn_pass: Button
var _btn_bot: Button
var _btn_prop: Button
var _btn_sa: Button
var _btn_ev_u: Button
var _btn_ev_s: Button

# Stato del flusso azione
var _mode := "idle"                   # idle | select_spaces | moves
var _limited := false                 # turno limitato a 1 spazio, niente Att.Speciale
var _faction_select: OptionButton
var _action_select: OptionButton
var _special_select: OptionButton

const SA_NAMES := {
	"transport": "Trasporto", "air_strike": "Attacco Aereo", "reprisal": "Rappresaglia",
	"infiltrate": "Infiltrazione", "ambush": "Imboscata", "kidnap": "Sequestro",
	"subvert": "Sovversione", "assassinate": "Assassinio",
	"profit": "Profitto", "muscle": "Muscle", "bribe": "Corruzione",
}
var _cur_faction := "government"
var _cur_action := ""
var _selected: Array = []
var _pending_moves: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	GameController.state_changed.connect(_refresh)
	GameController.action_logged.connect(_on_log)
	get_viewport().size_changed.connect(_layout_board)
	_on_faction_changed(0)
	_refresh()
	# Il layout va calcolato quando la finestra ha la sua dimensione reale (non a 0).
	_layout_board.call_deferred()


# ---------------------------------------------------------------------------
# Costruzione UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("12161c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Barra azioni in alto (va a capo automaticamente: niente troncamento)
	_bar = _build_action_bar()
	add_child(_bar)
	_bar.resized.connect(_layout_board)

	# Area mappa scrollabile (per lo zoom/pan)
	_board = ScrollContainer.new()
	_board.position = Vector2(8, 96)
	add_child(_board)

	# Wrapper che definisce l'area scrollabile (= mappa * zoom); il nodo mappa viene scalato.
	_map_wrap = Control.new()
	_map_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_map_wrap)

	# Sfondo: immagine reale della mappa
	_map = TextureRect.new()
	_map.texture = CLAssets.map()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.size_flags_horizontal = 0
	_map.size_flags_vertical = 0
	_map_wrap.add_child(_map)

	# Zone poligonali sagomate sui contorni (figlie della mappa).
	var regions: Dictionary = _load_regions()
	for sid in regions.keys():
		if GameController.game_def.space(sid) == null:
			continue
		var sd: SpaceDef = GameController.game_def.space(sid)
		var rv := RegionView.new()
		var r: Dictionary = regions[sid]
		var cbox := Vector2(-1, -1)
		var sbox := Vector2(-1, -1)
		if r.has("cbox"):
			cbox = Vector2(r["cbox"][0], r["cbox"][1])
		if r.has("sbox"):
			sbox = Vector2(r["sbox"][0], r["sbox"][1])
		var circle := Vector3(-1, -1, -1)
		if r.has("circle"):
			circle = Vector3(r["circle"][0], r["circle"][1], r["circle"][2])
		rv.setup(sd, r.get("polygon", []), Vector2(r["anchor"][0], r["anchor"][1]), cbox, sbox, circle)
		rv.space_clicked.connect(_on_space_clicked)
		rv.piece_dropped.connect(_on_piece_dropped)
		_map.add_child(rv)
		_space_views[sid] = rv

	# Overlay dei segnalini sui tracciati (sopra la mappa)
	_track_overlay = TrackOverlay.new()
	_track_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_track_overlay)

	# Pannello laterale (destra)
	_side = _build_side_panel()
	add_child(_side)

	resized.connect(_layout_board)
	_layout_board()


func _load_regions() -> Dictionary:
	var path := "res://games/cuba_libre/data/regions.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("regions", {}) if typeof(data) == TYPE_DICTIONARY else {}


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("9fb3c8"))
	l.add_theme_font_size_override("font_size", 12)
	return l


func _build_action_bar() -> VBoxContainer:
	var bar := VBoxContainer.new()
	bar.position = Vector2(8, 6)
	bar.add_theme_constant_override("separation", 3)

	# --- Banner di turno (in alto, colorato per Fazione) ---
	_turn_banner = Label.new()
	_turn_banner.add_theme_font_size_override("font_size", 18)
	_turn_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_turn_banner)

	# --- Riga 1: AZIONI DI TURNO ---
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 5)
	row1.add_theme_constant_override("v_separation", 3)
	bar.add_child(row1)

	_faction_select = OptionButton.new()
	for f in GameController.game_def.factions:
		_faction_select.add_item(f.name)
		_faction_select.set_item_metadata(_faction_select.item_count - 1, f.id)
	_faction_select.item_selected.connect(_on_faction_changed)
	row1.add_child(_mk_label("Fazione:"))
	row1.add_child(_faction_select)

	_action_select = OptionButton.new()
	_action_select.item_selected.connect(func(_i): _on_start())
	row1.add_child(_mk_label("Operazione:"))
	row1.add_child(_action_select)
	row1.add_child(_mk_btn("Esegui", _on_execute))

	_special_select = OptionButton.new()
	row1.add_child(_mk_label("Att.Spec:"))
	row1.add_child(_special_select)
	_btn_sa = _mk_btn("Aggiungi Att.Speciale", _on_special)
	row1.add_child(_btn_sa)

	_btn_ev_u = _mk_btn("Evento ▸ chiaro", func(): _on_event("unshaded"))
	row1.add_child(_btn_ev_u)
	_btn_ev_s = _mk_btn("Evento ▸ ombr.", func(): _on_event("shaded"))
	row1.add_child(_btn_ev_s)

	row1.add_child(VSeparator.new())
	_btn_end = _mk_btn("✓ Concludi turno", func(): _on_execute_and_end())
	_btn_end.add_theme_color_override("font_color", Color("a3e635"))
	row1.add_child(_btn_end)
	_btn_pass = _mk_btn("Passa", func(): GameController.seq_pass())
	row1.add_child(_btn_pass)
	_btn_bot = _mk_btn("🤖 Gioca la fazione di turno", func(): GameController.bot_act_pending())
	row1.add_child(_btn_bot)
	_btn_prop = _mk_btn("Risolvi Propaganda", func(): GameController.run_propaganda())
	row1.add_child(_btn_prop)
	row1.add_child(_mk_btn("Annulla", _on_cancel))

	# --- Riga 2: STRUMENTI ---
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 5)
	row2.add_theme_constant_override("v_separation", 3)
	bar.add_child(row2)

	row2.add_child(_mk_label("Partita:"))
	row2.add_child(_mk_btn("Avanza carta", func(): GameController.step_card()))
	row2.add_child(_mk_btn("Auto: tutta la partita", func(): GameController.run_full_game_paced()))
	row2.add_child(_mk_btn("Tutti i Bot (questa carta)", _on_all_bots))
	row2.add_child(_mk_btn("Nuova Partita", func(): GameController.new_game()))
	row2.add_child(_mk_label("Velocità:"))
	var spd := OptionButton.new()
	for it in [["Lento", 1.3], ["Medio", 0.7], ["Veloce", 0.3]]:
		spd.add_item(it[0])
		spd.set_item_metadata(spd.item_count - 1, it[1])
	spd.select(1)
	spd.item_selected.connect(func(i): GameController.pace_delay = float(spd.get_item_metadata(i)))
	row2.add_child(spd)
	row2.add_child(VSeparator.new())
	row2.add_child(_mk_label("Vista:"))
	row2.add_child(_mk_btn("Zoom +", func(): _set_zoom(_zoom * 1.25)))
	row2.add_child(_mk_btn("Zoom -", func(): _set_zoom(_zoom / 1.25)))
	row2.add_child(_mk_btn("Adatta", func(): _set_zoom(1.0)))

	# Istruzione di passo (sotto le righe)
	_instr = Label.new()
	_instr.add_theme_color_override("font_color", Color("f1c40f"))
	bar.add_child(_instr)
	return bar


## Esegui l'operazione (se selezionata e non ancora eseguita) e concludi il turno.
func _on_execute_and_end() -> void:
	if _cur_action != "" and _mode != "idle":
		_on_execute()
	GameController.end_turn()


func _build_side_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.clip_contents = true
	# Contenuto scrollabile: niente più nulla che esce dal riquadro.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# Carte: corrente e prossima (Upcoming), affiancate
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 6)
	vb.add_child(cards_row)
	var col_cur := VBoxContainer.new()
	var lbl_cur := Label.new()
	lbl_cur.text = "Corrente"
	lbl_cur.add_theme_color_override("font_color", Color("f1c40f"))
	col_cur.add_child(lbl_cur)
	_card_img = TextureRect.new()
	_card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_card_img.custom_minimum_size = Vector2(150, 200)
	col_cur.add_child(_card_img)
	cards_row.add_child(col_cur)
	var col_next := VBoxContainer.new()
	var lbl_next := Label.new()
	lbl_next.text = "Prossima"
	lbl_next.add_theme_color_override("font_color", Color("9fb3c8"))
	col_next.add_child(lbl_next)
	_next_card_img = TextureRect.new()
	_next_card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_next_card_img.custom_minimum_size = Vector2(150, 200)
	_next_card_img.modulate = Color(1, 1, 1, 0.75)
	col_next.add_child(_next_card_img)
	cards_row.add_child(col_next)

	_card_label = RichTextLabel.new()
	_card_label.bbcode_enabled = true
	_card_label.fit_content = true
	_card_label.add_theme_font_size_override("normal_font_size", 12)
	_card_label.custom_minimum_size = Vector2(330, 48)
	vb.add_child(_card_label)
	vb.add_child(HSeparator.new())

	_faction_label = RichTextLabel.new()
	_faction_label.bbcode_enabled = true
	_faction_label.fit_content = true
	_faction_label.add_theme_font_size_override("normal_font_size", 13)
	_faction_label.custom_minimum_size = Vector2(330, 84)
	vb.add_child(_faction_label)

	vb.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Log"
	vb.add_child(log_title)

	# Log con altezza fissa, sempre visibile e scrollabile.
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.scroll_active = true
	_log.custom_minimum_size = Vector2(340, 260)
	vb.add_child(_log)

	pc.custom_minimum_size = Vector2(380, 0)
	return pc


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.5, 4.0)
	_layout_board()


func _layout_board() -> void:
	if _bar == null or _board == null:
		return
	var side_w := 388.0
	# La barra azioni occupa la larghezza utile e va a capo; il board parte sotto.
	_bar.size.x = maxf(300.0, size.x - 16.0)
	var top: float = _bar.get_combined_minimum_size().y + 16.0
	_board.position = Vector2(8, top)
	_board.size = Vector2(maxf(300.0, size.x - side_w - 16.0), maxf(200.0, size.y - top - 8.0))
	# Pannello laterale a destra, sotto la barra
	_side.position = Vector2(size.x - side_w + 4.0, top)
	_side.size = Vector2(side_w - 8.0, size.y - top - 8.0)
	# Dimensione base della mappa per riempire il viewport, poi moltiplicata per lo zoom
	var aspect := 2040.0 / 2640.0
	var vw := _board.size.x
	var vh := _board.size.y
	var mw0 := vw
	var mh0 := mw0 * aspect
	if mh0 > vh:
		mh0 = vh
		mw0 = mh0 / aspect
	# Dimensione base (zoom=1); lo zoom è applicato come SCALA al nodo mappa, così tutto
	# (mappa, pedine, segnalini) scala in modo uniforme. Il wrapper definisce l'area scrollabile.
	var base := Vector2(mw0, mh0)
	if _map != null:
		_map.custom_minimum_size = base
		_map.size = base
		_map.scale = Vector2(_zoom, _zoom)
	if _map_wrap != null:
		_map_wrap.custom_minimum_size = base * _zoom
		_map_wrap.size = base * _zoom
	for sid in _space_views.keys():
		var rv: RegionView = _space_views[sid]
		rv.position = Vector2.ZERO
		rv.size = base
		rv.relayout()
	if _track_overlay != null:
		_track_overlay.position = Vector2.ZERO
		_track_overlay.size = base
		_track_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Aggiornamento viste
# ---------------------------------------------------------------------------

const ACTION_NAMES := {
	0: "Passa", 1: "Operazione", 2: "Op+Att.Speciale", 3: "Op Limitata", 4: "Evento",
}


var _prev_fp: Dictionary = {}


func _refresh() -> void:
	for sid in _space_views.keys():
		_space_views[sid].refresh(GameController.state)
	if _track_overlay != null:
		_track_overlay.queue_redraw()
	_flash_changes()
	_refresh_turn_banner()
	_refresh_side()


## Lampeggia gli spazi il cui stato è cambiato dall'ultimo aggiornamento (feedback visivo).
func _flash_changes() -> void:
	var s: GameState = GameController.state
	var first := _prev_fp.is_empty()
	for sid in _space_views.keys():
		var fp := _space_fp(s, sid)
		if not first and _prev_fp.get(sid, "") != fp:
			_space_views[sid].flash()
		_prev_fp[sid] = fp


func _space_fp(s: GameState, sid: String) -> String:
	var st: SpaceState = s.space_state(sid)
	var out := "%s,%d,%d,%d" % [st.control, st.support, st.marker("terror"), st.marker("sabotage")]
	for f in ["government", "m26", "directorio", "syndicate"]:
		for t in ["troops", "police", "base", "guerrilla", "casino"]:
			out += "," + str(st.count(f, t))
	return out


## Banner di turno: mostra chi è di turno e le azioni legali; abilita i pulsanti pertinenti.
func _refresh_turn_banner() -> void:
	var st := GameController.seq_status()
	var card: int = GameController.state.current_card
	var turn_active: bool = st.get("active", false) and String(st.get("pending", "")) != ""
	var is_prop := card == 0 and not GameController.game_over
	# Stato pulsanti contestuale
	_set_btn(_btn_end, turn_active)
	_set_btn(_btn_pass, turn_active)
	_set_btn(_btn_bot, turn_active)
	_set_btn(_btn_prop, is_prop)
	var legal: Array = st.get("legal", [])
	var event_ok := turn_active and (legal.has(4))  # EVENT
	_set_btn(_btn_ev_u, event_ok)
	_set_btn(_btn_ev_s, event_ok)
	_set_btn(_btn_sa, turn_active and not GameController.seq_is_limited_only())

	if not turn_active:
		_turn_banner.add_theme_color_override("font_color", Color("ffffff"))
		if is_prop:
			_turn_banner.text = "📣 Carta Propaganda %d/4 — premi 'Risolvi Propaganda'" % (GameController.propaganda_played + 1)
		elif GameController.game_over:
			_turn_banner.text = "🏁 Partita conclusa"
		elif card == -1:
			_turn_banner.text = "Mazzo esaurito"
		else:
			_turn_banner.text = ""
		return
	var pending: String = st["pending"]
	if pending != _cur_faction:
		_select_faction(pending)
	_turn_banner.add_theme_color_override("font_color", GameController.faction_color(pending))
	var slot := "1ª" if st.get("first_slot", true) else "2ª"
	# Guida passo-passo in base allo stato del flusso.
	var step := ""
	if _mode == "idle":
		var acts: Array = []
		for a in legal:
			acts.append(ACTION_NAMES.get(int(a), str(a)))
		step = "scegli un'Operazione (menu), oppure: %s" % ", ".join(acts)
	elif _mode == "moves":
		step = "trascina i pezzi (%d spostamenti) → '✓ Concludi turno'" % _pending_moves.size()
	else:
		step = "clicca gli spazi evidenziati (%d selezionati) → '✓ Concludi turno'" % _selected.size()
	_turn_banner.text = "▶ Tocca a %s (%s Fazione) — %s" % \
		[GameController.faction_name(pending), slot, step]


func _set_btn(b: Button, on: bool) -> void:
	if b != null:
		b.disabled = not on


func _select_faction(fid: String) -> void:
	for i in range(_faction_select.item_count):
		if _faction_select.get_item_metadata(i) == fid:
			_faction_select.select(i)
			_on_faction_changed(i)
			return


func _refresh_side() -> void:
	var s: GameState = GameController.state
	var cc: int = s.current_card
	_card_img.texture = CLAssets.card(cc) if cc >= 0 else null
	var nc: int = GameController.next_card()
	_next_card_img.texture = CLAssets.card(nc) if nc >= 0 else null
	_card_label.text = GameController.current_card_text()
	# Progresso verso la vittoria (info NON ripetuta sulla plancia): valore/soglia per fazione.
	var vic := GameController.victory()
	var txt := "[b]Progresso vittoria[/b]\n"
	for f in GameController.game_def.factions:
		var col := GameController.faction_color(f.id).to_html(false)
		var v: Dictionary = vic[f.id]
		var won := " ✓" if v.get("won", false) else ""
		txt += "[color=#%s]●[/color] %s: %+d%s\n" % [col, f.short_name, int(v.margin), won]
	_faction_label.text = txt


func _on_log(text: String, faction: String = "") -> void:
	if faction != "":
		var hex := GameController.faction_color(faction).to_html(false)
		var txt := "000000" if faction == "directorio" else "ffffff"
		_log.append_text("[bgcolor=#%s] [color=#%s] %s [/color] [/bgcolor]\n" % [hex, txt, text])
	else:
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
	_special_select.clear()
	for sa in GameController.game_def.faction(_cur_faction).special_activities:
		_special_select.add_item(SA_NAMES.get(sa, sa))
		_special_select.set_item_metadata(_special_select.item_count - 1, sa)
	_on_cancel()


func _on_start() -> void:
	if _action_select.item_count == 0:
		return
	_cur_action = _action_select.get_item_metadata(_action_select.selected)
	_selected.clear()
	_pending_moves.clear()
	_limited = GameController.seq_is_limited_only()
	_mode = OP_KIND.get(_cur_action, "space_list")
	_clear_highlights()
	for sid in _valid_spaces(_cur_faction, _cur_action):
		_space_views[sid].set_highlight(true)
	var lim := " (Op Limitata: 1 spazio, niente Att.Speciale)" if _limited else ""
	if _mode == "moves":
		_instr.text = "%s%s: trascina i pezzi, poi '✓ Concludi turno'" % [OP_NAMES.get(_cur_action, _cur_action), lim]
	else:
		_instr.text = "%s%s: clicca gli spazi, poi '✓ Concludi turno'" % [OP_NAMES.get(_cur_action, _cur_action), lim]
	_refresh_turn_banner()


func _on_space_clicked(sid: String) -> void:
	if _mode != "select_spaces" and _mode != "space_list":
		return
	if _selected.has(sid):
		_selected.erase(sid)
	else:
		if _limited and _selected.size() >= 1:
			for prev in _selected:
				_space_views[prev].set_highlight(false)
			_selected.clear()
		_selected.append(sid)
		_space_views[sid].set_highlight(true)
	_instr.text = "Selezionati: %s" % ", ".join(_selected)
	_refresh_turn_banner()


func _on_piece_dropped(from_id: String, to_id: String, faction: String, type: String) -> void:
	if _mode != "moves":
		return
	_pending_moves.append({"from": from_id, "to": to_id, "count": 1, "type": type})
	_instr.text = "%d spostamenti in coda" % _pending_moves.size()
	_refresh_turn_banner()


func _on_execute() -> void:
	if _cur_action == "":
		return
	var params := _build_params()
	GameController.run_operation(_cur_action, params)
	_on_cancel()


## Esegue l'Attività Speciale selezionata, con parametri ricavati dalla selezione/spostamenti.
func _on_special() -> void:
	if _special_select.item_count == 0:
		return
	if _limited:
		_instr.text = "Operazione Limitata: niente Attività Speciale"
		return
	var sa: String = _special_select.get_item_metadata(_special_select.selected)
	var sa_id := sa
	if sa == "ambush":
		sa_id = "ambush_m26" if _cur_faction == "m26" else "ambush_dr"
	GameController.run_special(sa_id, _build_special_params(sa))


func _build_special_params(sa: String) -> Dictionary:
	var first: String = _selected[0] if _selected.size() > 0 else ""
	match sa:
		"transport", "muscle":
			if _pending_moves.size() > 0:
				var m: Dictionary = _pending_moves[0]
				var p := {"from": m["from"], "to": m["to"], "count": int(m["count"])}
				if sa == "muscle":
					var dest: SpaceDef = GameController.game_def.space(m["to"])
					p["type"] = "police" if dest.type == CoinEnums.SpaceType.CITY else "troops"
				return p
			return {}
		"profit":
			return {"mode": "cash", "spaces": _selected}
		"reprisal":
			return {"space": first, "move": {}}
		"kidnap":
			return {"space": first, "target": "government"}
		_:
			return {"space": first, "faction": _cur_faction}


## Gioca l'Evento della carta corrente (lato chiaro/ombreggiato) per la Fazione selezionata.
func _on_event(side: String) -> void:
	var n: int = GameController.state.current_card
	if n <= 0:
		_instr.text = "Nessuna carta Evento corrente"
		return
	var params := {"faction": _cur_faction}
	if _selected.size() > 0:
		params["space"] = _selected[0]
	GameController.run_event(n, side, _cur_faction, params)
	_on_cancel()


func _on_all_bots() -> void:
	# Risolve la carta corrente con i bot, una mossa alla volta (con pausa/flash).
	GameController.run_card_paced()


func _on_cancel() -> void:
	_mode = "idle"
	_selected.clear()
	_pending_moves.clear()
	_clear_highlights()
	_instr.text = ""


func _clear_highlights() -> void:
	for sid in _space_views.keys():
		_space_views[sid].set_highlight(false)


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
