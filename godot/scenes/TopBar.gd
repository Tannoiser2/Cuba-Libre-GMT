class_name TopBar
extends PanelContainer

## Barra superiore comune ai giochi COIN: emblema e titolo, una tessera per Fazione
## (ordine sulla carta, ruolo Giocatore/Bot, stato, Risorse), turno e comandi di partita.
##
## Non conosce la logica di gioco: legge lo stato dal controller in `refresh()` e
## notifica le richieste con i segnali; la scena decide cosa farne.

signal role_toggle_requested(fid: String)
signal undo_requested
signal auto_bot_toggled
signal bot_turn_requested
signal menu_id_pressed(id: int)

const HEIGHT := 72.0
const FACTIONS := ["government", "m26", "directorio", "syndicate"]
## Nome della metrica di vittoria di ogni Fazione (suggerimento della tessera).
const VIC_LABEL := {
	"government": "Supporto", "m26": "Opposizione + Basi",
	"directorio": "Pop DR + Basi", "syndicate": "Casinò aperti",
}

## Voci del menu di partita (gli id arrivano alla scena con `menu_id_pressed`).
enum MenuId { SAVE, LOAD, AUTOSAVE, NEW_GAME, MAIN_MENU, BOT_TURN, ALL_BOTS, FULL_GAME,
	SPEED_SLOW, SPEED_MED, SPEED_FAST }

var _tiles: Dictionary = {}       ## fid -> {panel, order, name, sub, res}
var _turn_lbl: Label
var _btn_undo: Button
var _btn_auto: Button
var _btn_bot: Button
var _menu: MenuButton


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	var sb := CLTheme.flat(CLTheme.BAR)
	sb.border_width_bottom = 3
	sb.border_color = CLTheme.RED
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_build_brand())

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	var tiles_m := MarginContainer.new()
	for side in ["left", "right"]:
		tiles_m.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		tiles_m.add_theme_constant_override("margin_" + side, 7)
	tiles_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tiles_m.add_child(tiles)
	row.add_child(tiles_m)
	for fid in FACTIONS:
		tiles.add_child(_build_tile(fid))

	row.add_child(_vline())
	var turn_box := VBoxContainer.new()
	turn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_box.add_theme_constant_override("separation", -4)
	turn_box.custom_minimum_size = Vector2(78, 0)
	var tl := CLTheme.label("CARTE", CLTheme.TEXT_DIM, 12, CLTheme.ui_bold())
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_box.add_child(tl)
	_turn_lbl = CLTheme.label("—", Color.WHITE, 28, CLTheme.display())
	_turn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_lbl.tooltip_text = "Carte rimaste nel mazzo"
	turn_box.add_child(_turn_lbl)
	row.add_child(turn_box)

	row.add_child(_vline())
	_btn_undo = _cmd_button("Annulla", "Disfa l'ultima azione eseguita su questa carta (Ctrl+Z)")
	_btn_undo.pressed.connect(func(): undo_requested.emit())
	row.add_child(_btn_undo)
	row.add_child(_vline())
	_btn_auto = _cmd_button("Auto-Bot", "Se acceso, le Fazioni Bot giocano da sole quando tocca a loro")
	_btn_auto.toggle_mode = true
	_btn_auto.toggled.connect(func(_on): auto_bot_toggled.emit())
	row.add_child(_btn_auto)
	row.add_child(_vline())
	_btn_bot = _cmd_button("Gioca Bot", "Fai decidere al Bot l'azione della Fazione di turno")
	_btn_bot.pressed.connect(func(): bot_turn_requested.emit())
	row.add_child(_btn_bot)
	row.add_child(_vline())
	_menu = MenuButton.new()
	_menu.text = "Menu"
	_menu.tooltip_text = "Salvataggi, nuova partita, Bot e velocità"
	_style_cmd(_menu)
	var p := _menu.get_popup()
	p.add_item("Salva partita", MenuId.SAVE)
	p.add_item("Carica partita", MenuId.LOAD)
	p.add_item("Riprendi autosalvataggio", MenuId.AUTOSAVE)
	p.add_separator("Bot")
	p.add_item("Tutti i Bot (questa carta)", MenuId.ALL_BOTS)
	p.add_item("Auto: tutta la partita", MenuId.FULL_GAME)
	p.add_separator("Velocità dei Bot")
	p.add_radio_check_item("Lenta", MenuId.SPEED_SLOW)
	p.add_radio_check_item("Media", MenuId.SPEED_MED)
	p.add_radio_check_item("Veloce", MenuId.SPEED_FAST)
	p.set_item_checked(p.get_item_index(MenuId.SPEED_MED), true)
	p.add_separator()
	p.add_item("Nuova partita…", MenuId.NEW_GAME)
	p.add_item("Torna al menu iniziale", MenuId.MAIN_MENU)
	p.id_pressed.connect(_on_menu)
	row.add_child(_menu)


func _build_brand() -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", CLTheme.flat(CLTheme.RED, 0))
	pc.custom_minimum_size = Vector2(246, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 10)
	m.add_child(h)
	pc.add_child(m)
	var flag := FlagEmblem.new()
	flag.custom_minimum_size = Vector2(34, 34)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(flag)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -6)
	v.add_child(CLTheme.label("Cuba Libre", Color.WHITE, 36, CLTheme.display()))
	v.add_child(CLTheme.label("Insurrezione a Cuba · 1957–58", Color("f6e3df"), 11, CLTheme.typewriter()))
	h.add_child(v)
	return pc


func _build_tile(fid: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(176, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.tooltip_text = "Clicca per passare da Giocatore a Bot e viceversa"
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			role_toggle_requested.emit(fid))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	# Segnalino della Fazione con il numero d'ordine sulla carta.
	var tok_box := Control.new()
	tok_box.custom_minimum_size = Vector2(32, 40)
	tok_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tok := TextureRect.new()
	tok.texture = CLAssets.res_token(fid)
	tok.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tok.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tok.set_anchors_preset(Control.PRESET_FULL_RECT)
	tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tok_box.add_child(tok)
	var order := CLTheme.label("", CLTheme.BAR, 12, CLTheme.ui_heavy())
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ob := CLTheme.box(CLTheme.PAPER, CLTheme.PAPER, 0, 9)
	ob.content_margin_left = 0
	ob.content_margin_right = 0
	ob.content_margin_top = 0
	ob.content_margin_bottom = 0
	order.add_theme_stylebox_override("normal", ob)
	order.position = Vector2(20, -4)
	order.size = Vector2(17, 17)
	tok_box.add_child(order)
	h.add_child(tok_box)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := CLTheme.label(CLNames.faction_tile(fid), Color.WHITE, 17, CLTheme.ui_heavy())
	name_l.clip_text = true
	v.add_child(name_l)
	var sub := CLTheme.label("", CLTheme.TEXT_DIM, 13)
	sub.clip_text = true
	v.add_child(sub)
	# Vittoria: barra con la tacca della soglia e valore/soglia accanto.
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 5)
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := MeterBar.new()
	bar.color = CLTheme.faction(fid).lightened(0.15)
	bar.track_color = Color("33312b")
	bar.tick_color = CLTheme.PAPER
	bar.bar_height = 6
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vrow.add_child(bar)
	var vval := CLTheme.label("", CLTheme.TEXT_DIM, 12, CLTheme.ui_bold())
	vrow.add_child(vval)
	v.add_child(vrow)
	h.add_child(v)
	var res := CLTheme.label("", Color.WHITE, 28, CLTheme.display())
	res.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res.tooltip_text = "Risorse"
	res.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(res)
	_tiles[fid] = {"panel": pc, "order": order, "sub": sub, "res": res, "name": name_l,
		"bar": bar, "vval": vval}
	return pc


func _vline() -> Control:
	var c := ColorRect.new()
	c.color = CLTheme.BAR_LINE
	c.custom_minimum_size = Vector2(1, 0)
	return c


func _cmd_button(text: String, tip: String) -> Button:
	var b := TipButton.new()
	b.text = text
	b.tooltip_text = tip
	_style_cmd(b)
	return b


## Comandi della barra: piatti, alti quanto la barra, ottone al passaggio.
func _style_cmd(b: Button) -> void:
	CLTheme.style_button(b)
	b.custom_minimum_size = Vector2(76, 0)
	var n := CLTheme.flat(Color(0, 0, 0, 0), 8)
	var h := CLTheme.flat(Color("2a2822"), 8)
	var on := CLTheme.flat(Color("3a3324"), 8)
	on.border_width_bottom = 3
	on.border_color = CLTheme.BRASS_HI
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_color_override("font_color", Color("e8dcc0"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", CLTheme.BRASS_HI)
	b.add_theme_color_override("font_hover_pressed_color", CLTheme.BRASS_HI)
	b.add_theme_color_override("font_disabled_color", CLTheme.BTN_DISABLED_TEXT)
	b.add_theme_font_override("font", CLTheme.ui_bold())
	b.add_theme_font_size_override("font_size", 16)


func _on_menu(id: int) -> void:
	var p := _menu.get_popup()
	if id in [MenuId.SPEED_SLOW, MenuId.SPEED_MED, MenuId.SPEED_FAST]:
		for sid in [MenuId.SPEED_SLOW, MenuId.SPEED_MED, MenuId.SPEED_FAST]:
			p.set_item_checked(p.get_item_index(sid), sid == id)
	menu_id_pressed.emit(id)


func set_auto_bot(on: bool) -> void:
	_btn_auto.set_pressed_no_signal(on)
	_btn_auto.text = "Auto-Bot ON" if on else "Auto-Bot"


## Abilita/disabilita "Annulla" e ne aggiorna il suggerimento.
func set_undo(depth: int, label: String) -> void:
	_btn_undo.disabled = depth <= 0
	_btn_undo.text = "Annulla" if depth <= 0 else "Annulla (%d)" % depth
	_btn_undo.tooltip_text = "Disfa l'ultima azione eseguita su questa carta (Ctrl+Z)." if depth <= 0 \
		else "Disfa: %s — %d azioni annullabili (Ctrl+Z)" % [label, depth]


## Aggiorna le tessere: ordine sulla carta, ruolo, stato nella sequenza, Risorse.
func refresh() -> void:
	var gc = GameController
	var s: GameState = gc.state
	if s == null:
		return
	var card: CardDef = gc.game_def.card(s.current_card) if s.current_card > 0 else null
	var st: Dictionary = gc.seq_status()
	var pending := String(st.get("pending", ""))
	var actors: PackedStringArray = gc.seq.actors() if gc.seq != null else PackedStringArray()
	var passers: PackedStringArray = gc.seq.passers() if gc.seq != null else PackedStringArray()
	_turn_lbl.text = str(gc.cards_left())
	var vs: Dictionary = gc.victory()
	_btn_bot.disabled = pending == "" or gc.prop_pending
	for fid in FACTIONS:
		var t: Dictionary = _tiles[fid]
		var col := CLTheme.faction(fid)
		var active: bool = fid == pending and not gc.prop_pending
		var idx := card.faction_order.find(fid) if card != null else -1
		(t["order"] as Label).visible = idx >= 0
		(t["order"] as Label).text = str(idx + 1)
		var status := "disponibile"
		if active:
			status = "di turno"
		elif passers.has(fid):
			status = "ha passato"
		elif actors.has(fid):
			status = "ha agito"
		elif s.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) != CoinEnums.Eligibility.ELIGIBLE:
			status = "non disponibile"
		(t["sub"] as Label).text = "%s · %s" % ["Giocatore" if gc.is_player(fid) else "Bot", status]
		(t["res"] as Label).text = str(s.get_resources(fid)) if s.tracks_resources(fid) else "—"
		var d: Dictionary = vs.get(fid, {})
		var val := int(d.get("value", 0))
		var thr := int(d.get("threshold", 0))
		var bar: MeterBar = t["bar"]
		bar.max_value = maxf(thr * 1.45, val + 2.0)
		bar.set_values(val, thr)
		bar.color = Color.WHITE if active else col.lightened(0.15)
		bar.track_color = col.darkened(0.45) if active else Color("33312b")
		(t["vval"] as Label).text = "%d/%d" % [val, thr]
		(t["vval"] as Label).add_theme_color_override("font_color",
			Color("3b2f0a") if active and fid == "directorio" else (Color.WHITE if active else CLTheme.TEXT_DIM))
		(t["panel"] as Control).tooltip_text = "%s · Vittoria %s: %d (soglia %d, margine %+d)\nClicca per passare da Giocatore a Bot e viceversa" % [
			gc.faction_name(fid), VIC_LABEL.get(fid, ""), val, thr, int(d.get("margin", 0))]
		var sb := CLTheme.box(col if active else Color("1c1b18"),
			CLTheme.PAPER if active else Color("33312b"), 1)
		sb.border_width_left = 5
		sb.border_color = CLTheme.PAPER if active else Color("33312b")
		if not active:
			sb.border_color = col
			sb.border_width_top = 0
			sb.border_width_right = 0
			sb.border_width_bottom = 0
		sb.content_margin_left = 6
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		(t["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var dim: bool = not active and (status == "non disponibile" or status == "ha agito" or status == "ha passato")
		(t["panel"] as PanelContainer).modulate = Color(1, 1, 1, 0.6 if dim else 1.0)
		var fg := Color("111111") if active and fid == "directorio" else Color.WHITE
		(t["name"] as Label).add_theme_color_override("font_color", fg)
		(t["res"] as Label).add_theme_color_override("font_color", fg)
		(t["sub"] as Label).add_theme_color_override("font_color",
			Color("3b2f0a") if active and fid == "directorio" else (Color("f6e3df") if active else CLTheme.TEXT_DIM))


## Emblema disegnato: bandiera del 26 Luglio stilizzata (nero/crema con stella).
class FlagEmblem:
	extends Control

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h / 2.0), CLTheme.BAR)
		draw_rect(Rect2(0, h / 2.0, w, h / 2.0), CLTheme.PAPER)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.6, h / 2.0), Vector2(0, h)]), CLTheme.BAR)
		var c := Vector2(w * 0.2, h / 2.0)
		var pts := PackedVector2Array()
		for i in range(10):
			var r := (h * 0.2) if i % 2 == 0 else (h * 0.08)
			var a := -PI / 2.0 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, CLTheme.PAPER)

