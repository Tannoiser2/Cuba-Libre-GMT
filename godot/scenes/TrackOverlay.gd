class_name TrackOverlay
extends Control

## Disegna i segnalini sui tracciati di bordo mappa: Risorse delle 4 Fazioni, Aiuti,
## i 4 marcatori di vittoria (Totale Supporto, Opp+Basi, DR Pop+Basi, Casinò aperti)
## sul tracciato perimetrale 0–49, e il marcatore dell'Alleanza USA nella sua casella.
## I segnalini con lo stesso valore vengono impilati leggermente per non sovrapporsi.

const BASE_OFF := 20.0   # scostamento dei segnalini sotto la riga dei numeri
const STACK := 15.0      # scostamento per segnalini sulla stessa cella


func _track_norm(value: int) -> Vector2:
	value = clampi(value, 0, 49)
	if value <= 30:
		return Vector2(0.037 + value * 0.03067, 0.072)
	return Vector2(0.978, 0.115 + (value - 31) * 0.04722)


func _draw() -> void:
	var s: GameState = GameController.state
	if s == null:
		return
	var mod: CubaLibreModule = GameController.module
	# Elenco segnalini (valore, colore, etichetta)
	var chips := [
		[s.get_resources("government"), GameController.faction_color("government"), "G"],
		[s.get_resources("m26"), GameController.faction_color("m26"), "26"],
		[s.get_resources("directorio"), GameController.faction_color("directorio"), "DR"],
		[s.get_resources("syndicate"), GameController.faction_color("syndicate"), "S"],
		[int(s.tracks.get("aid", 0)), Color("e67e22"), "Ai"],
		[s.total_support(), Color("5dade2"), "Su"],
		[mod.opposition_plus_bases(s), Color("a93226"), "OB"],
		[mod.dr_pop_plus_bases(s), Color("d4ac0d"), "Dp"],
		[mod.open_casinos(s), Color("27ae60"), "Ca"],
	]
	# Raggruppa per valore per impilare solo i segnalini sulla stessa cella
	var counts := {}
	for ch in chips:
		var v := clampi(int(ch[0]), 0, 49)
		var idx := int(counts.get(v, 0))
		counts[v] = idx + 1
		_chip(v, idx, ch[1], ch[2])

	# Alleanza USA nella sua casella
	var ai := int(s.tracks.get("us_alliance", 0))
	var ay: float = [0.135, 0.185, 0.235][ai]
	var ac := Vector2(0.145 * size.x, ay * size.y)
	draw_circle(ac, 10.0, Color("2c3e50"))
	draw_arc(ac, 10.0, 0, TAU, 16, Color("f1c40f"), 2.0)
	_label(ac, "USA")


func _chip(value: int, stack_idx: int, col: Color, label: String) -> void:
	var n := _track_norm(value)
	var c := Vector2(n.x * size.x, n.y * size.y)
	if value <= 30:
		c.y += BASE_OFF + stack_idx * STACK
	else:
		c.x -= BASE_OFF + stack_idx * STACK
	draw_circle(c, 8.5, col)
	draw_arc(c, 8.5, 0, TAU, 16, Color(0, 0, 0, 0.7), 1.5)
	_label(c, label)


func _label(c: Vector2, t: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-9, 4), t, HORIZONTAL_ALIGNMENT_CENTER, 18, 10, Color.WHITE)
