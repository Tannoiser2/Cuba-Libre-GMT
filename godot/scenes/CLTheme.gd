class_name CLTheme
extends RefCounted

## Aspetto dell'interfaccia: tema "dossier rivoluzionario 1958".
##
## Unico posto dove vivono colori, caratteri e riquadri. Lo schema della schermata
## (barra in alto, mappa, pannello azione a destra, striscia in basso) è comune a tutti
## i giochi COIN; per un altro titolo della serie basta cambiare QUESTO file:
## palette, caratteri ed emblema.
##
## Due "superfici":
##  - scura (barra superiore, mappa, registro): testo chiaro su nero / mare di notte;
##  - carta (pannello azione, carta, risorse, vittoria): inchiostro su carta da dossier.

# --- Palette -----------------------------------------------------------------
const BG := Color("111a1c")            ## sfondo della scena (mare di notte)
const BAR := Color("0c0c0b")           ## barra superiore (nero 26 Luglio)
const BAR_LINE := Color("2b2a26")      ## divisori nella barra
const PAPER := Color("efe6cf")         ## carta da dossier
const PAPER_DARK := Color("e3d6b5")    ## carta in ombra (riquadri interni, hover)
const PAPER_EDGE := Color("b8a985")    ## bordo tenue su carta / disattivato
const INK := Color("231d16")           ## inchiostro
const INK_DIM := Color("5c5141")       ## inchiostro attenuato (etichette)
const INK_FAINT := Color("8a7d60")     ## testo disattivato su carta
const RED := Color("a8232b")           ## rosso rivoluzione: tasto principale, timbri
const RED_DARK := Color("4e1014")      ## ombra del tasto principale
const BRASS := Color("c9a24a")         ## ottone: titoli sul buio, cornice mappa
const BRASS_HI := Color("e9c46a")      ## spazio valido / selezionato
const LOG_BG := Color("1b2224")        ## fondo del registro
const LOG_EDGE := Color("344043")

const TEXT := Color("efe6cf")          ## testo chiaro sul buio
const TEXT_DIM := Color("b9ad90")      ## testo attenuato sul buio
const ACCENT := BRASS_HI               ## evidenziazioni (compatibilità)
const OK := Color("57c97e")            ## esito positivo (sul buio)
const OK_INK := Color("1f6b3a")        ## esito positivo (su carta)
const ERR := Color("ff6b6b")           ## errori (sul buio)
const ERR_INK := RED                   ## errori (su carta)
const WARN := Color("ff9f6b")
const WARN_INK := Color("9a4a12")

# Tasti sul buio (barra superiore, menu, finestre di dialogo).
const BTN_BG := Color("1c1b18")
const BTN_BORDER := Color("4a4231")
const BTN_HOVER_BG := Color("2a2822")
const BTN_HOVER_BORDER := BRASS
const BTN_PRESSED_BG := Color("0c0c0b")
const BTN_DISABLED_BG := Color("151513")
const BTN_DISABLED_BORDER := Color("2b2a26")
const BTN_DISABLED_TEXT := Color("6a6352")
const FONT_SIZE := 15

## Colori delle Fazioni (stessi della scatola, un po' più saturi sul buio).
const FACTION := {
	"government": Color("2f6db5"), "m26": Color("a8232b"),
	"directorio": Color("d9a91f"), "syndicate": Color("3f9a4a"),
}
## Variante più scura per barre su carta (il giallo puro non si legge sul crema).
const FACTION_INK := {
	"government": Color("2f6db5"), "m26": Color("a8232b"),
	"directorio": Color("b8901a"), "syndicate": Color("3f9a4a"),
}

# --- Caratteri (OFL / Apache, in res://assets/fonts) --------------------------
const FONT_DIR := "res://assets/fonts/"
static var _fonts: Dictionary = {}


static func _font(file: String) -> Font:
	if not _fonts.has(file):
		var path := FONT_DIR + file
		_fonts[file] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[file]


## Bebas Neue: titoli, tasto principale, numeri grandi (solo maiuscole).
static func display() -> Font: return _font("BebasNeue-Regular.ttf")
## Special Elite: testi delle carte, istruzioni, registro (dattiloscritto).
static func typewriter() -> Font: return _font("SpecialElite-Regular.ttf")
## Barlow Condensed: testo dell'interfaccia.
static func ui() -> Font: return _font("BarlowCondensed-Regular.ttf")
static func ui_bold() -> Font: return _font("BarlowCondensed-SemiBold.ttf")
static func ui_heavy() -> Font: return _font("BarlowCondensed-Bold.ttf")


static func faction(fid: String) -> Color:
	return FACTION.get(fid, Color.WHITE)


static func faction_ink(fid: String) -> Color:
	return FACTION_INK.get(fid, INK)


# --- Riquadri -------------------------------------------------------------------

## Riquadro con bordo, usato per tutti gli stati dei tasti.
static func box(bg: Color, border: Color, border_w: int = 1, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


## Foglio di carta (pannelli informativi): crema, angoli appena smussati, ombra.
static func paper_box(margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.set_corner_radius_all(3)
	s.border_color = Color("d4c49c")
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin - 2.0
	s.content_margin_bottom = margin - 2.0
	return s


## Riquadro scuro semitrasparente (comandi sopra la mappa, registro).
static func dark_box(bg: Color = Color(0.047, 0.047, 0.043, 0.85), border: Color = BTN_BORDER) -> StyleBoxFlat:
	var s := box(bg, border)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func flat(bg: Color, margin: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


# --- Temi ----------------------------------------------------------------------

static var _dark_theme: Theme
static var _paper_theme: Theme


## Tema delle superfici scure: si applica alla radice della scena (e alla finestra,
## così anche menu a tendina e finestre di dialogo prendono caratteri e colori).
static func dark_theme() -> Theme:
	if _dark_theme != null:
		return _dark_theme
	var t := Theme.new()
	t.default_font = ui()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)
	_button_styles(t, "Button", BTN_BG, BTN_BORDER, BTN_HOVER_BG, BTN_HOVER_BORDER, BTN_PRESSED_BG,
		BTN_DISABLED_BG, BTN_DISABLED_BORDER, TEXT, Color.WHITE, BTN_DISABLED_TEXT, 1)
	_button_styles(t, "MenuButton", BTN_BG, BTN_BORDER, BTN_HOVER_BG, BTN_HOVER_BORDER, BTN_PRESSED_BG,
		BTN_DISABLED_BG, BTN_DISABLED_BORDER, TEXT, Color.WHITE, BTN_DISABLED_TEXT, 1)
	_button_styles(t, "OptionButton", BTN_BG, BTN_BORDER, BTN_HOVER_BG, BTN_HOVER_BORDER, BTN_PRESSED_BG,
		BTN_DISABLED_BG, BTN_DISABLED_BORDER, TEXT, Color.WHITE, BTN_DISABLED_TEXT, 1)
	# Menu a tendina: carta scura con voce evidenziata in ottone.
	var pm := box(Color("1c1b18"), BTN_BORDER)
	pm.content_margin_top = 6.0
	pm.content_margin_bottom = 6.0
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color("3a3324"), BRASS))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", BTN_DISABLED_TEXT)
	t.set_color("font_separator_color", "PopupMenu", TEXT_DIM)
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	# Finestre di dialogo: foglio di carta.
	var dlg := paper_box(18.0)
	t.set_stylebox("panel", "AcceptDialog", dlg)
	t.set_color("font_color", "AcceptDialog", INK)
	t.set_stylebox("embedded_border", "Window", box(PAPER, Color("d4c49c")))
	t.set_color("title_color", "Window", INK)
	t.set_font("title_font", "Window", display())
	t.set_font_size("title_font_size", "Window", 22)
	t.set_stylebox("panel", "TooltipPanel", box(BAR, BRASS))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", ui())
	t.set_font("bold_font", "RichTextLabel", ui_bold())
	# Barre di scorrimento sottili, color ottone.
	for sb_type in ["VScrollBar", "HScrollBar"]:
		var grab := box(Color("4a4231"), Color("4a4231"), 0, 4)
		t.set_stylebox("grabber", sb_type, grab)
		t.set_stylebox("grabber_highlight", sb_type, box(BRASS, BRASS, 0, 4))
		t.set_stylebox("grabber_pressed", sb_type, box(BRASS_HI, BRASS_HI, 0, 4))
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.0)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		t.set_stylebox("scroll", sb_type, track)
	_dark_theme = t
	return t


## Tema dei fogli di carta: inchiostro, tasti a contorno.
static func paper_theme() -> Theme:
	if _paper_theme != null:
		return _paper_theme
	var t := Theme.new()
	t.default_font = ui()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", INK)
	for type in ["Button", "MenuButton"]:
		_button_styles(t, type, Color(0, 0, 0, 0), INK, PAPER_DARK, INK, INK,
			Color(0, 0, 0, 0), PAPER_EDGE, INK, INK, INK_FAINT, 2)
		t.set_color("font_pressed_color", type, PAPER)
		t.set_font("font", type, ui_bold())
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", typewriter())
	t.set_font("bold_font", "RichTextLabel", ui_heavy())
	var pm := box(PAPER, INK)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(INK, INK))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", PAPER)
	t.set_color("font_disabled_color", "PopupMenu", INK_FAINT)
	t.set_font("font", "PopupMenu", ui_bold())
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	t.set_stylebox("panel", "TooltipPanel", box(BAR, BRASS))
	t.set_color("font_color", "TooltipLabel", TEXT)
	_paper_theme = t
	return t


static func _button_styles(t: Theme, type: String, bg: Color, border: Color, hover_bg: Color,
		hover_border: Color, pressed_bg: Color, dis_bg: Color, dis_border: Color,
		fg: Color, hover_fg: Color, dis_fg: Color, bw: int) -> void:
	t.set_stylebox("normal", type, box(bg, border, bw))
	t.set_stylebox("hover", type, box(hover_bg, hover_border, bw))
	t.set_stylebox("pressed", type, box(pressed_bg, border, bw))
	t.set_stylebox("hover_pressed", type, box(pressed_bg, hover_border, bw))
	t.set_stylebox("disabled", type, box(dis_bg, dis_border, bw))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, hover_fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_pressed_color", type, hover_fg)
	t.set_color("font_hover_pressed_color", type, hover_fg)
	t.set_color("font_disabled_color", type, dis_fg)


# --- Tasti ---------------------------------------------------------------------

## Veste standard di un tasto (anche MenuButton). Colori e riquadri arrivano dal tema
## della superficie su cui si trova; qui resta solo ciò che vale ovunque.
static func style_button(b: Button) -> void:
	# Niente focus persistente: altrimenti Invio/Spazio ri-attivano l'ultimo tasto
	# premuto invece di eseguire le scorciatoie di turno.
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.remove_theme_stylebox_override(st)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.remove_theme_color_override(c)


## Tasto sul buio con veste esplicita (usato dove il tema della scena non arriva,
## per esempio nel menu iniziale).
static func style_dark_button(b: Button) -> void:
	style_button(b)
	b.add_theme_stylebox_override("normal", box(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("hover", box(BTN_HOVER_BG, BTN_HOVER_BORDER))
	b.add_theme_stylebox_override("pressed", box(BTN_PRESSED_BG, BTN_BORDER))
	b.add_theme_stylebox_override("disabled", box(BTN_DISABLED_BG, BTN_DISABLED_BORDER))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", BTN_DISABLED_TEXT)
	b.add_theme_font_override("font", ui_bold())
	b.add_theme_font_size_override("font_size", FONT_SIZE)


## Tasto in evidenza, con sfondo pieno (es. "Esegui", Auto-Bot acceso, scelta attiva).
static func accent_button(b: Button, bg: Color, border: Color) -> void:
	b.add_theme_stylebox_override("normal", box(bg, border, 2))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.12), border, 2))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.18), border, 2))
	b.add_theme_stylebox_override("hover_pressed", box(bg.darkened(0.18), border, 2))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)


## Tasto principale del pannello: rosso pieno con "spessore" sotto, scritta Bebas.
static func primary_button(b: Button, size: int = 26) -> void:
	style_button(b)
	var n := box(RED, RED, 0)
	n.shadow_color = RED_DARK
	n.shadow_size = 0
	n.border_width_bottom = 4
	n.border_color = RED_DARK
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = RED.lightened(0.1)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = RED.darkened(0.15)
	p.border_width_bottom = 1
	var d := box(Color("c9b9a0"), Color("b0a184"), 0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("f3ece0"))
	b.add_theme_font_override("font", display())
	b.add_theme_font_size_override("font_size", size)


# --- Etichette -----------------------------------------------------------------

## Titolo di sezione in Bebas (es. "1 · OPERAZIONE").
static func section_title(text: String, color: Color = INK_DIM, size: int = 19) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Etichetta generica con carattere/colore/dimensione.
static func label(text: String, color: Color, size: int = FONT_SIZE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Testo su fondino del colore della Fazione (usato dal log e dal pannello Vittoria).
## Il giallo del Directorio richiede testo scuro per restare leggibile.
static func faction_chip(text: String, faction_id: String) -> String:
	if faction_id == "":
		return text
	var hex := faction(faction_id).to_html(false)
	var fg := "111111" if faction_id == "directorio" else "ffffff"
	return "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" % [hex, fg, text]
