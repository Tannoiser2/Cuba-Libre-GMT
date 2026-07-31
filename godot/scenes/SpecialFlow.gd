class_name SpecialFlow
extends RefCounted

## Macchina a stati delle Attività Speciali: sceglie il bersaglio (uno o più spazi,
## oppure origine + destinazione + numero di cubi) e prepara i parametri per il motore.
##
## Come ActionFlow non conosce la scena e non modifica la partita: `click()`/`confirm()`
## restituiscono `{ok, error, run}` dove `run` — se valorizzato — dice al chiamante
## quale Attività Speciale eseguire e con quali parametri. Così il flusso è collaudabile
## headless e la scena resta un semplice disegnatore.

## Attività con scelte multiple: ogni variante ha il suo id e i suoi parametri.
const VARIANTS := {
	"kidnap": [
		{"id": "kidnap:government", "label": "Sequestro (Governo)", "p": {"target": "government"}},
		{"id": "kidnap:syndicate", "label": "Sequestro (Sindacato)", "p": {"target": "syndicate"}},
	],
	"profit": [
		{"id": "profit:cash", "label": "Profitto (incassa Denaro)", "p": {"mode": "cash"}},
		{"id": "profit:convert", "label": "Profitto (converti in Risorse)", "p": {"mode": "convert"}},
	],
	"bribe": [
		{"id": "bribe:cubes", "label": "Corruzione (cubi)", "p": {"action": "cubes"}},
		{"id": "bribe:guerrillas_remove", "label": "Corruzione (rimuovi Guerriglie)", "p": {"action": "guerrillas_remove"}},
		{"id": "bribe:guerrillas_flip", "label": "Corruzione (gira Guerriglie)", "p": {"action": "guerrillas_flip"}},
		{"id": "bribe:base", "label": "Corruzione (rimuovi Base)", "p": {"action": "base"}},
	],
}

# Passi del flusso.
const STAGE_NONE := ""
const STAGE_POINT := "point"           ## scelta di un singolo spazio bersaglio
const STAGE_REPRISAL := "reprisal"     ## Rappresaglia: spostamento opzionale di 1 Guerriglia
const STAGE_MOVE_FROM := "move_from"   ## Trasporto/Muscle: scelta dell'origine
const STAGE_MOVE_TO := "move_to"       ## Trasporto/Muscle: scelta della destinazione
const STAGE_MOVE_N := "move_count"     ## Trasporto/Muscle: quanti cubi
const STAGE_PROFIT := "profit"         ## Profitto: 1-2 Casinò

var pending := ""            ## id (eventualmente con variante) dell'Attività in corso
var faction := ""
var stage := STAGE_NONE
var valid: Array = []        ## spazi cliccabili in questo passo
var from_id := ""
var move_to := ""
var move_count := 0
var profit_mode := "cash"
var spaces: Array = []       ## Casinò scelti per il Profitto
var reprisal_from := ""
var message := ""
var error := ""

var _gc: Node


func _init(controller: Node) -> void:
	_gc = controller


func _state() -> GameState:
	return _gc.state


func _def() -> GameDef:
	return _gc.game_def


func is_active() -> bool:
	return stage != STAGE_NONE


func highlights() -> Array:
	return valid.duplicate()


func clear() -> void:
	pending = ""
	stage = STAGE_NONE
	valid = []
	from_id = ""
	move_to = ""
	move_count = 0
	spaces = []
	reprisal_from = ""
	message = ""
	error = ""


# ---------------------------------------------------------------------------
# Identità delle varianti
# ---------------------------------------------------------------------------

## Attività di base dietro a un id-variante ("bribe:cubes" -> "bribe").
static func base_of(sa: String) -> String:
	var i := sa.find(":")
	return sa.substr(0, i) if i >= 0 else sa


## Parametri extra di una variante, o {} se non è una variante.
static func variant_params(sa: String) -> Dictionary:
	for v in VARIANTS.get(base_of(sa), []):
		if v["id"] == sa:
			return v["p"]
	return {}


## Etichetta da mostrare (variante o nome base).
static func label_of(sa: String) -> String:
	for v in VARIANTS.get(base_of(sa), []):
		if v["id"] == sa:
			return String(v["label"])
	return CLNames.sa(sa)


## Id effettivo per il motore (l'Imboscata dipende dalla Fazione attiva).
func target_id(sa: String) -> String:
	var base := base_of(sa)
	if base == "ambush":
		return "ambush_m26" if faction == "m26" else "ambush_dr"
	return base


## Parametri per un'Attività a bersaglio singolo su `space`.
func params_for(sa: String, space: String) -> Dictionary:
	var vp := variant_params(sa)
	match base_of(sa):
		"profit":
			if String(vp.get("mode", "cash")) == "convert":
				return {"mode": "convert", "close": [space]}
			return {"mode": "cash", "spaces": [space]}
		"reprisal": return {"space": space, "move": {}}
		"kidnap": return {"space": space, "target": String(vp.get("target", "government"))}
		"bribe": return {"space": space, "action": String(vp.get("action", "cubes"))}
		_: return {"space": space, "faction": faction}


# ---------------------------------------------------------------------------
# Bersagli validi
# ---------------------------------------------------------------------------

## Spazi dove l'Attività a bersaglio singolo ha davvero effetto (simulazione su copia).
func valid_spaces(sa: String) -> Array:
	var out: Array = []
	var sid_id := target_id(sa)
	var st: GameState = _state()
	for s in _def().space_ids():
		# Il Profitto (anche "converti") agisce solo dove c'è un Casinò aperto.
		if base_of(sa) == "profit" and st.space_state(s).count("syndicate", "casino", "open") < 1:
			continue
		if _gc.can_special(sid_id, params_for(sa, s)):
			out.append(s)
	return out


## Origini valide per Trasporto/Muscle (devono avere i pezzi da spostare).
func valid_origins(sa: String) -> Array:
	var out: Array = []
	var st_all: GameState = _state()
	for sid in _def().space_ids():
		var sd: SpaceDef = _def().space(sid)
		var st: SpaceState = st_all.space_state(sid)
		if sa == "transport":
			var from_ok := (sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0)
			if from_ok and st.count("government", "troops") > 0:
				out.append(sid)
		elif sa == "muscle":
			if st.count("government", "police") > 0 or st.count("government", "troops") > 0:
				out.append(sid)
	return out


## Destinazioni valide per Trasporto/Muscle data l'origine scelta.
func valid_dests(sa: String, p_from: String) -> Array:
	var out: Array = []
	var st_all: GameState = _state()
	var from_st: SpaceState = st_all.space_state(p_from)
	for sid in _def().space_ids():
		if sid == p_from:
			continue
		var sd: SpaceDef = _def().space(sid)
		var st: SpaceState = st_all.space_state(sid)
		if sa == "transport":
			out.append(sid)   # qualsiasi spazio
		elif sa == "muscle":
			if not (sd.is_economic() or st.count("syndicate", "casino", "open") > 0):
				continue
			var needed := "police" if sd.type == CoinEnums.SpaceType.CITY else "troops"
			if from_st.count("government", needed) > 0:
				out.append(sid)
	return out


## Massimo di cubi spostabili (Trasporto 3, Muscle 2, comunque non più dei presenti).
func move_max(sa: String, p_from: String, p_to: String) -> int:
	var from_st: SpaceState = _state().space_state(p_from)
	if base_of(sa) == "muscle":
		var dest: SpaceDef = _def().space(p_to)
		var typ := "police" if dest.type == CoinEnums.SpaceType.CITY else "troops"
		return mini(2, from_st.count("government", typ))
	return mini(3, from_st.count("government", "troops"))


## Fazione Insorgente con una Guerriglia da spostare nella Rappresaglia (o "").
func reprisal_movable(sid: String) -> String:
	var st: SpaceState = _state().space_state(sid)
	for f in ["m26", "directorio", "syndicate"]:
		if st.count(f, "guerrilla") > 0:
			return f
	return ""


func reprisal_dests(sid: String) -> Array:
	return Array(_def().space(sid).adjacent)


# ---------------------------------------------------------------------------
# Avvio e passi
# ---------------------------------------------------------------------------

func _fail(msg: String) -> Dictionary:
	error = msg
	message = msg
	return {"ok": false, "error": msg, "run": {}}


func _step(msg: String) -> Dictionary:
	error = ""
	message = msg
	return {"ok": true, "error": "", "run": {}}


func _run(id: String, params: Dictionary) -> Dictionary:
	error = ""
	return {"ok": true, "error": "", "run": {"id": id, "params": params}}


## Avvia l'Attività Speciale scelta. Restituisce false (con `error`) se non è possibile.
func start(sa: String, p_faction: String) -> bool:
	clear()
	faction = p_faction
	var base := base_of(sa)
	var name := label_of(sa)
	if base == "profit":
		var pvalid := valid_spaces(sa)
		if pvalid.is_empty():
			error = "%s: nessun Casinò aperto al momento" % name
			return false
		pending = sa
		profit_mode = String(variant_params(sa).get("mode", "cash"))
		valid = pvalid
		stage = STAGE_PROFIT
		_profit_message()
		return true
	if base == "transport" or base == "muscle":
		var origins := valid_origins(base)
		if origins.is_empty():
			error = "%s: nessuna origine valida al momento" % name
			return false
		pending = sa
		valid = origins
		stage = STAGE_MOVE_FROM
		message = "clicca un'ORIGINE evidenziata, poi la destinazione"
		return true
	var v := valid_spaces(sa)
	if v.is_empty():
		error = "%s: nessuno spazio valido al momento" % name
		return false
	pending = sa
	valid = v
	stage = STAGE_POINT
	message = "clicca uno spazio bersaglio evidenziato"
	return true


## Clic su uno spazio. Vedi la nota in testa per la forma del risultato.
func click(sid: String) -> Dictionary:
	match stage:
		STAGE_POINT: return _click_point(sid)
		STAGE_REPRISAL: return _click_reprisal(sid)
		STAGE_MOVE_FROM: return _click_origin(sid)
		STAGE_MOVE_TO: return _click_dest(sid)
		STAGE_MOVE_N: return _click_count(sid)
		STAGE_PROFIT: return _click_profit(sid)
	return {"ok": false, "error": "", "run": {}}


func _click_point(sid: String) -> Dictionary:
	if not valid.has(sid):
		return _fail("%s: spazio non valido, scegline uno evidenziato" % label_of(pending))
	# Rappresaglia: dopo il bersaglio si può spostare 1 Guerriglia in uno spazio adiacente.
	if base_of(pending) == "reprisal" and reprisal_movable(sid) != "" and not reprisal_dests(sid).is_empty():
		reprisal_from = sid
		valid = reprisal_dests(sid)
		valid.append(sid)   # ri-cliccare il bersaglio = non spostare
		stage = STAGE_REPRISAL
		var nm: String = _def().space(sid).name
		return _step("Rappresaglia a %s - clicca uno spazio ADIACENTE per spostarci 1 Guerriglia, oppure riclicca %s per non spostare" % [nm, nm])
	return _run(target_id(pending), params_for(pending, sid))


func _click_reprisal(sid: String) -> Dictionary:
	if sid == reprisal_from:
		return _run("reprisal", {"space": reprisal_from, "move": {}})
	if not valid.has(sid):
		return _fail("Spostamento non valido: scegli uno spazio adiacente evidenziato")
	return _run("reprisal", {"space": reprisal_from,
		"move": {"faction": reprisal_movable(reprisal_from), "to": sid}})


func _click_origin(sid: String) -> Dictionary:
	if not valid.has(sid):
		return _fail("Origine non valida: scegline una evidenziata")
	from_id = sid
	valid = valid_dests(base_of(pending), sid)
	var nm: String = _def().space(sid).name
	if valid.is_empty():
		stage = STAGE_MOVE_TO
		return _step("Nessuna destinazione valida da %s - Annulla per cambiare" % nm)
	stage = STAGE_MOVE_TO
	return _step("Origine: %s - clicca una DESTINAZIONE evidenziata" % nm)


func _click_dest(sid: String) -> Dictionary:
	if not valid.has(sid):
		return _fail("Destinazione non valida: scegline una evidenziata")
	move_to = sid
	move_count = move_max(pending, from_id, sid)
	valid = [sid]
	stage = STAGE_MOVE_N
	_move_message()
	return {"ok": true, "error": "", "run": {}}


## Ri-cliccare la destinazione cicla il numero di cubi da spostare.
func _click_count(sid: String) -> Dictionary:
	if sid != move_to:
		return {"ok": false, "error": "", "run": {}}
	var mx := move_max(pending, from_id, move_to)
	move_count = (move_count % mx) + 1 if mx > 0 else 0
	_move_message()
	return {"ok": true, "error": "", "run": {}}


func _click_profit(sid: String) -> Dictionary:
	if not valid.has(sid):
		return _fail("Profitto: scegli uno spazio con Casinò aperto evidenziato")
	if spaces.has(sid):
		spaces.erase(sid)
	elif profit_mode == "cash" and spaces.size() >= 2:
		return _fail("Profitto (incassa): massimo 2 spazi")
	else:
		spaces.append(sid)
	_profit_message()
	return {"ok": true, "error": "", "run": {}}


## Conferma il passo che richiede "Esegui" (numero di cubi, oppure Casinò del Profitto).
func confirm() -> Dictionary:
	if stage == STAGE_MOVE_N:
		if move_count <= 0:
			return _fail("Nessun cubo da spostare")
		var p := {"from": from_id, "to": move_to, "count": move_count}
		if base_of(pending) == "muscle":
			var dest: SpaceDef = _def().space(move_to)
			p["type"] = "police" if dest.type == CoinEnums.SpaceType.CITY else "troops"
		return _run(base_of(pending), p)
	if stage == STAGE_PROFIT:
		if spaces.is_empty():
			return _fail("Profitto: scegli almeno 1 Casinò")
		var pp := {"mode": profit_mode}
		if profit_mode == "cash":
			pp["spaces"] = spaces.duplicate()
		else:
			pp["close"] = spaces.duplicate()
		return _run("profit", pp)
	return {"ok": false, "error": "", "run": {}}


func _move_message() -> void:
	message = "%s: sposta %d da %s a %s - riclicca la destinazione per cambiare numero, poi 'Esegui'" % [
		label_of(pending), move_count, _def().space(from_id).name, _def().space(move_to).name]


func _profit_message() -> void:
	var names: Array = []
	for s in spaces:
		names.append(_def().space(s).name)
	var verb := "incassa Denaro in" if profit_mode == "cash" else "converti (chiudi)"
	message = "Profitto: %s %s - poi 'Esegui'" % [verb, ", ".join(names) if not names.is_empty() else "(scegli i Casinò)"]
