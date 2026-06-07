class_name RulesModule
extends RefCounted

## Interfaccia che ogni gioco della serie COIN implementa per il motore generico.
## Un modulo costruisce la GameDef, prepara lo stato iniziale e definisce le metriche
## di vittoria specifiche del gioco.

## Costruisce e restituisce la definizione (immutabile) del gioco.
func build_game_def() -> GameDef:
	push_error("RulesModule.build_game_def() non implementato")
	return null


## Applica uno scenario/schieramento iniziale a un GameState appena creato.
func apply_setup(state: GameState, scenario_id: String = "standard") -> void:
	push_error("RulesModule.apply_setup() non implementato")


## Restituisce { faction_id: { "value": int, "threshold": int, "margin": int, "won": bool } }.
func victory_status(state: GameState) -> Dictionary:
	return {}


## Ordine di risoluzione delle parità (id Fazione dal vincente al perdente in caso di pari margine).
func tiebreak_order() -> PackedStringArray:
	return PackedStringArray()


## Risorse ottenute da una Fazione quando Passa (default +1; alcuni giochi differiscono).
func pass_resources(faction: String) -> int:
	return 1
