class_name MovesOverlay
extends Control

## Disegna le frecce degli spostamenti in coda (anteprima): da casella di partenza
## a casella di destinazione. I pezzi si muovono davvero solo con "Esegui", quindi qui
## mostriamo l'intenzione di movimento, non lo stato finale.

var _segments: Array = []   # [{from: Vector2, to: Vector2}]
var color := Color(0.25, 0.85, 1.0, 0.95)


func set_segments(segs: Array) -> void:
	_segments = segs
	queue_redraw()


func _draw() -> void:
	for seg in _segments:
		_draw_arrow(seg["from"], seg["to"])


func _draw_arrow(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 1.0:
		return
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# Accorcia un po' le estremità per non coprire del tutto i pezzi.
	var a2 := a + dir * 10.0
	var b2 := b - dir * 12.0
	# Bordo scuro + linea colorata (così risalta su sfondi chiari/scuri).
	draw_line(a2, b2, Color(0, 0, 0, 0.5), 5.0)
	draw_line(a2, b2, color, 3.0)
	# Punta della freccia.
	var head := 13.0
	var tip := b - dir * 4.0
	var p1 := tip - dir * head + perp * head * 0.55
	var p2 := tip - dir * head - perp * head * 0.55
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)
	# Pallino sull'origine.
	draw_circle(a, 4.5, Color(0, 0, 0, 0.5))
	draw_circle(a, 3.0, color)
