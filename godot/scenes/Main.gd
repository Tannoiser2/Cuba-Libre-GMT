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
var _map_wrap: Control
var _map: TextureRect
var _bar: VBoxContainer
var _side: PanelContainer
var _track_overlay: TrackOverlay
var _card_img: TextureRect
var _next_card_img: TextureRect
var _zoom := 1.0
var _card_label: RichTextLabel
var _vic: RichTextLabel                # pannello Vittoria/Risorse (numerico)
var _confirm_new: ConfirmationDialog   # conferma per "Nuova Partita"
var _log: RichTextLabel
var _instr: Label
var _turn_banner: Label
var _btn_end: Button
var _btn_pass: Button
var _btn_bot: Button
var _btn_auto: Button
var _auto_bot := false                 # se true, i Bot giocano da soli; altrimenti aspettano il consenso
var _role_btns: Dictionary = {}        # fid -> Button (toggle Giocatore/Bot)
var _btn_ev_u: Button
var _btn_ev_s: Button

# Stato del flusso azione
var _mode := "idle"                  # idle | select_spaces | moves
var _op_btns: HBoxContainer
var _sa_btns: HBoxContainer

var _cur_faction := "government"
var _btn_launder: Button              # Riciclaggio (2.3.6)
var _btn_clear: Button                # scarta la selezione in preparazione
var _btn_undo: Button                 # annulla l'ultima azione eseguita
var _preview: TipLabel                # anteprima costo/effetti dell'Operazione in preparazione
var _resume_mode := "idle"            # modalità Operazione da riprendere dopo l'Att.Speciale


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_flow = ActionFlow.new(GameController)
	_sflow = SpecialFlow.new(GameController)
	# Su schermi touch (iPad): canvas logico più piccolo = testi e bersagli ~25% più grandi.
	if DisplayServer.is_touchscreen_available():
		get_window().content_scale_size = Vector2i(1180, 650)
	_build_ui()
	GameController.state_changed.connect(_refresh)
	GameController.action_logged.connect(_on_log)
	GameController.bot_decision.connect(_on_bot_decision)
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

	# Overlay frecce degli spostamenti in coda (anteprima del trascinamento)
	_moves_overlay = MovesOverlay.new()
	_moves_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moves_overlay.z_index = 40
	_map.add_child(_moves_overlay)

	# Layer per le animazioni dei pezzi che si spostano (sopra tutto, non interattivo)
	_anim_layer = Control.new()
	_anim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anim_layer.z_index = 50
	_map.add_child(_anim_layer)
	_avail_box = _load_avail_boxes()

	# Pannello laterale (destra)
	_side = _build_side_panel()
	add_child(_side)

	# Conferma per "Nuova Partita" (evita di azzerare la partita per un click di troppo).
	_confirm_new = ConfirmationDialog.new()
	_confirm_new.title = "Nuova Partita"
	_confirm_new.dialog_text = "Iniziare una nuova partita?\nLa partita in corso andrà persa (l'autosalvataggio resta disponibile)."
	_confirm_new.ok_button_text = "Nuova partita"
	_confirm_new.cancel_button_text = "Annulla"
	_confirm_new.confirmed.connect(_on_new_game)
	add_child(_confirm_new)

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
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	return s


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := TipButton.new()
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
	b.add_theme_font_size_override("font_size", 12)
	# Niente focus persistente: altrimenti Invio/Spazio ri-attivano l'ultimo tasto premuto
	# invece di eseguire le scorciatoie di turno.
	b.focus_mode = Control.FOCUS_NONE
	return b


## Evidenzia un tasto con uno sfondo colorato (per il tasto "Esegui").
func _accent_btn(b: Button, bg: Color, border: Color) -> void:
	b.add_theme_stylebox_override("normal", _btn_style(bg, border))
	b.add_theme_stylebox_override("hover", _btn_style(bg.lightened(0.12), border))
	b.add_theme_stylebox_override("pressed", _btn_style(bg.darkened(0.18), border))
	b.add_theme_color_override("font_color", Color("ffffff"))


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
	var btn_exec := _mk_btn("Esegui", _on_execute)
	btn_exec.tooltip_text = "Applica l'Operazione preparata (Invio)"
	_accent_btn(btn_exec, Color("2e7d46"), Color("57c97e"))   # sfondo verde, risalta
	op_box.add_child(btn_exec)
	# Anteprima: costo in Risorse ed esito previsto, calcolati simulando su una copia.
	_preview = TipLabel.new()
	_preview.add_theme_font_size_override("font_size", 11)
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	op_box.add_child(_preview)
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
	_btn_ev_u = _mk_btn("- chiaro", func(): _on_event("unshaded"))
	ev_box.add_child(_btn_ev_u)
	_btn_ev_s = _mk_btn("- ombr.", func(): _on_event("shaded"))
	ev_box.add_child(_btn_ev_s)
	row1.add_child(_labeled_group("Evento", ev_box))

	row1.add_child(VSeparator.new())
	# Gruppo Turno
	var turn_box := HBoxContainer.new()
	turn_box.add_theme_constant_override("separation", 3)
	_btn_end = _mk_btn("Concludi", func(): _on_execute_and_end())
	_btn_end.tooltip_text = "Esegui (se serve) e chiudi il turno della Fazione (Spazio)"
	_btn_end.add_theme_color_override("font_color", Color("a3e635"))
	turn_box.add_child(_btn_end)
	_btn_pass = _mk_btn("Passa", func(): GameController.seq_pass())
	turn_box.add_child(_btn_pass)
	_btn_launder = _mk_btn("Riciclaggio", _on_launder)
	_btn_launder.tooltip_text = "Rimuovi 1 tuo segnalino Denaro per un'Operazione Limitata extra GRATUITA (non Costruzione). Possibile dopo un'Operazione pagata senza Attività Speciale (max 1 per carta)."
	turn_box.add_child(_btn_launder)
	# Due Annulla distinti: scartare la selezione ≠ disfare un'azione già eseguita.
	_btn_clear = _mk_btn("Annulla sel.", _on_cancel_selection)
	_btn_clear.tooltip_text = "Scarta la selezione/coda in preparazione, senza toccare le azioni già eseguite. (Esc)"
	turn_box.add_child(_btn_clear)
	_btn_undo = _mk_btn("Annulla azione", _on_undo_action)
	turn_box.add_child(_btn_undo)
	row1.add_child(_labeled_group("Turno", turn_box))

	# Gruppo Ruoli (Giocatore/Bot) in griglia 2x2, subito dopo il Turno.
	var roles_grid := GridContainer.new()
	roles_grid.columns = 2
	roles_grid.add_theme_constant_override("h_separation", 3)
	roles_grid.add_theme_constant_override("v_separation", 2)
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var rb := _mk_btn("", _toggle_role.bind(fid))
		rb.add_theme_font_size_override("font_size", 11)
		_role_btns[fid] = rb
		roles_grid.add_child(rb)
	row1.add_child(_labeled_group("Ruoli", roles_grid))
	_update_role_btns()

	# --- Riga 2: PARTITA / VISTA ---
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 5)
	row2.add_theme_constant_override("v_separation", 3)
	bar.add_child(row2)

	_btn_bot = _mk_btn(" Gioca la fazione di turno", func(): GameController.bot_act_pending())
	row2.add_child(_btn_bot)
	_btn_auto = _mk_btn("Auto-Bot: OFF", _toggle_auto_bot)
	row2.add_child(_btn_auto)
	row2.add_child(_mk_btn("Tutti i Bot (questa carta)", _on_all_bots))
	row2.add_child(_mk_btn("Auto: tutta la partita", func(): GameController.run_full_game_paced()))
	# Menu Partita: salvataggio/caricamento e Nuova Partita (con conferma).
	var game_menu := _mk_menu_btn("Partita...")
	game_menu.tooltip_text = "Salva/carica la partita (anche l'autosalvataggio, aggiornato a ogni azione) o iniziane una nuova."
	var gp := game_menu.get_popup()
	gp.add_item("Salva partita", 0)
	gp.add_item("Carica partita", 1)
	gp.add_item("Riprendi autosalvataggio", 2)
	gp.add_separator()
	gp.add_item("Nuova Partita...", 3)
	gp.id_pressed.connect(_on_game_menu)
	row2.add_child(game_menu)
	row2.add_child(VSeparator.new())
	row2.add_child(_mk_label("Velocità:"))
	var spd := OptionButton.new()
	for it in [["Lento", 1.8], ["Medio", 1.1], ["Veloce", 0.7]]:
		spd.add_item(it[0])
		spd.set_item_metadata(spd.item_count - 1, it[1])
	spd.select(1)
	spd.item_selected.connect(func(i): GameController.pace_delay = float(spd.get_item_metadata(i)))
	row2.add_child(spd)
	row2.add_child(VSeparator.new())
	row2.add_child(_mk_label("Vista:"))
	row2.add_child(_mk_btn("Zoom +", func(): _zoom_at(1.25)))
	row2.add_child(_mk_btn("Zoom -", func(): _zoom_at(1.0 / 1.25)))
	row2.add_child(_mk_btn("Adatta", func(): _set_zoom(1.0)))

	# Istruzione di passo (sotto le righe)
	_instr = Label.new()
	_instr.add_theme_color_override("font_color", Color("f1c40f"))
	_instr.add_theme_font_size_override("font_size", 10)
	_instr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Contenitore ad altezza FISSA: così la barra non cambia altezza e la mappa resta
	# sempre adattata. Il testo che non entra si legge per intero nel tooltip (InstrBox).
	var instr_box := InstrBox.new()
	instr_box.custom_minimum_size = Vector2(0, 38)
	instr_box.clip_contents = true
	instr_box.mouse_filter = Control.MOUSE_FILTER_STOP
	instr_box.mouse_entered.connect(func(): instr_box.tooltip_text = _instr.text)
	instr_box.add_child(_instr)
	bar.add_child(instr_box)
	return bar


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
	_set_btn(_btn_undo, false)
	if _preview != null:
		_preview.text = ""
	for b in _op_btns.get_children():
		b.disabled = true
	for b in _sa_btns.get_children():
		b.disabled = true
	_set_btn(_btn_end, stage != "")
	_clear_highlights()
	if stage == "":
		_turn_banner.add_theme_color_override("font_color", Color("ffffff"))
		_turn_banner.text = "» Round di Propaganda in corso..."
		return
	# Spostamento (6.4): si trascinano i cubi; evidenzia gli spazi che DEVONO svuotarsi.
	if stage == "redeploy":
		var must: Array = GameController.propaganda.redeploy_must_leave()
		for sid in must:
			if _space_views.has(sid):
				_space_views[sid].set_highlight(true)
		_turn_banner.add_theme_color_override("font_color", GameController.faction_color("government"))
		var tail := "nessun obbligo: sposta se vuoi, poi 'Concludi'" if must.is_empty() \
			else "le Truppe DEVONO lasciare gli spazi evidenziati (%d)" % must.size()
		_turn_banner.text = "» Propaganda - Spostamento del Governo: trascina Truppe/Polizia - %s" % tail
		return
	for sid in GameController.propaganda.support_action_spaces(stage):
		if _space_views.has(sid):
			_space_views[sid].set_highlight(true)
	_turn_banner.add_theme_color_override("font_color", GameController.faction_color(stage))
	_turn_banner.text = "» Propaganda - %s. %s - poi 'Concludi'" % \
		[GameController.faction_name(stage), PROP_MSG.get(stage, "")]


# Istruzioni dei passi interattivi della Propaganda (fase Supporto).
const PROP_MSG := {
	"government": "Azione Civica: clicca gli spazi evidenziati (4 Risorse: -1 Terrore o +1 Supporto)",
	"m26": "Dimostrazioni: clicca gli spazi evidenziati (1 Risorsa: -1 Terrore o +1 Opposizione)",
	"directorio": "Supporto Espatriati: Riorganizzazione gratuita in 1 spazio evidenziato (+1 Guerriglia)",
}


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
	_make_card_zoomable(_card_img)
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
	_make_card_zoomable(_next_card_img)
	col_next.add_child(_next_card_img)
	cards_row.add_child(col_next)

	_card_label = RichTextLabel.new()
	_card_label.bbcode_enabled = true
	_card_label.fit_content = true
	_card_label.add_theme_font_size_override("normal_font_size", 12)
	_card_label.custom_minimum_size = Vector2(330, 48)
	vb.add_child(_card_label)
	vb.add_child(HSeparator.new())

	# Pannello Vittoria: valore/soglia/margine di ogni Fazione + Risorse, sempre visibile.
	var vic_title := Label.new()
	vic_title.text = "Vittoria"
	vb.add_child(vic_title)
	_vic = RichTextLabel.new()
	_vic.bbcode_enabled = true
	_vic.fit_content = true
	_vic.scroll_active = false
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_vic.add_theme_font_size_override(fs, 11)
	_vic.add_theme_constant_override("line_separation", 3)
	vb.add_child(_vic)
	vb.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Log"
	vb.add_child(log_title)

	# Log con altezza fissa, sempre visibile e scrollabile; righe "[+] logica" espandibili.
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.scroll_active = true
	_log.custom_minimum_size = Vector2(340, 260)
	# Testo del log piccolo (override di tema = affidabile, non dipende dal bbcode).
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_log.add_theme_font_size_override(fs, 11)
	# Spaziatura compatta tra le righe del log.
	_log.add_theme_constant_override("line_separation", 2)
	_log.meta_clicked.connect(_on_log_meta)
	vb.add_child(_log)

	pc.custom_minimum_size = Vector2(380, 0)
	return pc


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
	var map_pt := (Vector2(_board.scroll_horizontal, _board.scroll_vertical) + local) / old_zoom
	_zoom = target
	_layout_board()
	_board.scroll_horizontal = int(map_pt.x * _zoom - local.x)
	_board.scroll_vertical = int(map_pt.y * _zoom - local.y)


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
	if _bar == null or _board == null:
		return
	# Larghezza minima del pannello laterale (log/carte); può crescere oltre.
	var min_side := 360.0
	# La barra azioni occupa la larghezza utile e va a capo; il board parte sotto.
	_bar.size.x = maxf(300.0, size.x - 16.0)
	var top: float = _bar.get_combined_minimum_size().y + 16.0
	var avail_h := maxf(200.0, size.y - top - 8.0)
	# La mappa (landscape) si adatta all'area disponibile lasciando spazio al pannello.
	var aspect := 2040.0 / 2640.0
	var max_map_w := maxf(300.0, size.x - 16.0 - min_side - 8.0)
	var mw0 := max_map_w
	var mh0 := mw0 * aspect
	if mh0 > avail_h:
		mh0 = avail_h
		mw0 = mh0 / aspect
	# Pannello laterale di larghezza comoda (né troppo stretto né esageratamente largo);
	# la mappa e il pannello stanno attaccati e il blocco è centrato, così l'eventuale
	# spazio extra diventa due piccoli margini bilanciati invece di un vuoto tra i due.
	var max_side := 470.0
	var side_w := clampf(size.x - 16.0 - mw0 - 8.0, min_side, max_side)
	var block_w := mw0 + 8.0 + side_w
	var lm := maxf(8.0, (size.x - block_w) * 0.5)
	_board.position = Vector2(lm, top)
	_board.size = Vector2(mw0, avail_h)
	_side.position = Vector2(lm + mw0 + 8.0, top)
	_side.size = Vector2(side_w, avail_h)
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
	if _anim_layer != null:
		_anim_layer.position = Vector2.ZERO
		_anim_layer.size = base
	if _moves_overlay != null:
		_moves_overlay.position = Vector2.ZERO
		_moves_overlay.size = base
		_update_moves_overlay()


# ---------------------------------------------------------------------------
# Aggiornamento viste
# ---------------------------------------------------------------------------

const ACTION_NAMES := {
	0: "Passa", 1: "Operazione", 2: "Op+Att.Speciale", 3: "Op Limitata", 4: "Evento",
}


var _prev_fp: Dictionary = {}
var _anim_layer: Control                  # layer per le animazioni dei pezzi
var _moves_overlay: MovesOverlay          # frecce degli spostamenti in coda
var _prev_pc: Dictionary = {}             # conteggi precedenti "sid|faction|type" -> n
var _avail_box: Dictionary = {}           # faction -> centro (normalizzato) del box Forze Disponibili
const ANIM_SZ := 26.0
const ANIM_DUR := 0.9


func _refresh() -> void:
	_animate_moves()
	for sid in _space_views.keys():
		_space_views[sid].refresh(GameController.state)
	if _track_overlay != null:
		_track_overlay.queue_redraw()
	_flash_changes()
	_refresh_turn_banner()
	_refresh_side()
	if not _role_btns.is_empty():
		_update_role_btns()


## Centri normalizzati dei box "Forze Disponibili" (per animare piazzamenti/rimozioni).
func _load_avail_boxes() -> Dictionary:
	var out: Dictionary = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://games/cuba_libre/data/board_layout.json"))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var box: Dictionary = data.get("box", {})
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var r = box.get("available_%s" % fid, null)
		if r != null:
			out[fid] = Vector2((r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5)
	return out


## Anima i pezzi che si sono spostati dall'ultimo aggiornamento: da zona a zona, e
## da/verso i box Forze Disponibili. Confronta i conteggi per (spazio, fazione, tipo).
func _animate_moves() -> void:
	if _anim_layer == null:
		return
	var s: GameState = GameController.state
	var base: Vector2 = _map.size
	# Nuovi conteggi
	var nc: Dictionary = {}
	for sid in _space_views.keys():
		var st: SpaceState = s.space_state(sid)
		for f in ["government", "m26", "directorio", "syndicate"]:
			for t in ["troops", "police", "base", "guerrilla", "casino"]:
				var n := st.count(f, t)
				if n > 0:
					nc["%s|%s|%s" % [sid, f, t]] = n
	# Primo aggiornamento: memorizza soltanto.
	if _prev_pc.is_empty():
		_prev_pc = nc
		return
	# Raccoglie sorgenti e destinazioni per (fazione, tipo).
	var ghosts: Array = []   # {f,t,from,to}
	for f in ["government", "m26", "directorio", "syndicate"]:
		var bc_norm: Vector2 = _avail_box.get(f, Vector2(0.5, 0.5))
		var box_c := bc_norm * base
		for t in ["troops", "police", "base", "guerrilla", "casino"]:
			var sources: Array = []   # [sid, qty]
			var dests: Array = []
			for sid in _space_views.keys():
				var key := "%s|%s|%s" % [sid, f, t]
				var d: int = int(nc.get(key, 0)) - int(_prev_pc.get(key, 0))
				if d < 0:
					sources.append([sid, -d])
				elif d > 0:
					dests.append([sid, d])
			# Accoppia sorgenti->destinazioni (movimento mappa->mappa); le restanti
			# destinazioni vengono dal box Disponibili, le restanti sorgenti vi tornano.
			var si := 0
			var sleft := 0 if sources.is_empty() else int(sources[0][1])
			for de in dests:
				var dv: RegionView = _space_views[de[0]]
				var dc := dv.center_point()
				for _k in range(int(de[1])):
					var from_pos := box_c
					if si < sources.size():
						var sv: RegionView = _space_views[sources[si][0]]
						from_pos = sv.center_point()
						sleft -= 1
						if sleft <= 0:
							si += 1
							sleft = 0 if si >= sources.size() else int(sources[si][1])
					ghosts.append({"f": f, "t": t, "from": from_pos, "to": dc})
			while si < sources.size():
				var rv: RegionView = _space_views[sources[si][0]]
				var sc := rv.center_point()
				for _k2 in range(sleft):
					ghosts.append({"f": f, "t": t, "from": sc, "to": box_c})
				si += 1
				sleft = 0 if si >= sources.size() else int(sources[si][1])
	_prev_pc = nc
	# Troppi movimenti insieme (nuova partita / Propaganda): salta per non intasare.
	if ghosts.size() > 24:
		return
	for g in ghosts:
		_spawn_ghost(String(g["f"]), String(g["t"]), g["from"], g["to"])


## Anima un pezzo che vola da `from_pos` a `to_pos` con una scia luminosa (effetto cometa):
## una "testa" brillante più alcune copie sfalsate che la inseguono attenuandosi.
func _spawn_ghost(faction: String, type: String, from_pos: Vector2, to_pos: Vector2) -> void:
	var tex := CLAssets.piece(faction, type, "")
	if tex == null:
		return
	var half := Vector2(ANIM_SZ, ANIM_SZ) * 0.5
	var echoes := 4
	for e in range(echoes):
		var g := TextureRect.new()
		g.texture = tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size = Vector2(ANIM_SZ, ANIM_SZ)
		g.pivot_offset = half
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.position = from_pos - half
		var head := e == 0
		# Testa brillante e ingrandita; le copie della scia più piccole e attenuate.
		g.modulate = Color(1.5, 1.5, 1.2, 1.0) if head else Color(1.2, 1.2, 1.1, 0.5 - 0.1 * float(e))
		g.scale = Vector2(1.45, 1.45) if head else Vector2(1.2, 1.2)
		_anim_layer.add_child(g)
		var lead := float(e) * 0.08   # ritardo crescente -> la copia resta "indietro" (scia)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if lead > 0.0:
			tw.tween_interval(lead)
		tw.tween_property(g, "position", to_pos - half, ANIM_DUR)
		tw.parallel().tween_property(g, "scale", Vector2(1, 1), ANIM_DUR)
		tw.parallel().tween_property(g, "modulate:a", 0.0, ANIM_DUR * 0.45).set_delay(ANIM_DUR * 0.55)
		tw.tween_callback(g.queue_free)


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
	_refresh_undo_btn()
	_refresh_preview()
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
		_turn_banner.add_theme_color_override("font_color", Color("ffffff"))
		if GameController.game_over:
			if GameController.winner != "":
				_turn_banner.text = "» Partita conclusa - vince %s" % GameController.faction_name(GameController.winner)
				_turn_banner.add_theme_color_override("font_color", GameController.faction_color(GameController.winner))
			else:
				_turn_banner.text = "=== Partita conclusa"
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
	_turn_banner.text = "> Tocca a %s (%s Fazione) - %s" % \
		[GameController.faction_name(pending), slot, step]


func _set_btn(b: Button, on: bool) -> void:
	if b != null:
		b.disabled = not on


## Tasto Annulla-azione: attivo solo se c'è qualcosa da disfare, e dice cosa.
func _refresh_undo_btn() -> void:
	if _btn_undo == null:
		return
	var n := GameController.undo_depth()
	_set_btn(_btn_undo, n > 0)
	_btn_undo.text = "Annulla azione" if n == 0 else "Annulla azione (%d)" % n
	_btn_undo.tooltip_text = "Disfa l'ultima azione eseguita su questa carta (Ctrl+Z)." if n == 0 \
		else "Disfa: %s  —  %d azioni annullabili (Ctrl+Z)" % [GameController.undo_label(), n]


## Anteprima dell'Operazione in preparazione: costo in Risorse ed effetti previsti,
## calcolati simulando l'azione su una copia dello stato (non tocca la partita).
func _refresh_preview() -> void:
	if _preview == null:
		return
	var sst := GameController.seq_status()
	if _flow.op == "" or _mode not in ["space_list", "select_spaces", "moves"] \
			or String(sst.get("pending", "")) == "":
		_preview.text = ""
		_preview.tooltip_text = ""
		return
	var res: Dictionary = GameController.preview_operation(_flow.op, _flow.build_params())
	if not res.get("ok", false):
		# Errore atteso: si vede PRIMA di premere Esegui.
		_preview.text = "⚠ non eseguibile"
		_preview.add_theme_color_override("font_color", Color("ff9f6b"))
		_preview.tooltip_text = String(res.get("error", ""))
		return
	var cost := int(res.get("cost", 0))
	var free := GameController.free_limop_armed()
	if not bool(res.get("tracks_resources", true)):
		_preview.text = "costo — (NP)"
		_preview.add_theme_color_override("font_color", Color("9fb3c8"))
	elif free or cost == 0:
		_preview.text = "GRATIS" if free else "costo 0"
		_preview.add_theme_color_override("font_color", Color("57c97e"))
	else:
		var have := int(res.get("resources", 0))
		_preview.text = "costo %d / %d" % [cost, have]
		_preview.add_theme_color_override("font_color",
			Color("57c97e") if res.get("affordable", false) else Color("ff6b6b"))
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
	for op in GameController.game_def.faction(fid).operations:
		var ob: Button = _mk_btn(CLNames.op(op), _start_op.bind(op))
		ob.tooltip_text = OP_DESC.get(op, "")
		_op_btns.add_child(ob)
	for c in _sa_btns.get_children():
		c.queue_free()
	for sa in GameController.game_def.faction(fid).special_activities:
		if SpecialFlow.VARIANTS.has(sa):
			# Un solo tasto a tendina che "esplode" le varianti (niente barra che va a capo).
			var mb := _mk_menu_btn("%s..." % CLNames.sa(sa))
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
	b.add_theme_stylebox_override("normal", _btn_style(Color("2b3442"), Color("4a5666")))
	b.add_theme_stylebox_override("hover", _btn_style(Color("3a4759"), Color("6f8197")))
	b.add_theme_stylebox_override("pressed", _btn_style(Color("1d242e"), Color("4a5666")))
	b.add_theme_stylebox_override("disabled", _btn_style(Color("222831"), Color("333b46")))
	b.add_theme_color_override("font_color", Color("e6edf3"))
	b.add_theme_color_override("font_hover_color", Color("ffffff"))
	b.add_theme_color_override("font_disabled_color", Color("5b6571"))
	b.add_theme_font_size_override("font_size", 12)
	return b


func _refresh_side() -> void:
	var s: GameState = GameController.state
	var cc: int = s.current_card
	_card_img.texture = CLAssets.card(cc) if cc >= 0 else null
	var nc: int = GameController.next_card()
	_next_card_img.texture = CLAssets.card(nc) if nc >= 0 else null
	_card_label.text = GameController.current_card_text()
	_refresh_victory()


# Metrica di vittoria di ogni Fazione (nome breve mostrato nel pannello).
const _VIC_LABEL := {
	"government": "Supporto", "m26": "Opp.+Basi",
	"directorio": "Pop.+Basi", "syndicate": "Casinò",
}


## Pannello Vittoria: per ogni Fazione valore/soglia (margine) e Risorse; sotto, Aiuti
## e stato dell'Alleanza USA. I numeri altrimenti si leggono solo dai segnalini sul tracciato.
func _refresh_victory() -> void:
	if _vic == null:
		return
	var vs: Dictionary = GameController.victory()
	var s: GameState = GameController.state
	var txt := ""
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var d: Dictionary = vs.get(fid, {})
		var m := int(d.get("margin", 0))
		var mcol := "57c97e" if m >= 0 else "ff8080"
		var res_txt := str(s.get_resources(fid)) if s.tracks_resources(fid) else "—"
		txt += "%s %s [b]%d[/b]/%d [color=#%s](%+d)[/color] · Risorse %s\n" % [
			_fmt_log_line(_ROLE_SHORT.get(fid, fid), fid), _VIC_LABEL.get(fid, ""),
			int(d.get("value", 0)), int(d.get("threshold", 0)), mcol, m, res_txt]
	var alliance: int = clampi(int(s.tracks.get("us_alliance", 0)), 0, 2)
	txt += "[color=#9fb3c8]Aiuti %d · Alleanza USA: %s[/color]" % [
		int(s.tracks.get("aid", 0)), ["Salda", "Riluttante", "Embargo"][alliance]]
	_vic.text = txt


## Rende cliccabile l'anteprima di una carta: click = ingrandimento a schermo intero.
func _make_card_zoomable(tr: TextureRect) -> void:
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tr.tooltip_text = "Clicca per ingrandire"
	tr.gui_input.connect(_on_card_gui_input.bind(tr))


func _on_card_gui_input(event: InputEvent, tr: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_card_zoom(tr.texture)


## Overlay a schermo intero con la carta ingrandita; un click qualsiasi lo chiude.
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
	_instr.add_theme_color_override("font_color", Color("ff6b6b"))
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func(): _instr.add_theme_color_override("font_color", Color("f1c40f")))


## Menu "Partita...": salvataggio, caricamento, autosalvataggio, nuova partita.
func _on_game_menu(id: int) -> void:
	match id:
		0:
			if GameController.save_game():
				_on_log("Partita salvata", "")
				_instr.text = "Partita salvata"
			else:
				_err("Salvataggio non riuscito")
		1:
			_load_from(GameController.SAVE_PATH, "salvataggio")
		2:
			_load_from(GameController.AUTOSAVE_PATH, "autosalvataggio")
		3:
			_confirm_new.popup_centered()


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
	_prev_pc.clear()
	_prev_fp.clear()
	if GameController.load_game(path):
		_on_log("Partita caricata (%s)" % label, "")
		_instr.text = "Partita caricata (%s)" % label
	else:
		_err("File di %s non valido" % label)


var _log_entries: Array = []


func _on_log(text: String, faction: String = "") -> void:
	_log_entries.append({"t": text, "f": faction, "tr": []})
	_render_log()


func _on_bot_decision(text: String, faction: String, trace: Array) -> void:
	_log_entries.append({"t": text, "f": faction, "tr": trace})
	_render_log()


## Font corsiva sintetica (la font di default non ne ha una): inclina i glifi.
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
	var turn := 0
	for i in range(_log_entries.size()):
		var e: Dictionary = _log_entries[i]
		var txt := String(e["t"])
		# Fine carta = fine di un turno: divisore prominente con il numero del turno.
		if String(e["f"]) == "" and txt.find("Carta conclusa") != -1:
			turn += 1
			s += "[center][b][color=#f1c40f]=====  Fine turno %d  =====[/color][/b][/center]\n" % turn
			continue
		# Banner di fine partita.
		if String(e["f"]) == "" and txt.find("FINE PARTITA") != -1:
			s += "\n[center][b][font_size=16][color=#f1c40f]===  FINE PARTITA  ===[/color][/font_size][/b][/center]\n"
			continue
		s += _fmt_log_line(txt, String(e["f"]))
		if e["tr"].size() > 0:
			var exp: bool = e.get("exp", false)
			s += " [url=%d][font_size=10][color=#7fb0ff]%s[/color][/font_size][/url]\n" % [i, ("[-] logica" if exp else "[+] logica")]
			if exp:
				var depth := 1   # livello base delle sotto-righe sotto una carta
				for tl in e["tr"]:
					var raw := String(tl)
					# Indentazione "originale" (le sotto-priorità hanno spazi iniziali).
					var lead := 0
					while lead < raw.length() and raw[lead] == " ":
						lead += 1
					var line := raw.strip_edges()
					if line == "":
						continue
					var extra := lead / 2
					var lvl := depth
					if line.begins_with("Carta Calixto"):
						depth = 1
						lvl = 0
					elif line.begins_with("-> giro") or line.find("(retro)") != -1:
						lvl = depth
						depth += 1            # le condizioni del retro rientrano di più
					elif line.begins_with("Operazione scelta") or line.begins_with("Attività Speciale") or line.begins_with("Nessuna Operazione"):
						lvl = 0
					var pad := "  ".repeat(lvl + extra)
					s += "  [font_size=9][color=#9fb3c8]%s%s[/color][/font_size]\n" % [pad, line]
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
	_instr.text = "%s%s - %s\n> %s, poi 'Esegui' o 'Concludi turno'" % [CLNames.op(op_id), lim, desc, hint]
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
	_instr.text = "%s - %s\n> %s" % [SpecialFlow.label_of(sa),
		SA_DESC.get(SpecialFlow.base_of(sa), ""), _sflow.message]
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


const _ROLE_SHORT := {"government": "Gov", "m26": "26J", "directorio": "DR", "syndicate": "SYN"}


func _toggle_role(fid: String) -> void:
	GameController.set_role(fid, "bot" if GameController.is_player(fid) else "player")
	_update_role_btns()


func _update_role_btns() -> void:
	for fid in _role_btns:
		var player := GameController.is_player(fid)
		var b: Button = _role_btns[fid]
		b.text = "%s: %s" % [_ROLE_SHORT.get(fid, fid), "Giocatore" if player else "Bot"]
		b.add_theme_color_override("font_color", GameController.faction_color(fid) if player else Color("8aa0b3"))


## Tick automatico: se tocca a una Fazione Bot (e non sto scegliendo nulla), gioca da sola.
func _toggle_auto_bot() -> void:
	_auto_bot = not _auto_bot
	_btn_auto.text = "Auto-Bot: ON" if _auto_bot else "Auto-Bot: OFF"
	_accent_btn(_btn_auto, Color("2e7d46"), Color("57c97e")) if _auto_bot else _mk_btn_restyle(_btn_auto)


## Riporta un tasto allo stile neutro standard.
func _mk_btn_restyle(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_style(Color("2b3442"), Color("4a5666")))
	b.add_theme_stylebox_override("hover", _btn_style(Color("3a4759"), Color("6f8197")))
	b.add_theme_stylebox_override("pressed", _btn_style(Color("1d242e"), Color("4a5666")))
	b.add_theme_color_override("font_color", Color("e6edf3"))


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


## Nuova partita: ripulisce il log e la selezione, poi reinizializza.
func _on_new_game() -> void:
	_clear_pending()
	_log_entries.clear()
	_render_log()
	_zoom = 1.0          # mappa adattata al riquadro
	_layout_board()
	GameController.new_game()


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
	_prev_pc.clear()
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




