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
## trace (opzionale): vi vengono aggiunte righe leggibili sulla logica seguita.
## Restituisce { "result": "op"/"draw"/"flip", "op_id": String }.
static func walk(side: Dictionary, eval: Callable, trace: Array = []) -> Dictionary:
	var flow: Array = side.get("flow", [])
	for node in flow:
		var target: String
		if node.has("cond"):
			var res := bool(eval.call(node))
			target = String(node["t"]) if res else String(node["f"])
			trace.append("• Condizione «%s» = %s → %s" % [String(node["cond"]), ("VERO" if res else "FALSO"), _target_label(target)])
		else:
			target = String(node.get("t", "next"))
			trace.append("• (incondizionata) → %s" % _target_label(target))
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


static func _target_label(t: String) -> String:
	match t:
		"next": return "scendi"
		"draw": return "pesca nuova carta"
		"flip": return "gira la carta"
		_: return "Operazione %s" % (t.substr(3) if t.begins_with("op:") else t)


## Lista Attività Speciali per la faccia, eventualmente specifica del ramo (op scelta).
static func specials_for(side: Dictionary, op_id: String) -> Array:
	if side.has("special_by_branch"):
		var by: Dictionary = side["special_by_branch"]
		return by.get(op_id, [])
	return side.get("special", [])
