class_name BotBrain
extends RefCounted

## Interfaccia generica per l'IA di una Fazione Non-Giocatore in un gioco COIN.
## Un gioco implementa questa classe traducendo i propri flowchart deterministici.

## Esegue il turno della Fazione Non-Giocatore con la carta corrente.
## Restituisce { "ok": bool, "action": String, "log": Array }.
func take_turn(faction: String) -> Dictionary:
	push_error("BotBrain.take_turn() non implementato")
	return {"ok": false, "action": "none", "log": []}
