extends Node

## Singleton (autoload) che incapsula il motore di gioco e lo espone alla UI.
## Mantiene il modulo, lo stato e le classi di regole, ed emette segnali quando lo
## stato cambia, così che le viste possano aggiornarsi.

signal state_changed
signal action_logged(text: String)

var module: CubaLibreModule
var game_def: GameDef
var state: GameState
var ops: CubaLibreOperations
var specials: CubaLibreSpecials
var propaganda: CubaLibrePropaganda


func _ready() -> void:
	new_game()


## Avvia una nuova partita con lo schieramento standard.
func new_game(scenario: String = "standard") -> void:
	module = CubaLibreModule.new()
	game_def = module.build_game_def()
	state = GameState.new(game_def)
	module.apply_setup(state, scenario)
	ops = CubaLibreOperations.new(state, module)
	specials = CubaLibreSpecials.new(state, module)
	propaganda = CubaLibrePropaganda.new(state, module)
	emit_signal("state_changed")


## Esegue un'Operazione per id e ne propaga il risultato/log.
func run_operation(op_id: String, params: Dictionary) -> Dictionary:
	var res: Dictionary
	match op_id:
		"train": res = ops.train(params)
		"garrison": res = ops.garrison(params)
		"sweep": res = ops.sweep(params)
		"assault": res = ops.assault(params)
		"rally": res = ops.rally(params)
		"march": res = ops.march(params)
		"attack": res = ops.attack(params)
		"terror": res = ops.terror(params)
		"build": res = ops.build(params)
		_: res = {"ok": false, "error": "Operazione sconosciuta: %s" % op_id, "log": []}
	_emit_result(res)
	return res


func run_special(sa_id: String, params: Dictionary) -> Dictionary:
	var res: Dictionary
	match sa_id:
		"transport": res = specials.transport(params)
		"air_strike": res = specials.air_strike(params)
		"reprisal": res = specials.reprisal(params)
		"infiltrate": res = specials.infiltrate(params)
		"ambush_m26": res = specials.ambush("m26", params)
		"kidnap": res = specials.kidnap(params)
		"subvert": res = specials.subvert(params)
		"ambush_dr": res = specials.ambush("directorio", params)
		"assassinate": res = specials.assassinate(params)
		"profit": res = specials.profit(params)
		"muscle": res = specials.muscle(params)
		"bribe": res = specials.bribe(params)
		_: res = {"ok": false, "error": "Attività speciale sconosciuta: %s" % sa_id, "log": []}
	_emit_result(res)
	return res


func run_propaganda(params: Dictionary = {}) -> Dictionary:
	var res := propaganda.run(params)
	for line in res.get("log", []):
		emit_signal("action_logged", line)
	emit_signal("state_changed")
	return res


func _emit_result(res: Dictionary) -> void:
	if res.get("ok", false):
		for line in res.get("log", []):
			emit_signal("action_logged", String(line))
		emit_signal("state_changed")
	else:
		emit_signal("action_logged", "⚠ " + String(res.get("error", "errore")))


# --- Helper di lettura per la UI ---

func victory() -> Dictionary:
	return module.victory_status(state)


func faction_color(fid: String) -> Color:
	match fid:
		"government": return Color("3a6ea5")
		"m26": return Color("c0392b")
		"directorio": return Color("d4ac0d")
		"syndicate": return Color("27ae60")
		_: return Color.WHITE
