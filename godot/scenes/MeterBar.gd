class_name MeterBar
extends Control

## Barra orizzontale con tacca di soglia facoltativa (Vittoria sotto le tessere Fazione).

var color := Color.WHITE
var track_color := Color("d8caa6")
var tick_color := Color("231d16")
var max_value := 26.0
var bar_height := 10.0
var _value := 0.0
var _threshold := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(30, bar_height + 4)


func set_values(v: float, thr: float) -> void:
	_value = v
	_threshold = thr
	queue_redraw()


func _draw() -> void:
	var y := (size.y - bar_height) * 0.5
	draw_rect(Rect2(0, y, size.x, bar_height), track_color)
	var frac := clampf(_value / maxf(1.0, max_value), 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(0, y, size.x * frac, bar_height), color)
	if _threshold >= 0.0:
		var tx := size.x * clampf(_threshold / maxf(1.0, max_value), 0.0, 1.0)
		draw_rect(Rect2(tx - 1, y - 2, 2, bar_height + 4), tick_color)
