class_name TrackOverlay
extends Control

## Disegna i segnalini originali sui tracciati di bordo mappa: cilindri Risorse delle 4
## Fazioni, Aiuti, i 4 marcatori di vittoria sul tracciato perimetrale 0–49, e il marcatore
## dell'Alleanza USA nella sua casella. I segnalini con lo stesso valore vengono sfalsati.

const BASE_OFF := 18.0   # scostamento sotto la riga dei numeri
const STACK := 22.0      # scostamento per segnalini sulla stessa cella
const MK := 26.0         # dimensione segnalino


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
	var chips := [
		[s.get_resources("government"), CLAssets.res_token("government")],
		[s.get_resources("m26"), CLAssets.res_token("m26")],
		[s.get_resources("directorio"), CLAssets.res_token("directorio")],
		[s.get_resources("syndicate"), CLAssets.res_token("syndicate")],
		[int(s.tracks.get("aid", 0)), CLAssets.aid_marker()],
		[s.total_support(), CLAssets.vic_support()],
		[mod.opposition_plus_bases(s), CLAssets.vic_opp_bases()],
		[mod.dr_pop_plus_bases(s), CLAssets.vic_dr()],
		[mod.open_casinos(s), CLAssets.vic_casinos()],
	]
	var counts := {}
	for ch in chips:
		var v := clampi(int(ch[0]), 0, 49)
		var idx := int(counts.get(v, 0))
		counts[v] = idx + 1
		_marker(v, idx, ch[1])

	# Alleanza USA nella sua casella (Firm/Reluctant/Embargoed)
	var ai := int(s.tracks.get("us_alliance", 0))
	var ay: float = [0.135, 0.185, 0.235][ai]
	_blit(CLAssets.alliance_marker(), Vector2(0.145 * size.x, ay * size.y))


func _marker(value: int, stack_idx: int, t: Texture2D) -> void:
	var n := _track_norm(value)
	var c := Vector2(n.x * size.x, n.y * size.y)
	if value <= 30:
		c.y += BASE_OFF + stack_idx * STACK
	else:
		c.x -= BASE_OFF + stack_idx * STACK
	_blit(t, c)


func _blit(t: Texture2D, center: Vector2) -> void:
	if t == null:
		return
	draw_texture_rect(t, Rect2(center - Vector2(MK, MK) * 0.5, Vector2(MK, MK)), false)
