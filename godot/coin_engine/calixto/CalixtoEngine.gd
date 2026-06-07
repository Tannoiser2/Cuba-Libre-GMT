class_name CalixtoEngine
extends RefCounted

## Interprete generico (riusabile) del flusso di una faccia-carta Calixto.
## Indipendente dal gioco: valuta le condizioni tramite una Callable fornita dal gioco.
##
## Una faccia-carta ha:
##   "flow": [ {"cond": <key?>, "t": <target>, "f": <target>} ... ]
##   "ops":  { "<id>": {...} }
##   "special" o "special_by_branch": liste di Attività Speciali
## Target: "next" (scendi), "draw" (pesca nuova carta), "flip" (gira), "op:<id>" (Operazione).
## Un nodo senza "cond" va sempre a "t".


## Percorre il flusso. eval = Callable(node: Dictionary) -> bool.
## Restituisce { "result": "op"/"draw"/"flip", "op_id": String }.
static func walk(side: Dictionary, eval: Callable) -> Dictionary:
	var flow: Array = side.get("flow", [])
	for node in flow:
		var target: String
		if node.has("cond"):
			target = String(node["t"]) if bool(eval.call(node)) else String(node["f"])
		else:
			target = String(node.get("t", "next"))
		match target:
			"next":
				continue
			"draw":
				return {"result": "draw", "op_id": ""}
			"flip":
				return {"result": "flip", "op_id": ""}
			_:
				if target.begins_with("op:"):
					return {"result": "op", "op_id": target.substr(3)}
				return {"result": "op", "op_id": target}
	# Caduta in fondo: usa la prima Operazione disponibile (carte incondizionate).
	var ops: Dictionary = side.get("ops", {})
	if not ops.is_empty():
		return {"result": "op", "op_id": ops.keys()[0]}
	return {"result": "draw", "op_id": ""}


## Lista Attività Speciali per la faccia, eventualmente specifica del ramo (op scelta).
static func specials_for(side: Dictionary, op_id: String) -> Array:
	if side.has("special_by_branch"):
		var by: Dictionary = side["special_by_branch"]
		return by.get(op_id, [])
	return side.get("special", [])
