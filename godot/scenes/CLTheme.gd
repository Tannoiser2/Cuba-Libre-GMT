class_name CLTheme
extends RefCounted

## Aspetto dei comandi: unico posto dove vivono colori e riquadri dei tasti.
## Prima gli stessi StyleBox venivano ricostruiti a mano in quattro funzioni diverse
## di Main.gd, con il rischio che un ritocco ne raggiungesse solo una parte.

const BG := Color("12161c")            ## sfondo della scena
const TEXT := Color("e6edf3")
const TEXT_DIM := Color("9fb3c8")
const ACCENT := Color("f1c40f")        ## evidenziazioni e istruzioni
const OK := Color("57c97e")            ## esito positivo / costo sostenibile
const ERR := Color("ff6b6b")           ## errori
const WARN := Color("ff9f6b")          ## avvisi ("non eseguibile")

const BTN_BG := Color("2b3442")
const BTN_BORDER := Color("4a5666")
const BTN_HOVER_BG := Color("3a4759")
const BTN_HOVER_BORDER := Color("6f8197")
const BTN_PRESSED_BG := Color("1d242e")
const BTN_DISABLED_BG := Color("222831")
const BTN_DISABLED_BORDER := Color("333b46")
const BTN_DISABLED_TEXT := Color("5b6571")
const FONT_SIZE := 12


## Riquadro arrotondato con bordo, usato per tutti gli stati dei tasti.
static func box(bg: Color, border: Color) -> StyleBoxFlat:
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


## Veste standard di un tasto (anche MenuButton): riquadro + stati + colori del testo.
static func style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("hover", box(BTN_HOVER_BG, BTN_HOVER_BORDER))
	b.add_theme_stylebox_override("pressed", box(BTN_PRESSED_BG, BTN_BORDER))
	b.add_theme_stylebox_override("disabled", box(BTN_DISABLED_BG, BTN_DISABLED_BORDER))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", BTN_DISABLED_TEXT)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	# Niente focus persistente: altrimenti Invio/Spazio ri-attivano l'ultimo tasto
	# premuto invece di eseguire le scorciatoie di turno.
	b.focus_mode = Control.FOCUS_NONE


## Tasto in evidenza, con sfondo colorato (es. "Esegui", Auto-Bot acceso).
static func accent_button(b: Button, bg: Color, border: Color) -> void:
	b.add_theme_stylebox_override("normal", box(bg, border))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.12), border))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.18), border))
	b.add_theme_color_override("font_color", Color.WHITE)


## Testo su fondino del colore della Fazione (usato dal log e dal pannello Vittoria).
## Il giallo del Directorio richiede testo scuro per restare leggibile.
static func faction_chip(text: String, faction: String) -> String:
	if faction == "":
		return text
	var hex := GameController.faction_color(faction).to_html(false)
	var fg := "000000" if faction == "directorio" else "ffffff"
	return "[bgcolor=#%s] [color=#%s] %s [/color] [/bgcolor]" % [hex, fg, text]

