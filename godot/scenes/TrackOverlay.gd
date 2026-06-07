class_name TrackOverlay
extends Control

## Disegna i segnalini originali sui tracciati di bordo mappa: cilindri Risorse delle 4
## Fazioni, Aiuti, i 4 marcatori di vittoria sul tracciato perimetrale 0–49, e il marcatore
## dell'Alleanza USA nella sua casella. I segnalini con lo stesso valore vengono sfalsati.

const BASE_OFF := 2.0    # i segnalini stanno sulla riga dei numeri (non nei riquadri sotto)
const STACK := 14.0      # scostamento per segnalini sulla stessa cella
const MK := 24.0         # dimensione segnalino


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

	_draw_available(s)
	_draw_eligibility(s)


# Riquadri "Available Forces": origine (normalizzata) della riga "pezzo + xN" per fazione.
const AVAIL := {
	"government": {"types": ["troops", "police", "base"], "o": [0.27, 0.135]},
	"syndicate": {"types": ["guerrilla", "casino"], "o": [0.625, 0.115]},
	"directorio": {"types": ["guerrilla", "base"], "o": [0.025, 0.885]},
	"m26": {"types": ["guerrilla", "base"], "o": [0.655, 0.90]},
}
const AV_PC := 20.0   # dimensione pezzo in riserva
const AV_STEP := 62.0 # passo orizzontale tra i tipi


func _draw_available(s: GameState) -> void:
	var font := ThemeDB.fallback_font
	for fid in AVAIL:
		var cfg: Dictionary = AVAIL[fid]
		var x: float = cfg["o"][0] * size.x
		var y: float = cfg["o"][1] * size.y
		for t in cfg["types"]:
			var n := s.available(fid, t)
			if n <= 0:
				continue
			var st := "closed" if t == "casino" else ("underground" if t == "guerrilla" else "")
			var tex := CLAssets.piece(fid, t, st)
			if tex != null:
				draw_texture_rect(tex, Rect2(Vector2(x, y), Vector2(AV_PC, AV_PC)), false)
			var label := "x%d" % n
			var lp := Vector2(x + AV_PC + 3, y + AV_PC - 3)
			draw_string(font, lp + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
			draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			x += AV_STEP


# Sequenza di Gioco: colonne Disponibili / Non Disponibili (cilindri fazione).
const ELIG_OK := [0.225, 0.60]
const ELIG_NO := [0.44, 0.60]
const ELIG_STEP := 26.0
const ELIG_SZ := 22.0


func _draw_eligibility(s: GameState) -> void:
	var ok := 0
	var no := 0
	for fid in ["government", "m26", "directorio", "syndicate"]:
		var elig: bool = int(s.eligibility.get(fid, 0)) == 0  # 0 = ELIGIBLE
		var base: Array = ELIG_OK if elig else ELIG_NO
		var idx := ok if elig else no
		var c := Vector2(base[0] * size.x, base[1] * size.y + idx * ELIG_STEP)
		var t := CLAssets.res_token(fid)
		if t != null:
			draw_texture_rect(t, Rect2(c, Vector2(ELIG_SZ, ELIG_SZ)), false)
		if elig: ok += 1
		else: no += 1



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
