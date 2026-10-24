class_name BottomStrip
extends PanelContainer

## Striscia sotto la mappa: il registro delle azioni.
## Carte, Risorse e Vittoria vivono altrove (pannello azione e tessere Fazione), così
## qui resta spazio per leggere più righe di registro e la mappa guadagna altezza.

const HEIGHT := 128.0

var log_view: LogView          ## esposto: la scena ci collega i segnali del controller


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", CLTheme.dark_box(CLTheme.LOG_BG, CLTheme.LOG_EDGE))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	v.add_child(CLTheme.section_title("Registro", CLTheme.BRASS))
	log_view = LogView.new()
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 60)
	v.add_child(log_view)


## Niente da ricalcolare: il registro si aggiorna coi segnali del controller.
func refresh() -> void:
	pass
