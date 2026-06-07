class_name CalixtoDeck
extends RefCounted

## Mazzo Calixto generico (riusabile tra giochi COIN). Contiene le lettere-carta di ogni
## Fazione NP. La pesca (C8.5.3): sposta in fondo le carte una a una finché in cima c'è una
## carta della Fazione attiva; quella resta in cima finché serve pescarne una nuova. Rimescolo
## solo a inizio partita e nel Reset di Propaganda.

var _cards: Array[Dictionary] = []   # {"faction": String, "letter": String}
var _rng: RandomNumberGenerator


func _init(letters_by_faction: Dictionary, rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		_rng.randomize()
	for fid in letters_by_faction:
		for letter in letters_by_faction[fid]:
			_cards.append({"faction": fid, "letter": String(letter)})
	shuffle()


func shuffle() -> void:
	for i in range(_cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = _cards[i]; _cards[i] = _cards[j]; _cards[j] = tmp


func size() -> int:
	return _cards.size()


## Porta in cima la prossima carta della Fazione indicata e ne restituisce la lettera.
## Le carte scartate vanno in fondo (a faccia in su). Restituisce "" se nessuna carta.
func draw_for(faction: String) -> String:
	var guard := 0
	while guard < _cards.size() + 1:
		guard += 1
		if _cards.is_empty():
			return ""
		if _cards[0]["faction"] == faction:
			return _cards[0]["letter"]
		_cards.append(_cards.pop_front())
	return ""


## Scarta la carta in cima (in fondo) e pesca la successiva della stessa Fazione.
func draw_next(faction: String) -> String:
	if not _cards.is_empty():
		_cards.append(_cards.pop_front())
	return draw_for(faction)
