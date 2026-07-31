class_name MapAnimator
extends Control

## Effetti sulla mappa: i pezzi che cambiano posto volano da una zona all'altra (o da/verso
## i box delle Forze Disponibili) con una scia luminosa, e gli spazi il cui stato è cambiato
## lampeggiano.
##
## Funziona per DIFFERENZA: confronta i conteggi con quelli dell'aggiornamento precedente,
## quindi non ha bisogno di sapere quali azioni siano state svolte. Il layer è puramente
## decorativo e non intercetta il mouse.

const PIECE_SIZE := 26.0    ## dimensione del pezzo animato
const DURATION := 0.9       ## durata del volo
const MAX_GHOSTS := 24      ## oltre questa soglia si salta (nuova partita, Propaganda)
const ECHOES := 4           ## copie della scia (la prima è la "testa")

const FACTIONS := ["government", "m26", "directorio", "syndicate"]
const TYPES := ["troops", "police", "base", "guerrilla", "casino"]

var _views: Dictionary = {}      ## space_id -> RegionView (per i centri delle zone)
var _avail_box: Dictionary = {}  ## fazione -> centro normalizzato del box Disponibili
var _prev_counts: Dictionary = {}
var _prev_fingerprint: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50


## Collega le viste degli spazi e carica i centri dei box "Forze Disponibili".
func setup(views: Dictionary) -> void:
	_views = views
	_avail_box = _load_avail_boxes()


func _load_avail_boxes() -> Dictionary:
	var out: Dictionary = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://games/cuba_libre/data/board_layout.json"))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var box: Dictionary = data.get("box", {})
	for fid in FACTIONS:
		var r = box.get("available_%s" % fid, null)
		if r != null:
			out[fid] = Vector2((r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5)
	return out


## Dopo un caricamento o una nuova partita: riparte dal nuovo stato senza animare
## le decine di differenze accumulate.
func reset() -> void:
	_prev_counts.clear()
	_prev_fingerprint.clear()


## Da chiamare a ogni aggiornamento: anima gli spostamenti e fa lampeggiare i cambiamenti.
func update(state: GameState, map_size: Vector2) -> void:
	_animate_moves(state, map_size)
	_flash_changes(state)


# ---------------------------------------------------------------------------
# Spostamenti
# ---------------------------------------------------------------------------

func _animate_moves(state: GameState, map_size: Vector2) -> void:
	var counts: Dictionary = {}
	for sid in _views.keys():
		var st: SpaceState = state.space_state(sid)
		for f in FACTIONS:
			for t in TYPES:
				var n := st.count(f, t)
				if n > 0:
					counts["%s|%s|%s" % [sid, f, t]] = n
	# Primo aggiornamento: memorizza soltanto.
	if _prev_counts.is_empty():
		_prev_counts = counts
		return
	var ghosts := _collect_ghosts(counts, map_size)
	_prev_counts = counts
	# Troppi movimenti insieme: salta per non intasare lo schermo.
	if ghosts.size() > MAX_GHOSTS:
		return
	for g in ghosts:
		_spawn_ghost(String(g["f"]), String(g["t"]), g["from"], g["to"])


## Accoppia le diminuzioni con gli aumenti per (fazione, tipo): ciò che resta scompensato
## arriva dal box Forze Disponibili o vi ritorna.
func _collect_ghosts(counts: Dictionary, map_size: Vector2) -> Array:
	var ghosts: Array = []
	for f in FACTIONS:
		var box_c: Vector2 = (_avail_box.get(f, Vector2(0.5, 0.5)) as Vector2) * map_size
		for t in TYPES:
			var sources: Array = []   # [sid, quantità]
			var dests: Array = []
			for sid in _views.keys():
				var key := "%s|%s|%s" % [sid, f, t]
				var d: int = int(counts.get(key, 0)) - int(_prev_counts.get(key, 0))
				if d < 0:
					sources.append([sid, -d])
				elif d > 0:
					dests.append([sid, d])
			var si := 0
			var left := 0 if sources.is_empty() else int(sources[0][1])
			for de in dests:
				var dv: RegionView = _views[de[0]]
				var dc := dv.center_point()
				for _k in range(int(de[1])):
					var from_pos := box_c
					if si < sources.size():
						var sv: RegionView = _views[sources[si][0]]
						from_pos = sv.center_point()
						left -= 1
						if left <= 0:
							si += 1
							left = 0 if si >= sources.size() else int(sources[si][1])
					ghosts.append({"f": f, "t": t, "from": from_pos, "to": dc})
			while si < sources.size():
				var rv: RegionView = _views[sources[si][0]]
				var sc := rv.center_point()
				for _k2 in range(left):
					ghosts.append({"f": f, "t": t, "from": sc, "to": box_c})
				si += 1
				left = 0 if si >= sources.size() else int(sources[si][1])
	return ghosts


## Un pezzo che vola da `from_pos` a `to_pos` con effetto cometa: una testa brillante
## più alcune copie sfalsate che la inseguono attenuandosi.
func _spawn_ghost(faction: String, type: String, from_pos: Vector2, to_pos: Vector2) -> void:
	var tex := CLAssets.piece(faction, type, "")
	if tex == null:
		return
	var half := Vector2(PIECE_SIZE, PIECE_SIZE) * 0.5
	for e in range(ECHOES):
		var g := TextureRect.new()
		g.texture = tex
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size = Vector2(PIECE_SIZE, PIECE_SIZE)
		g.pivot_offset = half
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.position = from_pos - half
		var head := e == 0
		g.modulate = Color(1.5, 1.5, 1.2, 1.0) if head else Color(1.2, 1.2, 1.1, 0.5 - 0.1 * float(e))
		g.scale = Vector2(1.45, 1.45) if head else Vector2(1.2, 1.2)
		add_child(g)
		var lead := float(e) * 0.08   # ritardo crescente: la copia resta indietro (scia)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if lead > 0.0:
			tw.tween_interval(lead)
		tw.tween_property(g, "position", to_pos - half, DURATION)
		tw.parallel().tween_property(g, "scale", Vector2(1, 1), DURATION)
		tw.parallel().tween_property(g, "modulate:a", 0.0, DURATION * 0.45).set_delay(DURATION * 0.55)
		tw.tween_callback(g.queue_free)


# ---------------------------------------------------------------------------
# Lampeggio degli spazi cambiati
# ---------------------------------------------------------------------------

func _flash_changes(state: GameState) -> void:
	var first := _prev_fingerprint.is_empty()
	for sid in _views.keys():
		var fp := fingerprint(state, sid)
		if not first and String(_prev_fingerprint.get(sid, "")) != fp:
			(_views[sid] as RegionView).flash()
		_prev_fingerprint[sid] = fp


## Firma dello stato di uno spazio: cambia se cambia qualcosa di visibile.
static func fingerprint(state: GameState, sid: String) -> String:
	var st: SpaceState = state.space_state(sid)
	var out := "%s,%d,%d,%d" % [st.control, st.support, st.marker("terror"), st.marker("sabotage")]
	for f in FACTIONS:
		for t in TYPES:
			out += "," + str(st.count(f, t))
	return out
