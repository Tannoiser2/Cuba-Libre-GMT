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
var _log: RichTextLabel
var _instr: Label
var _turn_banner: Label
var _btn_end: Button
var _btn_pass: Button
var _btn_bot: Button
var _btn_ev_u: Button
var _btn_ev_s: Button

# Stato del flusso azione
var _mode := "idle"                   # idle | select_spaces | moves
var _limited := false                 # turno limitato a 1 spazio, niente Att.Speciale
var _op_btns: HBoxContainer
var _sa_btns: HBoxContainer

const PIECE_NAMES := {
	"troops": "Truppa", "police": "Polizia", "guerrilla": "Guerriglia",
	"base": "Base", "casino": "Casinò",
}
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
var _pending_sa := ""                  # Att.Speciale in attesa di bersaglio
var _sa_from := ""                     # origine (per Trasporto/Muscle)
var _resume_mode := "idle"             # modalità Operazione da riprendere dopo l'Att.Speciale
var _sa_valid: Array = []              # spazi bersaglio validi per l'Att.Speciale corrente


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	GameController.state_changed.connect(_refresh)
	GameController.action_logged.connect(_on_log)
	GameController.bot_decision.connect(_on_bot_decision)
	get_viewport().size_changed.connect(_layout_board)
	_rebuild_action_buttons(_cur_faction)
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


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(7)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 11.0
	s.content_margin_right = 11.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	# Aspetto da vero bottone: box arrotondato con bordo e stati hover/pressed.
	b.add_theme_stylebox_override("normal", _btn_style(Color("2b3442"), Color("4a5666")))
	b.add_theme_stylebox_override("hover", _btn_style(Color("3a4759"), Color("6f8197")))
	b.add_theme_stylebox_override("pressed", _btn_style(Color("1d242e"), Color("4a5666")))
	b.add_theme_stylebox_override("disabled", _btn_style(Color("222831"), Color("333b46")))
	b.add_theme_color_override("font_color", Color("e6edf3"))
	b.add_theme_color_override("font_hover_color", Color("ffffff"))
	b.add_theme_color_override("font_disabled_color", Color("5b6571"))
	b.add_theme_font_size_override("font_size", 13)
	return b


## Gruppo verticale: etichetta centrata sopra, contenuto (tasti) sotto.
func _labeled_group(title: String, content: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color("9fb3c8"))
	l.add_theme_font_size_override("font_size", 11)
	v.add_child(l)
	v.add_child(content)
	return v


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

	# --- Riga 1: AZIONI DI TURNO (tasti: Operazioni, Att.Speciali, Evento, Passa) ---
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 5)
	row1.add_theme_constant_override("v_separation", 3)
	bar.add_child(row1)

	# Gruppo Operazione (tasti operazioni + Esegui)
	_op_btns = HBoxContainer.new()
	_op_btns.add_theme_constant_override("separation", 3)
	var op_box := HBoxContainer.new()
	op_box.add_theme_constant_override("separation", 3)
	op_box.add_child(_op_btns)
	op_box.add_child(_mk_btn("Esegui", _on_execute))
	row1.add_child(_labeled_group("Operazione", op_box))

	row1.add_child(VSeparator.new())
	# Gruppo Attività Speciale
	_sa_btns = HBoxContainer.new()
	_sa_btns.add_theme_constant_override("separation", 3)
	row1.add_child(_labeled_group("Attività Speciale", _sa_btns))

	row1.add_child(VSeparator.new())
	# Gruppo Evento
	var ev_box := HBoxContainer.new()
	ev_box.add_theme_constant_override("separation", 3)
	_btn_ev_u = _mk_btn("▸ chiaro", func(): _on_event("unshaded"))
	ev_box.add_child(_btn_ev_u)
	_btn_ev_s = _mk_btn("▸ ombr.", func(): _on_event("shaded"))
	ev_box.add_child(_btn_ev_s)
	row1.add_child(_labeled_group("Evento", ev_box))

	row1.add_child(VSeparator.new())
	# Gruppo Turno
	var turn_box := HBoxContainer.new()
	turn_box.add_theme_constant_override("separation", 3)
	_btn_end = _mk_btn("✓ Concludi", func(): _on_execute_and_end())
	_btn_end.add_theme_color_override("font_color", Color("a3e635"))
	turn_box.add_child(_btn_end)
	_btn_pass = _mk_btn("Passa", func(): GameController.seq_pass())
	turn_box.add_child(_btn_pass)
	turn_box.add_child(_mk_btn("Annulla", _on_cancel))
	row1.add_child(_labeled_group("Turno", turn_box))

	# --- Riga 2: PARTITA / VISTA ---
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 5)
	row2.add_theme_constant_override("v_separation", 3)
	bar.add_child(row2)

	_btn_bot = _mk_btn("🤖 Gioca la fazione di turno", func(): GameController.bot_act_pending())
	row2.add_child(_btn_bot)
	row2.add_child(_mk_btn("Tutti i Bot (questa carta)", _on_all_bots))
	row2.add_child(_mk_btn("Auto: tutta la partita", func(): GameController.run_full_game_paced()))
	row2.add_child(_mk_btn("Nuova Partita", func(): GameController.new_game()))
	row2.add_child(VSeparator.new())
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

	var log_title := Label.new()
	log_title.text = "Log"
	vb.add_child(log_title)

	# Log con altezza fissa, sempre visibile e scrollabile; righe "▶ logica" espandibili.
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.scroll_active = true
	_log.custom_minimum_size = Vector2(340, 260)
	_log.meta_clicked.connect(_on_log_meta)
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
	# Stato pulsanti contestuale
	_set_btn(_btn_end, turn_active)
	_set_btn(_btn_pass, turn_active)
	_set_btn(_btn_bot, turn_active)
	var legal: Array = st.get("legal", [])
	var event_ok := turn_active and (legal.has(4))  # EVENT
	_set_btn(_btn_ev_u, event_ok)
	_set_btn(_btn_ev_s, event_ok)
	var lim := GameController.seq_is_limited_only()
	for b in _op_btns.get_children():
		b.disabled = not turn_active
	for b in _sa_btns.get_children():
		b.disabled = not turn_active or lim

	if not turn_active:
		_turn_banner.add_theme_color_override("font_color", Color("ffffff"))
		if GameController.game_over:
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
	if _mode == "sa_point" or _mode == "sa_move":
		step = "Att.Speciale %s: clicca lo spazio bersaglio" % SA_NAMES.get(_pending_sa, _pending_sa)
	elif _mode == "idle":
		var acts: Array = []
		for a in legal:
			acts.append(ACTION_NAMES.get(int(a), str(a)))
		step = "scegli un'Operazione (tasti), oppure: %s" % ", ".join(acts)
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
	_cur_faction = fid
	_rebuild_action_buttons(fid)
	_clear_pending()


## Ricrea i tasti delle Operazioni e Attività Speciali per la Fazione data.
func _rebuild_action_buttons(fid: String) -> void:
	for c in _op_btns.get_children():
		c.queue_free()
	for op in GameController.game_def.faction(fid).operations:
		_op_btns.add_child(_mk_btn(OP_NAMES.get(op, op), _start_op.bind(op)))
	for c in _sa_btns.get_children():
		c.queue_free()
	for sa in GameController.game_def.faction(fid).special_activities:
		_sa_btns.add_child(_mk_btn(SA_NAMES.get(sa, sa), _do_special.bind(sa)))


func _refresh_side() -> void:
	var s: GameState = GameController.state
	var cc: int = s.current_card
	_card_img.texture = CLAssets.card(cc) if cc >= 0 else null
	var nc: int = GameController.next_card()
	_next_card_img.texture = CLAssets.card(nc) if nc >= 0 else null
	_card_label.text = GameController.current_card_text()


var _log_entries: Array = []


func _on_log(text: String, faction: String = "") -> void:
	_log_entries.append({"t": text, "f": faction, "tr": []})
	_render_log()


func _on_bot_decision(text: String, faction: String, trace: Array) -> void:
	_log_entries.append({"t": text, "f": faction, "tr": trace})
	_render_log()


func _fmt_log_line(text: String, faction: String) -> String:
	if faction != "":
		var hex := GameController.faction_color(faction).to_html(false)
		var txt := "000000" if faction == "directorio" else "ffffff"
		return "[bgcolor=#%s] [color=#%s] %s [/color] [/bgcolor]" % [hex, txt, text]
	return text


func _render_log() -> void:
	if _log_entries.size() > 300:
		_log_entries = _log_entries.slice(_log_entries.size() - 300)
	var s := ""
	for i in range(_log_entries.size()):
		var e: Dictionary = _log_entries[i]
		s += _fmt_log_line(String(e["t"]), String(e["f"]))
		if e["tr"].size() > 0:
			var exp: bool = e.get("exp", false)
			s += "  [url=%d][font_size=11][color=#7fb0ff]%s[/color][/font_size][/url]\n" % [i, ("▼ logica" if exp else "▶ logica")]
			if exp:
				for tl in e["tr"]:
					s += "      [font_size=11][i][color=#9fb3c8]%s[/color][/i][/font_size]\n" % String(tl)
		else:
			s += "\n"
	_log.text = s
	_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))


func _on_log_meta(meta: Variant) -> void:
	var i := int(meta)
	if i >= 0 and i < _log_entries.size():
		_log_entries[i]["exp"] = not bool(_log_entries[i].get("exp", false))
		_render_log()


# ---------------------------------------------------------------------------
# Flusso azione guidato
# ---------------------------------------------------------------------------

## Avvia l'Operazione scelta (tasto): evidenzia gli spazi e imposta il flusso.
func _start_op(op_id: String) -> void:
	_cur_action = op_id
	_selected.clear()
	_pending_moves.clear()
	_limited = GameController.seq_is_limited_only()
	_mode = OP_KIND.get(op_id, "space_list")
	_clear_highlights()
	for sid in _valid_spaces(_cur_faction, op_id):
		_space_views[sid].set_highlight(true)
	var lim := " (Op Limitata: 1 spazio, niente Att.Speciale)" if _limited else ""
	if _mode == "moves":
		_instr.text = "%s%s: trascina i pezzi, poi '✓ Concludi turno'" % [OP_NAMES.get(op_id, op_id), lim]
	else:
		_instr.text = "%s%s: clicca gli spazi, poi '✓ Concludi turno'" % [OP_NAMES.get(op_id, op_id), lim]
	_refresh_turn_banner()


func _on_space_clicked(sid: String) -> void:
	# Bersaglio Attività Speciale
	if _mode == "sa_point":
		if not _sa_valid.has(sid):
			_instr.text = "%s: spazio non valido, scegline uno evidenziato" % SA_NAMES.get(_pending_sa, _pending_sa)
			return
		_run_sa(_pending_sa, sid)
		_end_sa()
		return
	if _mode == "sa_move":
		if _sa_from == "":
			if not _sa_valid.has(sid):
				_instr.text = "Origine non valida: scegline una evidenziata"
				return
			_sa_from = sid
			# Mostra solo le destinazioni valide per questa origine.
			_sa_valid = _sa_valid_dests(_pending_sa, sid)
			_clear_highlights()
			for d in _sa_valid:
				_space_views[d].set_highlight(true)
			if _sa_valid.is_empty():
				_instr.text = "Nessuna destinazione valida da %s — Annulla per cambiare" % GameController.game_def.space(sid).name
			else:
				_instr.text = "Origine: %s — clicca una DESTINAZIONE evidenziata" % GameController.game_def.space(sid).name
		else:
			if not _sa_valid.has(sid):
				_instr.text = "Destinazione non valida: scegline una evidenziata"
				return
			_run_sa_move(_pending_sa, _sa_from, sid)
			_end_sa()
		return
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
		_instr.text = "⚠ Per spostare i pezzi scegli prima un'operazione di movimento (Marcia / Perlustrazione / Guarnigione / Trasporto)"
		return
	if from_id == to_id:
		return
	_pending_moves.append({"from": from_id, "to": to_id, "count": 1, "type": type})
	# Feedback: lampeggia origine (blu) e destinazione (verde).
	if _space_views.has(from_id):
		_space_views[from_id].flash(Color(0.35, 0.6, 1.0))
	if _space_views.has(to_id):
		_space_views[to_id].flash(Color(0.4, 1.0, 0.5))
	var pn: String = PIECE_NAMES.get(type, type)
	var fn: String = GameController.game_def.space(from_id).name
	var tn: String = GameController.game_def.space(to_id).name
	_instr.text = "✓ In coda (%d): 1 %s da %s → %s — poi 'Esegui'" % [_pending_moves.size(), pn, fn, tn]
	_refresh_turn_banner()


func _on_execute() -> void:
	if _cur_action == "":
		return
	var params := _build_params()
	GameController.run_operation(_cur_action, params)
	_clear_pending()


## Esegue l'Attività Speciale (tasto): evidenzia SOLO gli spazi dove ha davvero effetto.
func _do_special(sa: String) -> void:
	if _limited:
		_instr.text = "Operazione Limitata: niente Attività Speciale"
		return
	var sa_name: String = SA_NAMES.get(sa, sa)
	# Avvia la selezione del BERSAGLIO dell'Attività Speciale (prima/durante/dopo l'Operazione).
	var resume := _mode if _mode in ["space_list", "select_spaces", "moves"] else "idle"
	if sa == "transport" or sa == "muscle":
		var origins := _sa_valid_origins(sa)
		if origins.is_empty():
			_instr.text = "%s: nessuna origine valida al momento" % sa_name
			return
		_resume_mode = resume
		_pending_sa = sa
		_sa_from = ""
		_sa_valid = origins
		_clear_highlights()
		for s in origins:
			_space_views[s].set_highlight(true)
		_mode = "sa_move"
		_instr.text = "%s: clicca un'ORIGINE evidenziata, poi la destinazione" % sa_name
	else:
		var valid := _sa_valid_spaces(sa)
		if valid.is_empty():
			_instr.text = "%s: nessuno spazio valido al momento" % sa_name
			return
		_resume_mode = resume
		_pending_sa = sa
		_sa_from = ""
		_sa_valid = valid
		_clear_highlights()
		for s in valid:
			_space_views[s].set_highlight(true)
		_mode = "sa_point"
		_instr.text = "%s: clicca uno spazio bersaglio evidenziato" % sa_name
	_refresh_turn_banner()


## sa_id effettivo (Imboscata dipende dalla Fazione attiva).
func _sa_target_id(sa: String) -> String:
	if sa == "ambush":
		return "ambush_m26" if _cur_faction == "m26" else "ambush_dr"
	return sa


## Parametri per un'Att.Speciale a bersaglio singolo su `space`.
func _sa_params(sa: String, space: String) -> Dictionary:
	match sa:
		"profit": return {"mode": "cash", "spaces": [space]}
		"reprisal": return {"space": space, "move": {}}
		"kidnap": return {"space": space, "target": "government"}
		_: return {"space": space, "faction": _cur_faction}


## Spazi dove l'Att.Speciale a bersaglio singolo ha davvero effetto (simulazione su copia).
func _sa_valid_spaces(sa: String) -> Array:
	var out: Array = []
	var sid_id := _sa_target_id(sa)
	for s in _space_views.keys():
		if GameController.can_special(sid_id, _sa_params(sa, s)):
			out.append(s)
	return out


## Origini valide per Trasporto/Muscle (devono avere i pezzi da spostare).
func _sa_valid_origins(sa: String) -> Array:
	var out: Array = []
	var st_all: GameState = GameController.state
	for sid in _space_views.keys():
		var sd: SpaceDef = GameController.game_def.space(sid)
		var st: SpaceState = st_all.space_state(sid)
		if sa == "transport":
			var from_ok := (sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0)
			if from_ok and st.count("government", "troops") > 0:
				out.append(sid)
		elif sa == "muscle":
			if st.count("government", "police") > 0 or st.count("government", "troops") > 0:
				out.append(sid)
	return out


## Destinazioni valide per Trasporto/Muscle data l'origine scelta.
func _sa_valid_dests(sa: String, from_id: String) -> Array:
	var out: Array = []
	var st_all: GameState = GameController.state
	var from_st: SpaceState = st_all.space_state(from_id)
	for sid in _space_views.keys():
		if sid == from_id:
			continue
		var sd: SpaceDef = GameController.game_def.space(sid)
		var st: SpaceState = st_all.space_state(sid)
		if sa == "transport":
			out.append(sid)   # qualsiasi spazio
		elif sa == "muscle":
			var dest_ok := sd.is_economic() or st.count("syndicate", "casino", "open") > 0
			if not dest_ok:
				continue
			var needed := "police" if sd.type == CoinEnums.SpaceType.CITY else "troops"
			if from_st.count("government", needed) > 0:
				out.append(sid)
	return out


## Esegue l'Att.Speciale su uno spazio (specials a bersaglio singolo).
func _run_sa(sa: String, space: String) -> void:
	GameController.run_special(_sa_target_id(sa), _sa_params(sa, space))


## Esegue Trasporto/Muscle come spostamento origine→destinazione.
func _run_sa_move(sa: String, from_id: String, to_id: String) -> void:
	var p := {"from": from_id, "to": to_id, "count": 2}
	if sa == "muscle":
		var dest: SpaceDef = GameController.game_def.space(to_id)
		p["type"] = "police" if dest.type == CoinEnums.SpaceType.CITY else "troops"
	GameController.run_special(sa, p)


func _end_sa() -> void:
	_pending_sa = ""
	_sa_from = ""
	_sa_valid = []
	_clear_highlights()
	# Se l'Operazione era in corso, riprendila (Att.Speciale fatta DURANTE l'operazione).
	if _resume_mode != "idle" and _cur_action != "":
		_mode = _resume_mode
		for sid in _valid_spaces(_cur_faction, _cur_action):
			_space_views[sid].set_highlight(true)
		for sid in _selected:
			_space_views[sid].set_highlight(true)
		_instr.text = "Continua l'Operazione (clicca/trascina), poi 'Esegui' o '✓ Concludi turno'"
	else:
		_mode = "idle"
	_resume_mode = "idle"
	_refresh_turn_banner()


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
	_clear_pending()


func _on_all_bots() -> void:
	# Risolve la carta corrente con i bot, una mossa alla volta (con pausa/flash).
	GameController.run_card_paced()


## Pulizia interna della selezione/coda in preparazione (senza undo).
func _clear_pending() -> void:
	_mode = "idle"
	_selected.clear()
	_pending_moves.clear()
	_pending_sa = ""
	_sa_from = ""
	_sa_valid = []
	_clear_highlights()
	_instr.text = ""


## Tasto "Annulla": scarta l'azione in preparazione oppure annulla (undo) l'ultima eseguita.
func _on_cancel() -> void:
	var had_pending := _mode != "idle" or not _selected.is_empty() or not _pending_moves.is_empty() or _pending_sa != ""
	_clear_pending()
	if had_pending:
		_instr.text = "Azione in preparazione annullata"
		return
	if GameController.undo_last():
		_instr.text = "↩ Ultima azione annullata"
	else:
		_instr.text = "Niente da annullare"


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
