extends Control

## Scena principale: mappa interattiva + pannelli (fazioni, tracciati, log) + barra azioni
## con flusso guidato (selezione spazi / drag-and-drop dei pezzi).

# Cosa permette di fare ogni Operazione (sintesi mostrata nel banner).
const OP_DESC := {
	"train": "Clicca uno spazio per piazzare cubi (riclicca per +1, fino a 4); un altro click cicla a Base (da 2 cubi) o Azione Civica (1 sola Att. speciale per Addestramento).",
	"garrison": "Sposta cubi verso Città/EC (trascina); attiva le Guerriglie negli EC. Clicca un EC per un Assalto gratuito lì.",
	"sweep": "Sposta Truppe negli spazi adiacenti e attiva 1 Guerriglia clandestina nemica per ogni Truppa/Polizia.",
	"assault": "Rimuovi pezzi nemici scoperti (1 per Truppa, o per Polizia in Città): prima le Guerriglie Attive, poi le Basi.",
	"rally": "Clicca uno spazio per piazzare Guerriglie; riclicca per cambiare azione (Base = sostituisci 2 Guerriglie con 1 Base; Clandestine = gira sotto, dove hai una Base).",
	"march": "Sposta Guerriglie/cubi in spazi adiacenti; chi entra dove ci sono nemici o Polizia diventa Attivo.",
	"attack": "Tira per rimuovere pezzi nemici (1 ogni 2 Guerriglie); con l'Imboscata colpisci senza tiro.",
	"terror": "Con una Guerriglia clandestina: poni Terrore e sposta il Supporto verso l'Opposizione (o Sabotaggio su LoC/EC).",
	"build": "Sindacato (5 Risorse/spazio): clicca per un nuovo Casinò chiuso; riclicca per aprirne uno già chiuso, dove possibile.",
}
# Cosa permette di fare ogni Attività Speciale (sintesi mostrata nel banner).
const SA_DESC := {
	"transport": "Sposta fino a 3 Truppe da una Città o da una Base verso un qualsiasi spazio.",
	"air_strike": "Rimuovi 1 Guerriglia Attiva (o, se assente, 1 Base) in una Provincia/EC. Vietato durante l'Embargo.",
	"reprisal": "In uno spazio a Controllo Govt: poni Terrore, riduci l'Opposizione e sposta 1 Guerriglia in uno spazio adiacente.",
	"infiltrate": "Rimpiazza 1 cubo del Governo con una Guerriglia 26J in uno spazio senza Supporto (serve una clandestina 26J lì o adiacente).",
	"ambush": "In uno spazio scelto per l'Attacco: colpisci senza tiro rimuovendo 2 pezzi nemici (anche Basi).",
	"kidnap": "Trasferisci Risorse/Denaro dal Governo al 26J e chiudi 1 Casinò; servono più Guerriglie 26J che Polizia.",
	"subvert": "In una Provincia a Controllo DR: aggiungi Risorse pari alla Popolazione e rendi lo spazio Neutrale.",
	"assassinate": "Rimuovi 1 pezzo nemico (anche una Base) dove le Guerriglie DR superano la Polizia.",
	"profit": "Accumula 1 Denaro in 1-2 spazi con un Casinò aperto.",
	"muscle": "Sposta 1-2 Polizia (verso Città) o Truppe (verso Provincia/EC) in uno spazio con Casinò aperto o EC.",
	"bribe": "Spendi 3 Risorse del Sindacato per rimuovere fino a 2 cubi/Guerriglie nemici (o 1 Base) in uno spazio.",
}

## Pianificazione dell'Operazione in corso (stato + regole, senza dipendenze dalla scena).
var _flow: ActionFlow
## Macchina a stati dell'Attività Speciale in corso (anch'essa senza dipendenze dalla scena).
var _sflow: SpecialFlow
var _space_views: Dictionary = {}     # space_id -> RegionView
var _board: ScrollContainer
var _map_frame: Panel                 # cornice d'ottone attorno alla mappa
var _map_wrap: Control
var _map: TextureRect
var _top: TopBar                      # barra superiore (Fazioni, turno, comandi)
var _strip: BottomStrip               # striscia inferiore (carta, Risorse, Vittoria, registro)
var _panel: PanelContainer            # pannello azione (colonna di destra)
var _log: LogView                     # registro (vive nella striscia inferiore)
var _track_overlay: TrackOverlay
var _zoom := 1.0
var _view_ready := false              # prima inquadratura (isola a tutta larghezza) già fatta
var _confirm_new: ConfirmationDialog   # conferma per "Nuova Partita"
var _confirm_menu: ConfirmationDialog  # conferma per il ritorno al menu iniziale
var _end_dialog: ConfirmationDialog    # riepilogo di fine partita

# Ordine di servizio sopra la mappa: di chi è il turno e cosa fare adesso.
var _banner: PanelContainer
var _turn_banner: Label
var _instr: Label
var _zoom_lbl: Label

# Pannello azione
var _head: PanelContainer
var _head_tok: TextureRect
var _head_name: Label
var _head_sub: Label
var _head_stamp: Label
var _op_desc: Label
var _sel_lbl: Label
var _btn_exec: Button
var _btn_end: Button
var _btn_pass: Button
var _btn_bot: Button
var _auto_bot := false                 # se true, i Bot giocano da soli; altrimenti aspettano il consenso
var _btn_ev_u: Button
var _btn_ev_s: Button

# Stato del flusso azione
var _mode := "idle"                  # idle | select_spaces | moves
var _op_btns: GridContainer
var _op_btn_map: Dictionary = {}     # op_id -> Button (per evidenziare quella scelta)
var _sa_btns: HFlowContainer

var _cur_faction := "government"
var _btn_launder: Button              # Riciclaggio (2.3.6)
var _btn_clear: Button                # scarta la selezione in preparazione
var _preview: TipLabel                # anteprima costo/effetti dell'Operazione in preparazione
var _resume_mode := "idle"            # modalità Operazione da riprendere dopo l'Att.Speciale

const PANEL_W := 352.0
const GAP := 10.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Tema "dossier": vale per tutta la scena e per menu a tendina e finestre di dialogo.
	theme = CLTheme.dark_theme()
	get_window().theme = CLTheme.dark_theme()
	_flow = ActionFlow.new(GameController)
	_sflow = SpecialFlow.new(GameController)
	# Su schermi touch (iPad): canvas logico più piccolo = testi e bersagli ~25% più grandi.
	if DisplayServer.is_touchscreen_available():
		get_window().content_scale_size = Vector2i(1180, 650)
	_build_ui()
	GameController.state_changed.connect(_refresh)
	GameController.action_logged.connect(_log.add_line)
	GameController.bot_decision.connect(_log.add_decision)
	GameController.game_finished.connect(_on_game_finished)
	get_viewport().size_changed.connect(_layout_board)
	_rebuild_action_buttons(_cur_faction)
	# Driver automatico delle Fazioni Bot (gioca da sole al loro turno).
	var bot_timer := Timer.new()
	bot_timer.wait_time = 1.0
	bot_timer.one_shot = false
	add_child(bot_timer)
	bot_timer.timeout.connect(_auto_bot_tick)
	bot_timer.start()
	_refresh()
	# Il layout va calcolato quando la finestra ha la sua dimensione reale (non a 0).
	_layout_board.call_deferred()


# ---------------------------------------------------------------------------
# Costruzione UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = CLTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Barra superiore: emblema, Fazioni, turno, comandi di partita.
	_top = TopBar.new()
	_top.role_toggle_requested.connect(_toggle_role)
	_top.undo_requested.connect(_on_undo_action)
	_top.auto_bot_toggled.connect(_toggle_auto_bot)
	_top.menu_id_pressed.connect(_on_game_menu)
	add_child(_top)

	# Cornice della mappa (ottone) e area scrollabile per zoom/pan.
	_map_frame = Panel.new()
	var fsb := CLTheme.flat(CLTheme.BG)
	fsb.set_border_width_all(2)
	fsb.border_color = Color("8a7340")
	fsb.set_corner_radius_all(4)
	fsb.expand_margin_left = 3
	fsb.expand_margin_right = 3
	fsb.expand_margin_top = 3
	fsb.expand_margin_bottom = 3
	_map_frame.add_theme_stylebox_override("panel", fsb)
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_frame)
	_board = ScrollContainer.new()
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

	# Overlay frecce degli spostamenti in coda (anteprima del trascinamento)
	_moves_overlay = MovesOverlay.new()
	_moves_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moves_overlay.z_index = 40
	_map.add_child(_moves_overlay)

	# Layer per le animazioni dei pezzi che si spostano (sopra tutto, non interattivo)
	_anim_layer = MapAnimator.new()
	_anim_layer.setup(_space_views)   # le viste degli spazi esistono già: ne userà i centri
	_map.add_child(_anim_layer)

	# Sopra la mappa (non scalati): ordine di servizio al centro, zoom a destra.
	_build_map_banner()
	_build_zoom_box()

	# Striscia inferiore: carta, Risorse, Vittoria e registro si aggiornano da soli.
	_strip = BottomStrip.new()
	_strip.card_zoom_requested.connect(_show_card_zoom)
	_log = _strip.log_view
	add_child(_strip)

	# Pannello azione (colonna di destra).
	_panel = _build_action_panel()
	add_child(_panel)

	# Conferma per "Nuova Partita" (evita di azzerare la partita per un click di troppo).
	_confirm_new = ConfirmationDialog.new()
	_confirm_new.title = "Nuova Partita"
	_confirm_new.dialog_text = "Iniziare una nuova partita?\nLa partita in corso andrà persa (l'autosalvataggio resta disponibile)."
	_confirm_new.ok_button_text = "Nuova partita"
	_confirm_new.cancel_button_text = "Annulla"
	_confirm_new.confirmed.connect(_on_new_game)
	add_child(_confirm_new)

	# Ritorno al menu iniziale (la partita resta nell'autosalvataggio).
	_confirm_menu = ConfirmationDialog.new()
	_confirm_menu.title = "Menu iniziale"
	_confirm_menu.dialog_text = "Tornare al menu iniziale?\nLa partita in corso resta nell'autosalvataggio e si può riprendere."
	_confirm_menu.ok_button_text = "Torna al menu"
	_confirm_menu.cancel_button_text = "Resta in partita"
	_confirm_menu.confirmed.connect(_go_to_menu)
	add_child(_confirm_menu)

	# A fine partita: riepilogo e proposta di tornare al menu.
	_end_dialog = ConfirmationDialog.new()
	_end_dialog.title = "Partita conclusa"
	_end_dialog.ok_button_text = "Torna al menu"
	_end_dialog.cancel_button_text = "Resta a guardare"
	_end_dialog.confirmed.connect(_go_to_menu)
	add_child(_end_dialog)

	resized.connect(_layout_board)
	_layout_board()


func _load_regions() -> Dictionary:
	var path := "res://games/cuba_libre/data/regions.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data.get("regions", {}) if typeof(data) == TYPE_DICTIONARY else {}


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := TipButton.new()
	b.text = text
	b.pressed.connect(cb)
	CLTheme.style_button(b)
	return b


## Ordine di servizio sopra la mappa: foglietto con di chi è il turno e il passo da fare.
func _build_map_banner() -> void:
	_banner = InstrBox.new()
	_banner.add_theme_stylebox_override("panel", CLTheme.paper_box(12.0))
	_banner.theme = CLTheme.paper_theme()
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_banner.mouse_entered.connect(func(): _banner.tooltip_text = "%s\n%s" % [_turn_banner.text, _instr.text])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(v)
	_turn_banner = CLTheme.label("", CLTheme.INK, 16, CLTheme.ui_heavy())
	_turn_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_banner.max_lines_visible = 2
	v.add_child(_turn_banner)
	_instr = CLTheme.label("", CLTheme.INK, 13, CLTheme.typewriter())
	_instr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instr.max_lines_visible = 3
	v.add_child(_instr)
	add_child(_banner)


var _map_rect := Rect2()


## Il foglietto cambia altezza col testo: lo si tiene appoggiato al bordo basso della mappa.
func _place_banner() -> void:
	if _banner == null or _map_rect.size.x <= 0.0:
		return
	var bw := clampf(_map_rect.size.x * 0.55, 320.0, 620.0)
	var bh := _banner.get_combined_minimum_size().y
	var target := Rect2(_map_rect.position.x + 10.0, _map_rect.end.y - bh - 10.0, bw, bh)
	if _banner.position != target.position or _banner.size != target.size:
		_banner.position = target.position
		_banner.size = target.size


func _process(_delta: float) -> void:
	_place_banner()


## Comandi di vista sopra la mappa: zoom e inquadratura.
var _zoom_box: PanelContainer


func _build_zoom_box() -> void:
	_zoom_box = PanelContainer.new()
	_zoom_box.add_theme_stylebox_override("panel", CLTheme.dark_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	_zoom_box.add_child(h)
	var minus := _mk_btn("−", func(): _zoom_at(1.0 / 1.25))
	minus.tooltip_text = "Riduci (rotellina o −)"
	minus.custom_minimum_size = Vector2(36, 34)
	h.add_child(minus)
	_zoom_lbl = CLTheme.label("100%", CLTheme.TEXT, 14)
	_zoom_lbl.custom_minimum_size = Vector2(48, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_zoom_lbl)
	var plus := _mk_btn("+", func(): _zoom_at(1.25))
	plus.tooltip_text = "Ingrandisci (rotellina o +)"
	plus.custom_minimum_size = Vector2(36, 34)
	h.add_child(plus)
	var fit := _mk_btn("Isola", _view_island)
	fit.tooltip_text = "Inquadra Cuba a tutta larghezza"
	h.add_child(fit)
	var whole := _mk_btn("Tutta", func(): _set_zoom(1.0))
	whole.tooltip_text = "Mostra tutta la plancia, con tracciati e forze disponibili (0)"
	h.add_child(whole)
	add_child(_zoom_box)


## Pannello azione: i passi del turno in ordine, dal basso il tasto per eseguire.
func _build_action_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = CLTheme.paper_theme()
	var psb := CLTheme.paper_box(0.0)
	pc.add_theme_stylebox_override("panel", psb)
	pc.clip_contents = true
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	pc.add_child(outer)

	# Intestazione nel colore della Fazione di turno.
	_head = PanelContainer.new()
	outer.add_child(_head)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	_head.add_child(hh)
	_head_tok = TextureRect.new()
	_head_tok.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_head_tok.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_head_tok.custom_minimum_size = Vector2(30, 38)
	hh.add_child(_head_tok)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -3)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hv)
	_head_name = CLTheme.label("", Color.WHITE, 25, CLTheme.display())
	_head_name.clip_text = true
	hv.add_child(_head_name)
	_head_sub = CLTheme.label("", Color("f6dcd6"), 14)
	_head_sub.clip_text = true
	hv.add_child(_head_sub)
	_head_stamp = CLTheme.label("", Color.WHITE, 12, CLTheme.typewriter())
	var stamp_sb := StyleBoxFlat.new()
	stamp_sb.bg_color = Color(0, 0, 0, 0)
	stamp_sb.set_border_width_all(2)
	stamp_sb.border_color = Color.WHITE
	stamp_sb.content_margin_left = 6
	stamp_sb.content_margin_right = 6
	stamp_sb.content_margin_top = 1
	stamp_sb.content_margin_bottom = 1
	_head_stamp.add_theme_stylebox_override("normal", stamp_sb)
	_head_stamp.rotation_degrees = -6.0
	_head_stamp.resized.connect(func(): _head_stamp.pivot_offset = _head_stamp.size * 0.5)
	_head_stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(_head_stamp)

	# Corpo: passi numerati, scorrevole se lo schermo è basso (iPad).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(m)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	m.add_child(body)

	body.add_child(CLTheme.section_title("1 · Operazione"))
	_op_btns = GridContainer.new()
	_op_btns.columns = 2
	_op_btns.add_theme_constant_override("h_separation", 6)
	_op_btns.add_theme_constant_override("v_separation", 6)
	body.add_child(_op_btns)
	_op_desc = CLTheme.label("", Color("3b3226"), 12, CLTheme.typewriter())
	_op_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_op_desc.custom_minimum_size = Vector2(0, 46)
	body.add_child(_op_desc)

	body.add_child(CLTheme.section_title("2 · Spazi scelti"))
	var sel_box := PanelContainer.new()
	var ssb := CLTheme.flat(CLTheme.PAPER_DARK, 8)
	ssb.set_corner_radius_all(3)
	sel_box.add_theme_stylebox_override("panel", ssb)
	_sel_lbl = CLTheme.label("", CLTheme.INK, 14)
	_sel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_lbl.max_lines_visible = 3
	sel_box.add_child(_sel_lbl)
	body.add_child(sel_box)

	var sa_title := HBoxContainer.new()
	sa_title.add_child(CLTheme.section_title("3 · Attività speciale"))
	var opt := CLTheme.label(" (facoltativa)", CLTheme.INK_DIM, 13)
	opt.size_flags_vertical = Control.SIZE_SHRINK_END
	sa_title.add_child(opt)
	body.add_child(sa_title)
	_sa_btns = HFlowContainer.new()
	_sa_btns.add_theme_constant_override("h_separation", 6)
	_sa_btns.add_theme_constant_override("v_separation", 6)
	body.add_child(_sa_btns)

	body.add_child(CLTheme.section_title("4 · Oppure l'Evento"))
	var ev_box := GridContainer.new()
	ev_box.columns = 2
	ev_box.add_theme_constant_override("h_separation", 6)
	_btn_ev_u = _mk_btn("Chiaro", func(): _on_event("unshaded"))
	_btn_ev_u.tooltip_text = "Gioca il lato chiaro (non ombreggiato) dell'Evento"
	_btn_ev_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_ev_u.custom_minimum_size = Vector2(0, 38)
	ev_box.add_child(_btn_ev_u)
	_btn_ev_s = _mk_btn("Ombreggiato", func(): _on_event("shaded"))
	_btn_ev_s.tooltip_text = "Gioca il lato ombreggiato dell'Evento"
	_btn_ev_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_ev_s.custom_minimum_size = Vector2(0, 38)
	ev_box.add_child(_btn_ev_s)
	body.add_child(ev_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 4)
	body.add_child(spacer)

	# Anteprima del costo + Riciclaggio.
	var prev_box := PanelContainer.new()
	var pvb := CLTheme.box(Color(0, 0, 0, 0), Color("8a7340"), 1)
	prev_box.add_theme_stylebox_override("panel", pvb)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	prev_box.add_child(prow)
	prow.add_child(CLTheme.label("Anteprima", CLTheme.INK_DIM, 14))
	_preview = TipLabel.new()
	_preview.add_theme_font_override("font", CLTheme.ui_heavy())
	_preview.add_theme_font_size_override("font_size", 15)
	_preview.add_theme_color_override("font_color", CLTheme.INK)
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.clip_text = true
	prow.add_child(_preview)
	_btn_launder = _mk_btn("Riciclaggio", _on_launder)
	_btn_launder.tooltip_text = "Rimuovi 1 tuo segnalino Denaro per un'Operazione Limitata extra GRATUITA (non Costruzione). Possibile dopo un'Operazione pagata senza Attività Speciale (max 1 per carta)."
	prow.add_child(_btn_launder)
	body.add_child(prev_box)

	_btn_exec = _mk_btn("Esegui", _on_execute)
	_btn_exec.tooltip_text = "Applica l'Operazione preparata (Invio)"
	CLTheme.primary_button(_btn_exec)
	_btn_exec.custom_minimum_size = Vector2(0, 52)
	body.add_child(_btn_exec)

	var row_a := GridContainer.new()
	row_a.columns = 2
	row_a.add_theme_constant_override("h_separation", 8)
	row_a.add_theme_constant_override("v_separation", 8)
	body.add_child(row_a)
	_btn_clear = _mk_btn("Annulla selezione", _on_cancel_selection)
	_btn_clear.tooltip_text = "Scarta la selezione/coda in preparazione, senza toccare le azioni già eseguite. (Esc)"
	_btn_end = _mk_btn("Concludi turno", func(): _on_execute_and_end())
	_btn_end.tooltip_text = "Esegui (se serve) e chiudi il turno della Fazione (Spazio)"
	_btn_pass = _mk_btn("Passa", func(): GameController.seq_pass())
	_btn_pass.tooltip_text = "La Fazione passa e guadagna Risorse"
	_btn_bot = _mk_btn("Gioca il Bot", func(): GameController.bot_act_pending())
	_btn_bot.tooltip_text = "Fai decidere al Bot l'azione della Fazione di turno"
	for b in [_btn_clear, _btn_end, _btn_pass, _btn_bot]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 42)
		row_a.add_child(b)
	# "Concludi turno" pieno d'inchiostro: è la seconda azione più usata.
	CLTheme.accent_button(_btn_end, CLTheme.INK, CLTheme.INK)
	_btn_end.add_theme_color_override("font_color", CLTheme.PAPER)
	_btn_end.add_theme_color_override("font_hover_color", Color.WHITE)
	return pc


## Intestazione del pannello: Fazione di turno, posto nella sequenza, Risorse, ruolo.
func _refresh_panel_header(fid: String, sub: String, stamp: String) -> void:
	var col := CLTheme.faction(fid) if fid != "" else CLTheme.INK
	var hsb := CLTheme.flat(col, 0)
	hsb.content_margin_left = 14
	hsb.content_margin_right = 14
	hsb.content_margin_top = 8
	hsb.content_margin_bottom = 8
	hsb.corner_radius_top_left = 3
	hsb.corner_radius_top_right = 3
	_head.add_theme_stylebox_override("panel", hsb)
	var fg := Color("111111") if fid == "directorio" else Color.WHITE
	_head_tok.texture = CLAssets.res_token(fid) if fid != "" else null
	_head_tok.visible = fid != ""
	_head_name.text = GameController.faction_name(fid) if fid != "" else "In attesa"
	_head_name.add_theme_color_override("font_color", fg)
	_head_sub.text = sub
	_head_sub.add_theme_color_override("font_color", Color("3b2f0a") if fid == "directorio" else Color("f6e3df"))
	_head_stamp.text = stamp
	_head_stamp.visible = stamp != ""
	_head_stamp.add_theme_color_override("font_color", fg)
	(_head_stamp.get_theme_stylebox("normal") as StyleBoxFlat).border_color = fg


## Evidenzia il tasto dell'Operazione in preparazione (pieno nel colore della Fazione).
func _mark_op_button() -> void:
	var active: String = _flow.op if _mode != "idle" and _flow.op != "" else ""
	for op in _op_btn_map:
		var b: Button = _op_btn_map[op]
		if op == active and active != "":
			CLTheme.accent_button(b, CLTheme.faction_ink(_cur_faction), CLTheme.faction_ink(_cur_faction))
		else:
			CLTheme.style_button(b)
	_btn_exec.text = "Esegui" if active == "" else "Esegui %s" % CLNames.op(active)


## Elenco degli spazi scelti (o degli spostamenti in coda) nel passo 2.
func _refresh_selection_box() -> void:
	if _sel_lbl == null:
		return
	if _sflow.is_active():
		_sel_lbl.text = "Attività speciale: segui le istruzioni sulla mappa."
		return
	if _flow.op == "" or _mode == "idle":
		_sel_lbl.text = "Scegli prima un'Operazione: gli spazi validi si illuminano sulla mappa."
		return
	if _mode == "moves":
		_sel_lbl.text = "Nessuno spostamento in coda: trascina i pezzi sulla mappa." if _flow.moves.is_empty() \
			else "%d spostamenti in coda." % _flow.moves.size()
		return
	if _flow.selected.is_empty():
		_sel_lbl.text = "Nessuno: clicca uno spazio evidenziato."
		return
	var names: Array = []
	for sid in _flow.selected:
		var sd: SpaceDef = GameController.game_def.space(sid)
		names.append(sd.name if sd != null else sid)
	_sel_lbl.text = "%d · %s" % [names.size(), ", ".join(names)]


## Esegui l'operazione (se selezionata e non ancora eseguita) e concludi il turno.
## Durante la Propaganda interattiva "Concludi" chiude il passo corrente.
func _on_execute_and_end() -> void:
	if GameController.prop_pending:
		var r: Dictionary = GameController.prop_next_stage()
		if not r.get("ok", true):
			# Obbligo 6.4.2 non soddisfatto: indica gli spazi da svuotare.
			_err("✗ %s" % String(r.get("error", "")))
			for sid in r.get("spaces", []):
				if _space_views.has(sid):
					_space_views[sid].flash(Color(1.0, 0.4, 0.4))
		return
	if _flow.op != "" and _mode != "idle":
		if not _on_execute():
			return   # l'esecuzione è fallita: l'errore è mostrato, il turno resta aperto
	GameController.end_turn()


## Banner, evidenziazione e pulsanti durante il Round di Propaganda interattivo.
func _prop_banner(stage: String) -> void:
	_set_btn(_btn_pass, false)
	_set_btn(_btn_bot, false)
	_set_btn(_btn_ev_u, false)
	_set_btn(_btn_ev_s, false)
	_set_btn(_btn_launder, false)
	_set_btn(_btn_clear, false)
	_set_btn(_btn_exec, false)
	_top.set_undo(0, "")
	_sel_lbl.text = "Round di Propaganda: segui le istruzioni sulla mappa."
	_op_desc.text = ""
	if _preview != null:
		_preview.text = ""
	for b in _op_btns.get_children():
		b.disabled = true
	for b in _sa_btns.get_children():
		b.disabled = true
	_set_btn(_btn_end, stage != "")
	_clear_highlights()
	var head_fid := stage if stage in ["government", "m26", "directorio", "syndicate"] else ""
	if stage == "redeploy":
		head_fid = "government"
	_refresh_panel_header(head_fid, "Round di Propaganda", "PROPAGANDA")
	_instr.text = ""
	if stage == "":
		_turn_banner.add_theme_color_override("font_color", CLTheme.INK)
		_turn_banner.text = "» Round di Propaganda in corso..."
		return
	# Spostamento (6.4): si trascinano i cubi; evidenzia gli spazi che DEVONO svuotarsi.
	if stage == "redeploy":
		var must: Array = GameController.propaganda.redeploy_must_leave()
		for sid in must:
			if _space_views.has(sid):
				_space_views[sid].set_highlight(true)
		_turn_banner.add_theme_color_override("font_color", CLTheme.faction_ink("government"))
		var tail := "nessun obbligo: sposta se vuoi, poi 'Concludi turno'" if must.is_empty() \
			else "le Truppe DEVONO lasciare gli spazi evidenziati (%d)" % must.size()
		_turn_banner.text = "» Propaganda - Spostamento del Governo: trascina Truppe/Polizia - %s" % tail
		return
	for sid in GameController.propaganda.support_action_spaces(stage):
		if _space_views.has(sid):
			_space_views[sid].set_highlight(true)
	_turn_banner.add_theme_color_override("font_color", CLTheme.faction_ink(stage))
	_turn_banner.text = "» Propaganda - %s. %s - poi 'Concludi turno'" % \
		[GameController.faction_name(stage), PROP_MSG.get(stage, "")]


# Istruzioni dei passi interattivi della Propaganda (fase Supporto).
const PROP_MSG := {
	"government": "Azione Civica: clicca gli spazi evidenziati (4 Risorse: -1 Terrore o +1 Supporto)",
	"m26": "Dimostrazioni: clicca gli spazi evidenziati (1 Risorsa: -1 Terrore o +1 Opposizione)",
	"directorio": "Supporto Espatriati: Riorganizzazione gratuita in 1 spazio evidenziato (+1 Guerriglia)",
}



func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.5, 4.0)
	_layout_board()


## Zoom mantenendo fermo il punto della mappa sotto il pivot (mouse/pinch); senza
## pivot usa il centro dell'area visibile. Aggiorna lo scroll di conseguenza.
func _zoom_at(factor: float, screen_pos: Vector2 = Vector2(-1, -1)) -> void:
	if _board == null:
		return
	var local := screen_pos - _board.global_position
	if screen_pos.x < 0 or local.x < 0 or local.y < 0 or local.x > _board.size.x or local.y > _board.size.y:
		local = _board.size * 0.5
	var old_zoom := _zoom
	var target := clampf(_zoom * factor, 0.5, 4.0)
	if is_equal_approx(target, old_zoom):
		return
	# Punto della mappa (a zoom 1) attualmente sotto il pivot.
	var map_pt := (Vector2(_board.scroll_horizontal, _board.scroll_vertical) + local - _map.position) / old_zoom
	_zoom = target
	_layout_board()
	var off := _map.position
	_board.scroll_horizontal = int(map_pt.x * _zoom + off.x - local.x)
	_board.scroll_vertical = int(map_pt.y * _zoom + off.y - local.y)


## Scorciatoie da tastiera (desktop): Esc annulla la selezione, Invio esegue,
## Spazio conclude il turno, Ctrl+Z disfa, +/-/0 regolano la vista.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			_on_cancel_selection()
		KEY_ENTER, KEY_KP_ENTER:
			if GameController.prop_pending:
				return
			_on_execute()
		KEY_SPACE:
			_on_execute_and_end()
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				_on_undo_action()
			else:
				return
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			_zoom_at(1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(1.0 / 1.25)
		KEY_0, KEY_KP_0:
			_set_zoom(1.0)
		_:
			return
	get_viewport().set_input_as_handled()


var _touch_pts: Dictionary = {}   # index -> posizione (pinch-zoom a due dita)


## Zoom da input globale: rotellina del mouse (sull'area mappa), gesto magnify
## (trackpad) e pinch a due dita (touch/iPad).
func _input(event: InputEvent) -> void:
	if _board == null:
		return
	var board_rect := Rect2(_board.global_position, _board.size)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and board_rect.has_point(event.position):
			_zoom_at(1.15, event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and board_rect.has_point(event.position):
			_zoom_at(1.0 / 1.15, event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		if board_rect.has_point(event.position):
			_zoom_at(event.factor, event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_pts[event.index] = event.position
		else:
			_touch_pts.erase(event.index)
	elif event is InputEventScreenDrag and _touch_pts.has(event.index):
		if _touch_pts.size() == 2:
			var other := Vector2.ZERO
			for i in _touch_pts:
				if i != event.index:
					other = _touch_pts[i]
			var d_old: float = (_touch_pts[event.index] as Vector2).distance_to(other)
			_touch_pts[event.index] = event.position
			var d_new: float = (event.position as Vector2).distance_to(other)
			if d_old > 8.0 and d_new > 8.0:
				_zoom_at(d_new / d_old, (event.position + other) * 0.5)
				get_viewport().set_input_as_handled()
		else:
			_touch_pts[event.index] = event.position


func _layout_board() -> void:
	if _top == null or _board == null or _strip == null or _panel == null:
		return
	var W := size.x
	var H := size.y
	# Barra in alto a tutta larghezza; sotto: mappa + striscia a sinistra, pannello a destra.
	_top.position = Vector2.ZERO
	_top.size = Vector2(W, TopBar.HEIGHT)
	var top := TopBar.HEIGHT + GAP
	var panel_w := PANEL_W if W >= 1300.0 else 320.0
	var left := 12.0
	var map_w := maxf(300.0, W - left - GAP - panel_w - 12.0)
	var strip_h := BottomStrip.HEIGHT
	var map_h := maxf(200.0, H - top - GAP - strip_h - 12.0)
	_panel.position = Vector2(W - 12.0 - panel_w, top)
	_panel.size = Vector2(panel_w, H - top - 12.0)
	_strip.position = Vector2(left, top + map_h + GAP)
	_strip.size = Vector2(map_w, strip_h)
	_board.position = Vector2(left, top)
	_board.size = Vector2(map_w, map_h)
	_map_frame.position = _board.position
	_map_frame.size = _board.size
	# Sopra la mappa: zoom in alto a destra, ordine di servizio centrato.
	var zb := _zoom_box.get_combined_minimum_size()
	_zoom_box.position = Vector2(left + map_w - zb.x - 10.0, top + 10.0)
	_zoom_box.size = zb
	# In basso a sinistra: lì la plancia ha legenda e sequenza di gioco, l'isola resta libera.
	_map_rect = Rect2(left, top, map_w, map_h)
	_place_banner()
	# Dimensione base (zoom=1) = tutta la plancia contenuta nel riquadro; lo zoom è
	# applicato come SCALA al nodo mappa, così mappa, pedine e segnalini scalano insieme.
	var aspect := 2040.0 / 2640.0
	var mw0 := map_w
	var mh0 := mw0 * aspect
	if mh0 > map_h:
		mh0 = map_h
		mw0 = mh0 / aspect
	var base := Vector2(mw0, mh0)
	# Prima inquadratura: l'isola a tutta larghezza (la plancia intera resta a un tasto).
	if not _view_ready and map_w > 300.0:
		_view_ready = true
		_view_island.call_deferred()
	var scaled := base * _zoom
	if _map != null:
		_map.custom_minimum_size = base
		_map.size = base
		_map.scale = Vector2(_zoom, _zoom)
		# Se la plancia è più piccola del riquadro, resta centrata.
		_map.position = ((_board.size - scaled) * 0.5).max(Vector2.ZERO)
	if _map_wrap != null:
		_map_wrap.custom_minimum_size = scaled.max(_board.size)
		_map_wrap.size = scaled.max(_board.size)
	if _zoom_lbl != null:
		_zoom_lbl.text = "%d%%" % roundi(_zoom * 100.0)
	for sid in _space_views.keys():
		var rv: RegionView = _space_views[sid]
		rv.position = Vector2.ZERO
		rv.size = base
		rv.relayout()
	if _track_overlay != null:
		_track_overlay.position = Vector2.ZERO
		_track_overlay.size = base
		_track_overlay.queue_redraw()
	if _anim_layer != null:
		_anim_layer.position = Vector2.ZERO
		_anim_layer.size = base
	if _moves_overlay != null:
		_moves_overlay.position = Vector2.ZERO
		_moves_overlay.size = base
		_update_moves_overlay()


## Inquadra Cuba: plancia a tutta larghezza, scorsa sull'isola (fascia centrale).
func _view_island() -> void:
	if _board == null or _board.size.x <= 0.0:
		return
	var aspect := 2040.0 / 2640.0
	var mw0 := _board.size.x
	var mh0 := mw0 * aspect
	if mh0 > _board.size.y:
		mh0 = _board.size.y
		mw0 = mh0 / aspect
	# L'isola (con L'Avana e Santiago) occupa circa la fascia 12%–84% dell'altezza
	# della plancia: la si fa entrare tutta, senza superare la larghezza del riquadro.
	_zoom = clampf(minf(_board.size.x / mw0, _board.size.y / (mh0 * 0.72)), 0.5, 4.0)
	_layout_board()
	var h := mh0 * _zoom
	var center := h * 0.48
	await get_tree().process_frame
	_board.scroll_vertical = int(maxf(0.0, center - _board.size.y * 0.5))
	_board.scroll_horizontal = 0


# ---------------------------------------------------------------------------
# Aggiornamento viste
# ---------------------------------------------------------------------------

const ACTION_NAMES := {
	0: "Passa", 1: "Operazione", 2: "Op+Att.Speciale", 3: "Op Limitata", 4: "Evento",
}


var _anim_layer: MapAnimator              # animazioni dei pezzi e lampeggi
var _moves_overlay: MovesOverlay          # frecce degli spostamenti in coda


func _refresh() -> void:
	if _anim_layer != null:
		_anim_layer.update(GameController.state, _map.size)
	for sid in _space_views.keys():
		_space_views[sid].refresh(GameController.state)
	if _track_overlay != null:
		_track_overlay.queue_redraw()
	_refresh_turn_banner()
	_strip.refresh()
	_top.refresh()







func _refresh_turn_banner() -> void:
	# Round di Propaganda interattivo: banner e comandi dedicati.
	var pst: Dictionary = GameController.prop_status()
	if pst.get("active", false):
		_prop_banner(String(pst.get("stage", "")))
		return
	var st := GameController.seq_status()
	var card: int = GameController.state.current_card
	var turn_active: bool = st.get("active", false) and String(st.get("pending", "")) != ""
	# Stato pulsanti contestuale
	_set_btn(_btn_end, turn_active)
	_set_btn(_btn_pass, turn_active)
	_set_btn(_btn_bot, turn_active)
	_set_btn(_btn_launder, turn_active and GameController.can_launder())
	_set_btn(_btn_clear, _mode != "idle" or not _flow.selected.is_empty() or not _flow.moves.is_empty())
	_set_btn(_btn_exec, turn_active and (_sflow.is_active() or (_flow.op != "" and _mode != "idle")))
	_refresh_undo_btn()
	_refresh_preview()
	_refresh_selection_box()
	_mark_op_button()
	var legal: Array = st.get("legal", [])
	var event_ok := turn_active and (legal.has(4))  # EVENT
	_set_btn(_btn_ev_u, event_ok)
	_set_btn(_btn_ev_s, event_ok)
	var lim := GameController.seq_is_limited_only()
	# Momentum "MAP": il Governo può fare l'Att.Speciale anche in Op Limitata.
	var lim_sa_ok := GameController.limited_special_ok(String(st.get("pending", "")))
	for b in _op_btns.get_children():
		b.disabled = not turn_active
	for b in _sa_btns.get_children():
		b.disabled = not turn_active or (lim and not lim_sa_ok)

	if not turn_active:
		_turn_banner.add_theme_color_override("font_color", CLTheme.INK)
		_refresh_panel_header("", "Nessuna Fazione di turno", "")
		if GameController.game_over:
			if GameController.winner != "":
				_turn_banner.text = "» Partita conclusa - vince %s" % GameController.faction_name(GameController.winner)
				_turn_banner.add_theme_color_override("font_color", CLTheme.faction_ink(GameController.winner))
			else:
				_turn_banner.text = "=== Partita conclusa"
		elif card == -1:
			_turn_banner.text = "Mazzo esaurito"
		else:
			_turn_banner.text = ""
		_banner.visible = _turn_banner.text != "" or _instr.text != ""
		return
	var pending: String = st["pending"]
	if pending != _cur_faction:
		_select_faction(pending)
	_turn_banner.add_theme_color_override("font_color", CLTheme.faction_ink(pending))
	var slot := "1ª" if st.get("first_slot", true) else "2ª"
	var s: GameState = GameController.state
	var res_txt := ("Risorse %d" % s.get_resources(pending)) if s.tracks_resources(pending) else "Risorse —"
	var lim_txt := " · solo Op. Limitata" if lim else ""
	_refresh_panel_header(pending, "%s Fazione · %s%s" % [slot, res_txt, lim_txt],
		"IN AZIONE" if GameController.is_player(pending) else "BOT")
	_banner.visible = true
	if _mode == "idle" and not _sflow.is_active():
		_op_desc.text = "Scegli un'Operazione: gli spazi dove è possibile si illuminano sulla mappa." \
			if not lim else "Operazione Limitata: un solo spazio e nessuna Attività speciale."
	# Guida passo-passo in base allo stato del flusso.
	var step := ""
	if _sflow.is_active():
		step = "Att.Speciale %s: %s" % [SpecialFlow.label_of(_sflow.pending), _sflow.message]
	elif _mode == "idle":
		var acts: Array = []
		for a in legal:
			acts.append(ACTION_NAMES.get(int(a), str(a)))
		step = "scegli un'Operazione (tasti), oppure: %s" % ", ".join(acts)
	elif _mode == "moves":
		step = "trascina i pezzi (%d spostamenti) -> 'Concludi turno'" % _flow.moves.size()
	else:
		step = "clicca gli spazi evidenziati (%d selezionati) -> 'Concludi turno'" % _flow.selected.size()
	_turn_banner.text = "Tocca a %s (%s Fazione) — %s" % \
		[GameController.faction_name(pending), slot, step]


func _set_btn(b: Button, on: bool) -> void:
	if b != null:
		b.disabled = not on


## Tasto Annulla (barra superiore): attivo solo se c'è qualcosa da disfare, e dice cosa.
func _refresh_undo_btn() -> void:
	if _top != null:
		_top.set_undo(GameController.undo_depth(), GameController.undo_label())


## Anteprima dell'Operazione in preparazione: costo in Risorse ed effetti previsti,
## calcolati simulando l'azione su una copia dello stato (non tocca la partita).
func _refresh_preview() -> void:
	if _preview == null:
		return
	var sst := GameController.seq_status()
	if _flow.op == "" or _mode not in ["space_list", "select_spaces", "moves"] \
			or String(sst.get("pending", "")) == "":
		_preview.text = "—"
		_preview.add_theme_color_override("font_color", CLTheme.INK_FAINT)
		_preview.tooltip_text = ""
		return
	var res: Dictionary = GameController.preview_operation(_flow.op, _flow.build_params())
	if not res.get("ok", false):
		# Errore atteso: si vede PRIMA di premere Esegui.
		_preview.text = "⚠ non eseguibile"
		_preview.add_theme_color_override("font_color", CLTheme.WARN_INK)
		_preview.tooltip_text = String(res.get("error", ""))
		return
	var cost := int(res.get("cost", 0))
	var free := GameController.free_limop_armed()
	if not bool(res.get("tracks_resources", true)):
		_preview.text = "costo — (NP)"
		_preview.add_theme_color_override("font_color", CLTheme.INK_DIM)
	elif free or cost == 0:
		_preview.text = "GRATIS" if free else "costo 0"
		_preview.add_theme_color_override("font_color", CLTheme.OK_INK)
	else:
		var have := int(res.get("resources", 0))
		_preview.text = "costo %d / %d" % [cost, have]
		_preview.add_theme_color_override("font_color",
			CLTheme.OK_INK if res.get("affordable", false) else CLTheme.ERR_INK)
	# Nel tooltip: cosa succederà (l'Attacco dipende dal tiro, quindi è indicativo).
	var lines: Array = res.get("log", [])
	var tip := "Effetti previsti:\n- " + "\n- ".join(lines) if not lines.is_empty() else "Nessun effetto previsto"
	if _flow.op == "attack":
		tip += "\n\n(L'Attacco dipende dal tiro del dado: anteprima indicativa.)"
	_preview.tooltip_text = tip


func _select_faction(fid: String) -> void:
	_cur_faction = fid
	_rebuild_action_buttons(fid)
	_clear_pending()


## Ricrea i tasti delle Operazioni e Attività Speciali per la Fazione data.
func _rebuild_action_buttons(fid: String) -> void:
	for c in _op_btns.get_children():
		c.queue_free()
	_op_btn_map.clear()
	for op in GameController.game_def.faction(fid).operations:
		var ob: Button = _mk_btn(CLNames.op(op), _start_op.bind(op))
		ob.tooltip_text = OP_DESC.get(op, "")
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.custom_minimum_size = Vector2(0, 44)
		ob.add_theme_font_size_override("font_size", 17)
		_op_btns.add_child(ob)
		_op_btn_map[op] = ob
	for c in _sa_btns.get_children():
		c.queue_free()
	for sa in GameController.game_def.faction(fid).special_activities:
		if SpecialFlow.VARIANTS.has(sa):
			# Un solo tasto a tendina che "esplode" le varianti (niente barra che va a capo).
			var mb := _mk_menu_btn("%s ▾" % CLNames.sa(sa))
			mb.custom_minimum_size = Vector2(0, 36)
			mb.tooltip_text = SA_DESC.get(sa, "")
			var pop := mb.get_popup()
			var ids: Array = []
			for v in SpecialFlow.VARIANTS[sa]:
				pop.add_item(_variant_short(String(v["label"])))
				ids.append(String(v["id"]))
			pop.id_pressed.connect(func(i): _do_special(String(ids[i])))
			_sa_btns.add_child(mb)
		else:
			var sb: Button = _mk_btn(CLNames.sa(sa), _do_special.bind(sa))
			sb.custom_minimum_size = Vector2(0, 36)
			sb.tooltip_text = SA_DESC.get(sa, "")
			_sa_btns.add_child(sb)


## Etichetta breve di una variante: il testo tra parentesi ("Corruzione (cubi)" -> "cubi").
func _variant_short(label: String) -> String:
	var a := label.find("(")
	var b := label.rfind(")")
	return label.substr(a + 1, b - a - 1) if a >= 0 and b > a else label


## Tasto a tendina (MenuButton) con la stessa veste degli altri tasti.
func _mk_menu_btn(text: String) -> MenuButton:
	var b := TipMenuButton.new()
	b.text = text
	b.flat = false
	CLTheme.style_button(b)
	return b








func _show_card_zoom(tex: Texture2D) -> void:
	if tex == null:
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 100
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var big := TextureRect.new()
	big.texture = tex
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.offset_left = 30
	big.offset_top = 30
	big.offset_right = -30
	big.offset_bottom = -30
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(big)
	var hint := Label.new()
	hint.text = "clicca per chiudere"
	hint.add_theme_color_override("font_color", Color("9fb3c8"))
	hint.add_theme_font_size_override("font_size", 11)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -24
	dim.add_child(hint)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			dim.queue_free())
	add_child(dim)


## Messaggio di ERRORE nella riga istruzioni: rosso, poi torna al giallo standard.
func _err(text: String) -> void:
	_instr.text = text
	_banner.visible = true
	_instr.add_theme_color_override("font_color", CLTheme.ERR_INK)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func(): _instr.add_theme_color_override("font_color", CLTheme.INK))


## Menu "Partita...": salvataggio, caricamento, autosalvataggio, nuova partita.
func _on_game_menu(id: int) -> void:
	match id:
		0:
			if GameController.save_game():
				_log.add_line("Partita salvata", "")
				_instr.text = "Partita salvata"
			else:
				_err("Salvataggio non riuscito")
		1:
			_load_from(GameController.SAVE_PATH, "salvataggio")
		2:
			_load_from(GameController.AUTOSAVE_PATH, "autosalvataggio")
		3:
			_confirm_new.popup_centered()
		4:
			_confirm_menu.popup_centered()
		TopBar.MenuId.BOT_TURN:
			GameController.bot_act_pending()
		TopBar.MenuId.ALL_BOTS:
			_on_all_bots()
		TopBar.MenuId.FULL_GAME:
			GameController.run_full_game_paced()
		TopBar.MenuId.SPEED_SLOW:
			GameController.pace_delay = 1.8
		TopBar.MenuId.SPEED_MED:
			GameController.pace_delay = 1.1
		TopBar.MenuId.SPEED_FAST:
			GameController.pace_delay = 0.7


## Riciclaggio (2.3.6): se il Denaro è in un solo spazio agisci subito, altrimenti scegli.
func _on_launder() -> void:
	var spaces: Array = GameController.launder_spaces()
	if spaces.is_empty():
		_err("Riciclaggio: nessun tuo segnalino Denaro sulla mappa")
		return
	if spaces.size() == 1:
		_do_launder(spaces[0])
		return
	_mode = "launder_pick"
	_clear_highlights()
	for sid in spaces:
		_space_views[sid].set_highlight(true)
	_instr.text = "Riciclaggio: clicca lo spazio da cui rimuovere 1 tuo Denaro"


func _do_launder(sid: String) -> void:
	var r: Dictionary = GameController.do_launder(sid)
	if r.get("ok", false):
		_mode = "idle"
		_clear_highlights()
		_instr.text = "Riciclaggio: ora scegli un'Operazione (1 spazio, GRATUITA, non Costruzione), poi 'Esegui'"
	else:
		_err(String(r.get("error", "Riciclaggio non riuscito")))


func _load_from(path: String, label: String) -> void:
	if not GameController.has_save(path):
		_err("Nessun %s trovato" % label)
		return
	_clear_pending()
	# Evita le animazioni di massa al cambio di stato completo.
	if _anim_layer != null:
		_anim_layer.reset()
	if GameController.load_game(path):
		_log.add_line("Partita caricata (%s)" % label, "")
		_instr.text = "Partita caricata (%s)" % label
	else:
		_err("File di %s non valido" % label)









# ---------------------------------------------------------------------------
# Flusso azione guidato
# ---------------------------------------------------------------------------

## Avvia l'Operazione scelta (tasto): evidenzia gli spazi e imposta il flusso.
func _start_op(op_id: String) -> void:
	# LimOp anche quando è armata la LimOp gratuita del Riciclaggio (1 spazio).
	var lim_only: bool = GameController.seq_is_limited_only() or GameController.free_limop_armed()
	if not _flow.start(op_id, _cur_faction, lim_only):
		_err(_flow.error)
		return
	_mode = _flow.kind
	_render_flow()
	var lim := " (Op Limitata: 1 spazio, niente Att.Speciale)" if _flow.limited else ""
	var desc: String = OP_DESC.get(op_id, "")
	var hint := "trascina i pezzi nei loro spazi" if _mode == "moves" else "clicca gli spazi evidenziati"
	_op_desc.text = desc
	_instr.text = "%s%s — %s, poi 'Esegui' o 'Concludi turno'" % [CLNames.op(op_id), lim, hint]
	_refresh_turn_banner()


## Ridisegna ciò che la pianificazione descrive: evidenziazioni e frecce degli spostamenti.
func _render_flow() -> void:
	_clear_highlights()
	for sid in _flow.highlights():
		if _space_views.has(sid):
			_space_views[sid].set_highlight(true)
	_update_moves_overlay()


func _on_space_clicked(sid: String) -> void:
	# Round di Propaganda interattivo: il click applica il passo della fase Supporto.
	if GameController.prop_pending:
		var pr: Dictionary = GameController.prop_click(sid)
		if pr.get("ok", false):
			if _space_views.has(sid):
				_space_views[sid].flash(Color(0.4, 1.0, 0.5))
		else:
			_err(String(pr.get("error", "Azione non valida")))
		return
	# Riciclaggio: scelta dello spazio da cui rimuovere il Denaro.
	if _mode == "launder_pick":
		_do_launder(sid)
		return
	# Attività Speciale in corso: decide SpecialFlow, la scena disegna ed esegue.
	if _sflow.is_active():
		var r: Dictionary = _sflow.click(sid)
		if not r.get("ok", false):
			if String(r.get("error", "")) != "":
				_err(_sflow.error)
			return
		_instr.text = _sflow.message
		if not (r["run"] as Dictionary).is_empty():
			_execute_special(r["run"])
		else:
			_render_special()
			_refresh_turn_banner()
		return
	# Da qui in poi decide la pianificazione (ActionFlow): selezione degli spazi,
	# ciclo delle varianti (cubi/Base/Civica, bersaglio dell'Attacco, ...) e
	# Assalti gratuiti di Guarnigione/Perlustrazione. La scena si limita a disegnare.
	var before: int = _flow.selected.size()
	if not _flow.click(sid):
		if _flow.error != "":
			_err(_flow.error)
		return
	_instr.text = _flow.message
	# Feedback: verde se lo spazio è entrato nel piano, arancio per gli Assalti gratuiti.
	if _flow.op in ["garrison", "sweep"] and _mode == "moves":
		_space_views[sid].flash(Color(1.0, 0.7, 0.3))
	elif _flow.selected.size() != before:
		_space_views[sid].flash(Color(0.4, 1.0, 0.5))
	_render_flow()
	_refresh_turn_banner()



















func _on_piece_dropped(from_id: String, to_id: String, faction: String, type: String) -> void:
	# Spostamento della Propaganda (6.4): i cubi si muovono subito, non in coda.
	if GameController.prop_pending:
		if GameController.prop_stage != "redeploy":
			_err("Questo passo della Propaganda si gioca cliccando gli spazi, non trascinando")
			return
		if faction != "government":
			_err("Nello Spostamento si muovono solo le forze del Governo")
			return
		var rr: Dictionary = GameController.prop_redeploy_move(from_id, to_id, type)
		if rr.get("ok", false):
			_space_views[from_id].flash(Color(0.35, 0.6, 1.0))
			_space_views[to_id].flash(Color(0.4, 1.0, 0.5))
		else:
			_err("✗ %s" % String(rr.get("error", "Spostamento non valido")))
		return
	if _mode != "moves":
		# Momentum "Armored Cars": Truppe trascinabili negli spazi scelti per l'Assalto.
		if _mode == "space_list" and _flow.op == "assault" and type == "troops" \
				and GameController.module.has_momentum(GameController.state, "Armored Cars"):
			if not _flow.queue_assault_move(from_id, to_id):
				_err(_flow.error)
				return
			_instr.text = _flow.message
			_update_moves_overlay()
			return
		_err("! Per spostare i pezzi scegli prima un'operazione di movimento (Marcia / Perlustrazione / Guarnigione / Trasporto)")
		return
	if not _flow.queue_move(from_id, to_id, type):
		if _flow.error != "":
			_err(_flow.error)
		return
	# Feedback: lampeggia origine (blu) e destinazione (verde).
	if _space_views.has(from_id):
		_space_views[from_id].flash(Color(0.35, 0.6, 1.0))
	if _space_views.has(to_id):
		_space_views[to_id].flash(Color(0.4, 1.0, 0.5))
	_instr.text = _flow.message
	_update_moves_overlay()
	_refresh_turn_banner()


## Aggiorna le frecce di anteprima degli spostamenti in coda.
func _update_moves_overlay() -> void:
	if _moves_overlay == null:
		return
	var segs: Array = []
	for m in _flow.moves:
		var fi: String = m["from"]
		var ti: String = m["to"]
		if _space_views.has(fi) and _space_views.has(ti):
			var fv: RegionView = _space_views[fi]
			var tv: RegionView = _space_views[ti]
			segs.append({"from": fv.center_point(), "to": tv.center_point()})
	_moves_overlay.set_segments(segs)


func _on_execute() -> bool:
	# Passi dell'Attività Speciale che si confermano con "Esegui"
	# (numero di cubi del Trasporto/Muscle, Casinò del Profitto).
	if _sflow.is_active():
		var r: Dictionary = _sflow.confirm()
		if not r.get("ok", false):
			if _sflow.error != "":
				_err(_sflow.error)
			return false
		if (r["run"] as Dictionary).is_empty():
			return false
		_execute_special(r["run"])
		return true
	if _flow.op == "":
		return false
	var params := _flow.build_params()
	var res := GameController.run_operation(_flow.op, params)
	if not res.get("ok", false):
		# La selezione resta: si può correggere e ripremere "Esegui", o Annullare.
		_err("✗ %s" % String(res.get("error", "Operazione non eseguibile")))
		return false
	_clear_pending()
	return true


## Esegue l'Attività Speciale (tasto): evidenzia SOLO gli spazi dove ha davvero effetto.
func _do_special(sa: String) -> void:
	# Momentum "MAP": il Governo può accompagnare la LimOp con un'Att.Speciale.
	if _flow.limited and not GameController.limited_special_ok(_cur_faction):
		_err("Operazione Limitata: niente Attività Speciale")
		return
	# L'Att.Speciale può avvenire prima/durante/dopo l'Operazione: ricorda dove riprendere.
	_resume_mode = _mode if _mode in ["space_list", "select_spaces", "moves"] else "idle"
	if not _sflow.start(sa, _cur_faction):
		_err(_sflow.error)
		_resume_mode = "idle"
		return
	_mode = "special"
	_render_special()
	_op_desc.text = "%s: %s" % [SpecialFlow.label_of(sa), SA_DESC.get(SpecialFlow.base_of(sa), "")]
	_instr.text = "%s — %s" % [SpecialFlow.label_of(sa), _sflow.message]
	_refresh_turn_banner()


## Disegna gli spazi cliccabili del passo corrente dell'Attività Speciale.
func _render_special() -> void:
	_clear_highlights()
	for sid in _sflow.highlights():
		if _space_views.has(sid):
			_space_views[sid].set_highlight(true)


## Esegue l'Attività Speciale che il flusso ha preparato, poi chiude il passo.
func _execute_special(run: Dictionary) -> void:
	var res: Dictionary = GameController.run_special(String(run["id"]), run["params"])
	if not res.get("ok", false):
		_err("✗ %s" % String(res.get("error", "Attività non eseguibile")))
	_end_sa()














func _end_sa() -> void:
	_sflow.clear()
	_clear_highlights()
	# Se l'Operazione era in corso, riprendila (Att.Speciale fatta DURANTE l'operazione).
	if _resume_mode != "idle" and _flow.op != "":
		_mode = _resume_mode
		for sid in _flow.valid_spaces(_cur_faction, _flow.op):
			_space_views[sid].set_highlight(true)
		for sid in _flow.selected:
			_space_views[sid].set_highlight(true)
		_instr.text = "Continua l'Operazione (clicca/trascina), poi 'Esegui' o 'Concludi turno'"
	else:
		_mode = "idle"
	_resume_mode = "idle"
	_refresh_turn_banner()


## Gioca l'Evento della carta corrente (lato chiaro/ombreggiato) per la Fazione selezionata.
func _on_event(side: String) -> void:
	var params := {}
	if _flow.selected.size() > 0:
		params["space"] = _flow.selected[0]
	var res := GameController.play_event(side, params)
	_clear_pending()
	if not res.get("ok", false):
		_err("! " + String(res.get("error", "Evento non eseguibile")))
	else:
		_instr.text = "Evento giocato - turno concluso"
	_refresh_turn_banner()


func _on_all_bots() -> void:
	# Risolve la carta corrente con i bot, una mossa alla volta (con pausa/flash).
	GameController.run_card_paced()




func _toggle_role(fid: String) -> void:
	GameController.set_role(fid, "bot" if GameController.is_player(fid) else "player")
	_top.refresh()
	_refresh_turn_banner()


## Auto-Bot: se acceso, le Fazioni Bot giocano da sole quando tocca a loro.
func _toggle_auto_bot() -> void:
	_auto_bot = not _auto_bot
	_top.set_auto_bot(_auto_bot)


func _auto_bot_tick() -> void:
	if not _auto_bot or GameController.game_over or _mode != "idle":
		return
	var s: GameState = GameController.state
	if s == null or s.current_card <= 0:
		return
	var st := GameController.seq_status()
	var pending := String(st.get("pending", ""))
	if pending != "" and bool(st.get("active", false)) and GameController.is_bot(pending):
		GameController.bot_act_pending()


## Torna alla schermata iniziale (l'autosalvataggio conserva la partita).
func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## Fine partita: mostra il risultato e propone il ritorno al menu.
func _on_game_finished(winner: String) -> void:
	var vs: Dictionary = GameController.victory()
	var lines: Array = ["Vince %s." % GameController.faction_name(winner), ""]
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var d: Dictionary = vs.get(fid, {})
		lines.append("%s%s: %d/%d (margine %+d)" % [
			"» " if fid == winner else "   ", GameController.faction_name(fid),
			int(d.get("value", 0)), int(d.get("threshold", 0)), int(d.get("margin", 0))])
	_end_dialog.dialog_text = "\n".join(lines)
	_end_dialog.popup_centered()


## Nuova partita: ripulisce il log e la selezione, poi reinizializza.
func _on_new_game() -> void:
	_clear_pending()
	_log.clear_log()
	_zoom = 1.0          # mappa adattata al riquadro
	_layout_board()
	GameController.new_game(GameController.scenario, GameController.short_game)


## Pulizia interna della selezione/coda in preparazione (senza undo).
func _clear_pending() -> void:
	_mode = "idle"
	_flow.clear()
	_sflow.clear()
	_clear_highlights()
	_update_moves_overlay()
	_instr.text = ""


## "Annulla sel.": scarta soltanto la selezione/coda in preparazione (mai distruttivo).
func _on_cancel_selection() -> void:
	var had_pending := _mode != "idle" or not _flow.selected.is_empty() or not _flow.moves.is_empty() or _sflow.is_active()
	_clear_pending()
	_instr.text = "Selezione annullata" if had_pending else "Niente da annullare in preparazione"
	_refresh_turn_banner()


## "Annulla azione": disfa l'ultima azione già eseguita (ripetibile, fino a 20 livelli).
func _on_undo_action() -> void:
	# L'undo riporta indietro tutta la mappa: niente animazioni di massa.
	if _anim_layer != null:
		_anim_layer.reset()
	if GameController.undo_last():
		_clear_pending()
		var n := GameController.undo_depth()
		_instr.text = "Azione annullata" + ("" if n == 0 else " (%d ancora annullabili)" % n)
	else:
		_err("Nessuna azione da annullare su questa carta")
	_refresh_turn_banner()


func _clear_highlights() -> void:
	for sid in _space_views.keys():
		_space_views[sid].set_highlight(false)




