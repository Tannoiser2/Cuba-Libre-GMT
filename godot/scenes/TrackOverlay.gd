class_name TrackOverlay
extends Control

## Disegna i segnalini sui tracciati di bordo mappa: Risorse delle 4 Fazioni, Aiuti,
## i 4 marcatori di vittoria (Totale Supporto, Opp+Basi, DR Pop+Basi, Casinò aperti)
## sul tracciato perimetrale 0–49, e il marcatore dell'Alleanza USA nella sua casella.
## Coordinate normalizzate sull'immagine mappa (approssimate, rifinibili).

# Posizione normalizzata della cella `value` (0..49) del tracciato perimetrale.
func _track_norm(value: int) -> Vector2:
	value = clampi(value, 0, 49)
	if value <= 30:
		return Vector2(0.037 + value * 0.03067, 0.072)
	return Vector2(0.978, 0.115 + (value - 31) * 0.04722)


func _chip(value: int, lane: int, col: Color, label: String) -> void:
	var n := _track_norm(value)
	var c := Vector2(n.x * size.x, n.y * size.y)
	# sfalsa le corsie per non sovrapporre i segnalini sulla stessa cella
	if value <= 30:
		c.y += lane * 15.0
	else:
		c.x -= lane * 15.0
	draw_circle(c, 9.0, col)
	draw_arc(c, 9.0, 0, TAU, 16, Color(0, 0, 0, 0.7), 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-7, 4), label, HORIZONTAL_ALIGNMENT_CENTER, 14, 11, Color.WHITE)


func _draw() -> void:
	var s: GameState = GameController.state
	if s == null:
		return
	var mod: CubaLibreModule = GameController.module
	# Risorse delle Fazioni (corsie 0..3)
	_chip(s.get_resources("government"), 0, GameController.faction_color("government"), "G")
	_chip(s.get_resources("m26"), 1, GameController.faction_color("m26"), "26")
	_chip(s.get_resources("directorio"), 2, GameController.faction_color("directorio"), "DR")
	_chip(s.get_resources("syndicate"), 3, GameController.faction_color("syndicate"), "S")
	# Aiuti
	_chip(int(s.tracks.get("aid", 0)), 4, Color("e67e22"), "Aid")
	# Marcatori di vittoria
	_chip(s.total_support(), 5, Color("5dade2"), "Sup")
	_chip(mod.opposition_plus_bases(s), 6, Color("a93226"), "O+B")
	_chip(mod.dr_pop_plus_bases(s), 7, Color("d4ac0d"), "DRp")
	_chip(mod.open_casinos(s), 8, Color("27ae60"), "Cas")
	# Alleanza USA nella sua casella (Firm/Reluctant/Embargoed)
	var idx := int(s.tracks.get("us_alliance", 0))
	var ay: float = [0.135, 0.185, 0.235][idx]
	var ac := Vector2(0.145 * size.x, ay * size.y)
	draw_circle(ac, 10.0, Color("2c3e50"))
	draw_arc(ac, 10.0, 0, TAU, 16, Color("f1c40f"), 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, ac + Vector2(-8, 4), "USA", HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)
