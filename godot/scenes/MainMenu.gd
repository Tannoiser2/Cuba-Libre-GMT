extends Control

## Schermata iniziale: scelta dello scenario e dei ruoli, ripresa dell'autosalvataggio
## e (in futuro) partita online. È la scena principale del progetto: la partita vera
## si apre da qui e ci si torna a fine partita.

const GAME_SCENE := "res://scenes/Main.tscn"

var _scenario := "standard"
var _short := false
var _roles := {"government": "player", "m26": "bot", "directorio": "bot", "syndicate": "bot"}
var _role_btns: Dictionary = {}
var _scen_btns: Dictionary = {}
var _btn_short: Button
var _status: Label

# Scenari offerti (lo Schieramento Variabile sorteggia le posizioni entro i vincoli).
const SCENARIOS := [
	{"id": "standard", "label": "Standard",
	 "desc": "Schieramento fisso del regolamento (p.29): la partita di riferimento, uguale ogni volta."},
	{"id": "variable", "label": "Variabile",
	 "desc": "Schieramento Variabile (p.30): Casinò, Guerriglie e forze del Governo piazzati a sorte rispettando i vincoli. Apertura diversa a ogni partita."},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# I ruoli di default sono quelli del controller (solitario: Governo umano).
	for fid in _roles:
		_roles[fid] = String(GameController.roles.get(fid, _roles[fid]))
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CLTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Immagine della mappa come sfondo, molto attenuata: dà identità senza disturbare.
	var art := TextureRect.new()
	art.texture = CLAssets.map()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(1, 1, 1, 0.16)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.07, 0.086, 0.11, 0.93)
	pstyle.set_corner_radius_all(12)
	pstyle.set_border_width_all(1)
	pstyle.border_color = CLTheme.BTN_BORDER
	pstyle.content_margin_left = 34.0
	pstyle.content_margin_right = 34.0
	pstyle.content_margin_top = 24.0
	pstyle.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# --- Testata ---
	var title := Label.new()
	title.text = "CUBA LIBRE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", CLTheme.ACCENT)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "L'insorgenza di Castro a Cuba, 1957-1958 — Serie COIN, Volume II"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", CLTheme.TEXT_DIM)
	vb.add_child(sub)
	vb.add_child(HSeparator.new())

	# --- Scenario ---
	vb.add_child(_section("Scenario"))
	var scen_row := HBoxContainer.new()
	scen_row.add_theme_constant_override("separation", 6)
	scen_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for sc in SCENARIOS:
		var b := _mk_btn(String(sc["label"]), func(): _set_scenario(String(sc["id"])))
		b.tooltip_text = String(sc["desc"])
		b.custom_minimum_size = Vector2(150, 0)
		_scen_btns[String(sc["id"])] = b
		scen_row.add_child(b)
	vb.add_child(scen_row)

	_btn_short = _mk_btn("", _toggle_short)
	_btn_short.tooltip_text = "Partita breve: 8 carte Evento restano fuori dal mazzo (dura circa un quinto in meno)."
	vb.add_child(_btn_short)

	# --- Ruoli ---
	vb.add_child(HSeparator.new())
	vb.add_child(_section("Chi gioca cosa"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var rb := _mk_btn("", _toggle_role.bind(fid))
		rb.custom_minimum_size = Vector2(150, 0)
		rb.tooltip_text = "Clicca per alternare fra Giocatore e Bot (Non-giocatore Calixto)."
		_role_btns[fid] = rb
		grid.add_child(rb)
	vb.add_child(grid)

	# --- Avvio ---
	vb.add_child(HSeparator.new())
	var play := _mk_btn("  Inizia la partita  ", _start_game)
	play.add_theme_font_size_override("font_size", 16)
	CLTheme.accent_button(play, Color("2e7d46"), Color("57c97e"))
	vb.add_child(play)

	var resume := _mk_btn("Riprendi l'ultima partita", _resume)
	resume.disabled = not GameController.has_save(GameController.AUTOSAVE_PATH)
	resume.tooltip_text = "Riapre l'autosalvataggio, aggiornato dopo ogni azione." if not resume.disabled \
		else "Nessun autosalvataggio disponibile."
	vb.add_child(resume)

	var online := _mk_btn("Gioca online — prossimamente", func(): _say("La partita online non è ancora disponibile."))
	online.disabled = true
	online.tooltip_text = "Multigiocatore in rete: previsto, non ancora implementato."
	vb.add_child(online)

	if OS.get_name() != "Web":
		vb.add_child(_mk_btn("Esci", func(): get_tree().quit()))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", CLTheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 32)
	vb.add_child(_status)

	_refresh()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", CLTheme.TEXT_DIM)
	return l


func _mk_btn(text: String, cb: Callable) -> Button:
	var b := TipButton.new()
	b.text = text
	b.pressed.connect(cb)
	CLTheme.style_button(b)
	return b


func _say(text: String) -> void:
	_status.text = text


func _set_scenario(id: String) -> void:
	_scenario = id
	_refresh()


func _toggle_short() -> void:
	_short = not _short
	_refresh()


func _toggle_role(fid: String) -> void:
	_roles[fid] = "bot" if _roles[fid] == "player" else "player"
	_refresh()


func _refresh() -> void:
	for id in _scen_btns:
		var b: Button = _scen_btns[id]
		if id == _scenario:
			CLTheme.accent_button(b, Color("2b4b6f"), Color("6f9ccc"))
		else:
			CLTheme.style_button(b)
	_btn_short.text = "Partita breve: %s" % ("SÌ" if _short else "no")
	for fid in _role_btns:
		var rb: Button = _role_btns[fid]
		var is_player: bool = _roles[fid] == "player"
		rb.text = "%s: %s" % [CLNames.faction_short(fid), "Giocatore" if is_player else "Bot"]
		rb.add_theme_color_override("font_color",
			GameController.faction_color(fid) if is_player else Color("8aa0b3"))
	# Descrizione dello scenario scelto + avviso se non gioca nessun umano.
	var desc := ""
	for sc in SCENARIOS:
		if String(sc["id"]) == _scenario:
			desc = String(sc["desc"])
	var humans := 0
	for fid in _roles:
		if _roles[fid] == "player":
			humans += 1
	if humans == 0:
		desc += "  ·  Nessuna Fazione umana: la partita si giocherà da sola."
	_say(desc)


func _start_game() -> void:
	for fid in _roles:
		GameController.roles[fid] = _roles[fid]
	GameController.new_game(_scenario, _short)
	get_tree().change_scene_to_file(GAME_SCENE)


func _resume() -> void:
	if not GameController.load_game(GameController.AUTOSAVE_PATH):
		_say("Non è stato possibile aprire l'autosalvataggio.")
		return
	get_tree().change_scene_to_file(GAME_SCENE)
