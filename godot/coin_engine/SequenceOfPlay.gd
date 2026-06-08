class_name SequenceOfPlay
extends RefCounted

## Macchina a stati per la risoluzione di UNA carta Evento secondo la sequenza
## standard della serie COIN (cap. 2 di Cuba Libre):
##
##  - Le Fazioni Disponibili agiscono nell'ordine stampato sulla carta.
##  - La 1ª Disponibile sceglie: Passa / Operazione / Operazione+Att.Speciale / Evento.
##  - La 2ª Disponibile ha opzioni dipendenti da cosa ha fatto la 1ª:
##      1ª Op       -> 2ª: Operazione Limitata
##      1ª Op+SA    -> 2ª: Evento
##      1ª Evento   -> 2ª: Operazione (con eventuale Att.Speciale)
##  - Passare dà Risorse e lascia la Fazione Disponibile per la carta seguente.
##  - A fine carta: chi ha agito -> Non Disponibile, gli altri -> Disponibili.
##
## L'ESECUZIONE concreta di Operazioni/Eventi è demandata al chiamante; questa classe
## gestisce solo il flusso, la disponibilità, il Passare e l'avanzamento della carta.

const A := CoinEnums.ActionType

var state: GameState
var module: RulesModule
var card: CardDef

var _eligible_order: PackedStringArray = PackedStringArray()  ## fazioni Disponibili, in ordine carta
var _idx: int = 0                       ## puntatore nella lista ordinata
var _actors: PackedStringArray = PackedStringArray()          ## fazioni che hanno agito (Op/Evento)
var _passers: PackedStringArray = PackedStringArray()         ## fazioni che hanno Passato
var _first_action: int = -1             ## ActionType della 1ª Fazione che ha agito
var _done: bool = false
## Solo Operazioni Limitate consentite (Carta Evento Finale, 2.3.9).
var final_event_card: bool = false


func _init(p_state: GameState, p_module: RulesModule, p_card: CardDef) -> void:
	state = p_state
	module = p_module
	card = p_card
	_build_eligible_order()


func _build_eligible_order() -> void:
	_eligible_order.clear()
	for fid in card.faction_order:
		if state.eligibility.get(fid, CoinEnums.Eligibility.ELIGIBLE) == CoinEnums.Eligibility.ELIGIBLE:
			_eligible_order.append(fid)


# ---------------------------------------------------------------------------
# Interrogazione dello stato corrente
# ---------------------------------------------------------------------------

func is_done() -> bool:
	return _done


## Fazione la cui decisione è in sospeso ("" se la carta è conclusa).
func pending_faction() -> String:
	if _done or _idx >= _eligible_order.size():
		return ""
	return _eligible_order[_idx]


## Indica se la Fazione in sospeso è la 1ª (true) o la 2ª (false) ad agire.
func is_first_slot() -> bool:
	return _actors.is_empty()


## ActionType della 1ª Fazione che ha agito (-1 se nessuna). Per la tabella C8.5.2.
func first_action() -> int:
	return _first_action


## Fazione Disponibile successiva a quella in sospeso ("" se non c'è).
func next_eligible() -> String:
	if _idx + 1 < _eligible_order.size():
		return _eligible_order[_idx + 1]
	return ""


## Azioni legali per la Fazione in sospeso.
func legal_actions() -> Array[int]:
	var out: Array[int] = []
	if pending_faction() == "":
		return out
	out.append(A.PASS)
	if is_first_slot():
		# 1ª Disponibile
		if final_event_card:
			out.append(A.LIMITED_OPERATION)
		else:
			out.append(A.OPERATION)
			out.append(A.OPERATION_WITH_SPECIAL)
			out.append(A.EVENT)
	else:
		# 2ª Disponibile: dipende dall'azione della 1ª
		if final_event_card:
			out.append(A.LIMITED_OPERATION)
		else:
			match _first_action:
				A.OPERATION:
					out.append(A.LIMITED_OPERATION)
				A.OPERATION_WITH_SPECIAL:
					out.append(A.EVENT)
				A.EVENT:
					out.append(A.OPERATION)
					out.append(A.OPERATION_WITH_SPECIAL)
				_:
					out.append(A.LIMITED_OPERATION)
	return out


func is_legal(action: int) -> bool:
	return legal_actions().has(action)


# ---------------------------------------------------------------------------
# Applicazione delle decisioni
# ---------------------------------------------------------------------------

## Casella della Sequenza di Gioco dove mostrare il cilindro di ogni Fazione (per la UI).
var action_box: Dictionary = {}


## La Fazione in sospeso Passa: riceve Risorse e resta Disponibile.
func act_pass() -> bool:
	var fid := pending_faction()
	if fid == "" or not is_legal(A.PASS):
		return false
	state.add_resources(fid, module.pass_resources(fid))
	_passers.append(fid)
	action_box[fid] = "pass"
	_idx += 1
	_check_done()
	return true


## La Fazione in sospeso svolge un'azione (Operazione/Evento/...). L'effetto concreto
## è gestito dal chiamante; qui si registra l'azione e si aggiorna il flusso.
func act(action: int) -> bool:
	var fid := pending_faction()
	if fid == "" or action == A.PASS or not is_legal(action):
		return false
	var first := is_first_slot()
	if first:
		_first_action = action
	action_box[fid] = _box_for(action, first)
	_actors.append(fid)
	_idx += 1
	# Dopo 2 Fazioni che hanno agito, la carta è conclusa.
	if _actors.size() >= 2:
		_done = true
	else:
		_check_done()
	return true


func _box_for(action: int, first: bool) -> String:
	if first:
		match action:
			A.OPERATION: return "1st_op_only"
			A.OPERATION_WITH_SPECIAL: return "1st_op_sa"
			A.EVENT: return "1st_event"
			_: return "1st_op_only"
	match action:
		A.LIMITED_OPERATION: return "2nd_limop"
		A.EVENT: return "2nd_limop_or_event"
		_: return "2nd_op_sa"


func _check_done() -> void:
	if _idx >= _eligible_order.size():
		_done = true


# ---------------------------------------------------------------------------
# Chiusura della carta: aggiornamento della Disponibilità (2.3.7)
# ---------------------------------------------------------------------------

func finish() -> void:
	for f in state.game_def.factions:
		if _actors.has(f.id):
			state.eligibility[f.id] = CoinEnums.Eligibility.INELIGIBLE
		else:
			state.eligibility[f.id] = CoinEnums.Eligibility.ELIGIBLE
	_done = true


## Istantanea dello stato interno (per Annulla/undo). Vedi restore_snapshot().
func snapshot() -> Dictionary:
	return {
		"eligible_order": Array(_eligible_order),
		"idx": _idx,
		"actors": Array(_actors),
		"passers": Array(_passers),
		"first_action": _first_action,
		"done": _done,
		"final_event_card": final_event_card,
		"action_box": action_box.duplicate(true),
	}


func restore_snapshot(d: Dictionary) -> void:
	_eligible_order = PackedStringArray(d.get("eligible_order", []))
	_idx = int(d.get("idx", 0))
	_actors = PackedStringArray(d.get("actors", []))
	_passers = PackedStringArray(d.get("passers", []))
	_first_action = int(d.get("first_action", -1))
	_done = bool(d.get("done", false))
	final_event_card = bool(d.get("final_event_card", false))
	action_box = (d.get("action_box", {}) as Dictionary).duplicate(true)


func actors() -> PackedStringArray:
	return _actors


func passers() -> PackedStringArray:
	return _passers
