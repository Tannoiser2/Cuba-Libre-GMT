class_name ActionFlow
extends RefCounted

## Pianificazione dell'Operazione in preparazione: quali spazi sono stati scelti e con
## quale variante (cubi/Base/Civica per l'Addestramento, bersaglio per l'Attacco, ecc.),
## più la coda degli spostamenti nelle Operazioni a trascinamento.
##
## NON conosce la scena: non tocca viste, non colora nulla, non legge nodi. Espone lo
## stato, il testo da mostrare e i parametri per il motore; la scena si limita a
## disegnare `highlights()` e `message`. Questo la rende collaudabile headless.

# Operazioni "a spazi" (clic) contro operazioni "a spostamento" (trascinamento).
const OP_KIND := {
	"train": "space_list", "assault": "space_list", "rally": "space_list",
	"attack": "space_list", "terror": "space_list", "build": "space_list",
	"sweep": "moves", "garrison": "moves", "march": "moves",
}

var faction := ""                  ## Fazione che sta agendo
var op := ""                       ## Operazione scelta ("" = nessuna)
var kind := ""                     ## "space_list" | "moves"
var limited := false               ## Op Limitata: un solo spazio, niente Att.Speciale
var message := ""                  ## testo da mostrare (istruzione o riepilogo)
var error := ""                    ## motivo dell'ultimo rifiuto ("" se nessuno)

var selected: Array = []           ## spazi scelti, in ordine
var moves: Array = []              ## [{from, to, count, type}] in coda
var rally_choice: Dictionary = {}  ## sid -> "place"/"extra"/"base"/"flip"
var train_plan: Dictionary = {}    ## sid -> {kind: "cubes"/"base"/"civic", n: int}
var build_choice: Dictionary = {}  ## sid -> "new"/"open"
var attack_target: Dictionary = {} ## sid -> Fazione bersaglio
var garrison_ec := ""              ## EC scelto per l'Assalto gratuito della Guarnigione
var sweep_assault := ""            ## spazio dell'Assalto gratuito (Momentum Masferrer)

var _gc: Node                      ## GameController (stato, definizioni, modulo)


func _init(controller: Node) -> void:
	_gc = controller


func _state() -> GameState:
	return _gc.state


func _def() -> GameDef:
	return _gc.game_def


func is_idle() -> bool:
	return op == ""


func has_plan() -> bool:
	return not selected.is_empty() or not moves.is_empty()


## Avvia un'Operazione. Restituisce false (con `error`) se non è efficace da nessuna parte.
func start(op_id: String, p_faction: String, p_limited: bool) -> bool:
	error = ""
	# La Fazione deve avere quell'Operazione: nella scena i tasti nascono già dalle
	# operazioni della Fazione, ma qui la condizione va verificata comunque.
	var fd: FactionDef = _def().faction(p_faction)
	if fd != null and not Array(fd.operations).has(op_id):
		error = "%s non dispone dell'Operazione %s" % [_gc.faction_name(p_faction), CLNames.op(op_id)]
		message = error
		return false
	var k := String(OP_KIND.get(op_id, "space_list"))
	var valid := valid_spaces(p_faction, op_id)
	if k == "space_list" and valid.is_empty():
		error = "%s: nessuno spazio dove sia efficace al momento" % CLNames.op(op_id)
		message = error
		return false
	clear()
	faction = p_faction
	op = op_id
	kind = k
	limited = p_limited
	return true


## Azzera la pianificazione (senza annullare nulla di già eseguito).
func clear() -> void:
	op = ""
	kind = ""
	limited = false
	message = ""
	error = ""
	selected.clear()
	moves.clear()
	rally_choice.clear()
	train_plan.clear()
	build_choice.clear()
	attack_target.clear()
	garrison_ec = ""
	sweep_assault = ""


## Spazi da evidenziare: quelli dove l'Operazione è efficace, più quelli già scelti.
func highlights() -> Array:
	if op == "":
		return []
	var out := valid_spaces(faction, op)
	for sid in selected:
		if not out.has(sid):
			out.append(sid)
	return out


# ---------------------------------------------------------------------------
# Clic su uno spazio: seleziona, oppure cicla la variante e infine deseleziona
# ---------------------------------------------------------------------------

## Restituisce true se il clic è stato accettato; in caso contrario `error` spiega perché.
func click(sid: String) -> bool:
	error = ""
	match op:
		"rally": return _rally_click(sid)
		"train": return _train_click(sid)
		"attack": return _attack_click(sid)
		"build": return _build_click(sid)
	# Guarnigione (trascinamento): il clic su un EC sceglie l'Assalto gratuito.
	if op == "garrison" and kind == "moves":
		if not _def().space(sid).is_economic():
			error = "Guarnigione: l'Assalto gratuito può avvenire solo in un EC"
			return false
		garrison_ec = "" if garrison_ec == sid else sid
		var nm: String = _def().space(sid).name
		message = ("Guarnigione: Assalto gratuito a %s - trascina i cubi e 'Esegui'" % nm) \
			if garrison_ec != "" else "Guarnigione: Assalto in EC annullato"
		return true
	# Perlustrazione + Momentum Masferrer: clic per l'Assalto gratuito.
	if op == "sweep" and kind == "moves" and _gc.module.has_momentum(_state(), "Rolando Masferrer"):
		sweep_assault = "" if sweep_assault == sid else sid
		var snm: String = _def().space(sid).name
		message = ("Masferrer: Assalto gratuito a %s - poi 'Esegui'" % snm) \
			if sweep_assault != "" else "Masferrer: Assalto gratuito annullato"
		return true
	if kind != "space_list":
		return false
	# Selezione semplice (Assalto, Terrorismo).
	if selected.has(sid):
		selected.erase(sid)
	else:
		if not valid_spaces(faction, op).has(sid):
			error = "%s: qui non è efficace, scegli uno spazio evidenziato" % CLNames.op(op)
			return false
		_enforce_limited()
		selected.append(sid)
	message = "Selezionati: %s" % ", ".join(_names(selected))
	return true


## Op Limitata: un solo spazio: scegliendone un altro il precedente decade.
func _enforce_limited() -> void:
	if limited and selected.size() >= 1:
		selected.clear()
		rally_choice.clear()
		train_plan.clear()
		build_choice.clear()
		attack_target.clear()


func _names(ids: Array) -> Array:
	var out: Array = []
	for sid in ids:
		out.append(_def().space(sid).name)
	return out


# ---- Riorganizzazione (Rally) ----

## Azioni possibili in uno spazio (la 1ª è il default).
func rally_options(sid: String) -> Array:
	var st: SpaceState = _state().space_state(sid)
	var has_base := st.count(faction, "base") > 0
	var opts: Array = ["extra"] if has_base else ["place"]
	if st.count(faction, "guerrilla") >= 2 and _gc.module.can_place_base(_state(), sid, false):
		opts.append("base")   # sostituisci 2 Guerriglie con 1 Base
	if has_base and st.count(faction, "guerrilla", "active") > 0:
		opts.append("flip")   # gira le Guerriglie Clandestine
	return opts


func _rally_click(sid: String) -> bool:
	if not selected.has(sid):
		if not valid_spaces(faction, "rally").has(sid):
			error = "Riorganizzazione: qui non è efficace, scegli uno spazio evidenziato"
			return false
		_enforce_limited()
		selected.append(sid)
		rally_choice[sid] = rally_options(sid)[0]
	else:
		var opts := rally_options(sid)
		var i := opts.find(String(rally_choice.get(sid, opts[0])))
		if i + 1 < opts.size():
			rally_choice[sid] = opts[i + 1]   # azione successiva
		else:
			selected.erase(sid)               # dopo l'ultima: deseleziona
			rally_choice.erase(sid)
	var parts: Array = []
	for s in selected:
		parts.append("%s [%s]" % [_def().space(s).name, CLNames.RALLY.get(rally_choice.get(s, "place"), "?")])
	message = "Riorganizza: %s - riclicca uno spazio per cambiare azione, poi 'Esegui'" % ", ".join(parts) \
		if not parts.is_empty() else "Riorganizzazione: clicca gli spazi"
	return true


# ---- Attacco: bersaglio (Fazione) per ogni spazio ----

func attack_enemies(sid: String) -> Array:
	var st: SpaceState = _state().space_state(sid)
	var out: Array = []
	for ff in ["m26", "directorio", "syndicate", "government"]:
		if ff == faction:
			continue
		if st.count(ff, "guerrilla") + st.count(ff, "troops") + st.count(ff, "police") \
				+ st.count(ff, "base") + st.count(ff, "casino", "open") > 0:
			out.append(ff)
	return out


func _attack_click(sid: String) -> bool:
	if not selected.has(sid):
		if not valid_spaces(faction, "attack").has(sid):
			error = "Attacco: serve una tua Guerriglia e un nemico - scegli uno spazio evidenziato"
			return false
		_enforce_limited()
		selected.append(sid)
		var en := attack_enemies(sid)
		attack_target[sid] = en[0] if not en.is_empty() else ""
	else:
		var en := attack_enemies(sid)
		var i := en.find(String(attack_target.get(sid, "")))
		if i + 1 < en.size():
			attack_target[sid] = en[i + 1]
		else:
			selected.erase(sid)
			attack_target.erase(sid)
	var parts: Array = []
	for s in selected:
		parts.append("%s -> %s" % [_def().space(s).name, _gc.faction_name(String(attack_target.get(s, "")))])
	message = "Attacco: %s - riclicca uno spazio per cambiare bersaglio, poi 'Esegui'" % ", ".join(parts) \
		if not parts.is_empty() else "Attacco: clicca gli spazi"
	return true


# ---- Addestramento (Train): cubi per spazio + 1 azione speciale (Base/Civica) ----

func train_base_ok(sid: String) -> bool:
	var st: SpaceState = _state().space_state(sid)
	return st.count("government", "troops") + st.count("government", "police") >= 2 \
		and _gc.module.can_place_base(_state(), sid, false)


func train_civic_ok(sid: String) -> bool:
	var st: SpaceState = _state().space_state(sid)
	return st.control == "government" and st.count("government", "troops") > 0 \
		and st.count("government", "police") > 0


## Lo spazio che già ospita la singola Att. speciale di Train (Base/Civica), o "".
func train_special_owner(exclude: String) -> String:
	for s in train_plan:
		if s != exclude and String(train_plan[s].get("kind", "cubes")) in ["base", "civic"]:
			return s
	return ""


func _train_click(sid: String) -> bool:
	if not selected.has(sid):
		if not valid_spaces(faction, "train").has(sid):
			error = "Addestramento: scegli una Città o uno spazio con una Base del Governo"
			return false
		_enforce_limited()
		selected.append(sid)
		train_plan[sid] = {"kind": "cubes", "n": 1}
	else:
		var p: Dictionary = train_plan[sid]
		var pkind := String(p["kind"])
		if pkind == "cubes" and int(p["n"]) < 4:
			p["n"] = int(p["n"]) + 1
		elif pkind == "cubes":
			# Una sola Att. speciale per Addestramento.
			if train_special_owner(sid) == "" and train_base_ok(sid):
				p["kind"] = "base"
			elif train_special_owner(sid) == "" and train_civic_ok(sid):
				p["kind"] = "civic"
			else:
				_train_drop(sid)
		elif pkind == "base":
			if train_civic_ok(sid):
				p["kind"] = "civic"
			else:
				_train_drop(sid)
		else:
			_train_drop(sid)
	_train_message()
	return true


func _train_drop(sid: String) -> void:
	selected.erase(sid)
	train_plan.erase(sid)


func _train_message() -> void:
	var parts: Array = []
	for s in selected:
		var p: Dictionary = train_plan.get(s, {"kind": "cubes", "n": 1})
		var nm: String = _def().space(s).name
		match String(p["kind"]):
			"base": parts.append("%s [Base]" % nm)
			"civic": parts.append("%s [Civica]" % nm)
			_:
				var typ := "Polizia" if _def().space(s).type == CoinEnums.SpaceType.CITY else "Truppe"
				parts.append("%s [%d %s]" % [nm, int(p["n"]), typ])
	message = "Addestramento: %s - riclicca per +cubo / Base / Civica, poi 'Esegui'" % ", ".join(parts) \
		if not parts.is_empty() else "Addestramento: clicca gli spazi"


# ---- Costruzione (Build, Sindacato) ----

func build_options(sid: String) -> Array:
	var st: SpaceState = _state().space_state(sid)
	var opts: Array = []
	if st.count("syndicate", "casino", "closed") > 0:
		opts.append("open")
	if _gc.module.can_place_base(_state(), sid, true):
		opts.append("new")
	return opts if not opts.is_empty() else ["new"]


func _build_click(sid: String) -> bool:
	if not selected.has(sid):
		if not valid_spaces(faction, "build").has(sid):
			error = "Costruzione: scegli uno spazio con Controllo Govt o Sindacato"
			return false
		_enforce_limited()
		selected.append(sid)
		build_choice[sid] = build_options(sid)[0]
	else:
		var opts := build_options(sid)
		var i := opts.find(String(build_choice.get(sid, opts[0])))
		if i + 1 < opts.size():
			build_choice[sid] = opts[i + 1]
		else:
			selected.erase(sid)
			build_choice.erase(sid)
	var parts: Array = []
	for s in selected:
		var lbl := "apri Casinò" if String(build_choice.get(s, "new")) == "open" else "nuovo Casinò"
		parts.append("%s [%s]" % [_def().space(s).name, lbl])
	message = "Costruzione: %s - riclicca per cambiare, poi 'Esegui'" % ", ".join(parts) \
		if not parts.is_empty() else "Costruzione: clicca gli spazi"
	return true


# ---------------------------------------------------------------------------
# Spostamenti in coda (Operazioni a trascinamento)
# ---------------------------------------------------------------------------

## Accoda lo spostamento di 1 pezzo. Restituisce false se non siamo in modalità movimento.
func queue_move(from_id: String, to_id: String, type: String) -> bool:
	error = ""
	if kind != "moves":
		error = "Per spostare i pezzi scegli prima un'operazione di movimento (Marcia / Perlustrazione / Guarnigione)"
		return false
	if from_id == to_id:
		return false
	moves.append({"from": from_id, "to": to_id, "count": 1, "type": type})
	message = "In coda (%d): 1 %s da %s -> %s - poi 'Esegui'" % [
		moves.size(), CLNames.piece(type), _def().space(from_id).name, _def().space(to_id).name]
	return true


## Spostamenti extra consentiti dal Momentum "Armored Cars" verso gli spazi d'Assalto.
func queue_assault_move(from_id: String, to_id: String) -> bool:
	error = ""
	if not selected.has(to_id):
		error = "Armored Cars: trascina le Truppe in uno spazio già scelto per l'Assalto"
		return false
	moves.append({"from": from_id, "to": to_id, "count": 1, "type": "troops"})
	message = "Armored Cars: %d Truppe verso gli spazi d'Assalto - poi 'Esegui'" % moves.size()
	return true


# ---------------------------------------------------------------------------
# Parametri per il motore
# ---------------------------------------------------------------------------

func build_params() -> Dictionary:
	match op:
		"sweep":
			var dests := {}
			for m in moves:
				dests[m["to"]] = true
			var sp := {"spaces": dests.keys(), "moves": moves}
			if sweep_assault != "":
				sp["assault_space"] = sweep_assault   # Momentum Masferrer
			return sp
		"garrison":
			var gp := {"moves": moves}
			if garrison_ec != "":
				gp["assault_ec"] = garrison_ec
			return gp
		"march":
			return {"faction": faction, "moves": moves}
		"rally":
			return {"faction": faction, "spaces": selected, "choices": rally_choice.duplicate()}
		"attack":
			return {"faction": faction, "spaces": selected, "targets": attack_target.duplicate()}
		"terror":
			return {"faction": faction, "spaces": selected}
		"assault":
			var ap := {"spaces": selected}
			if not moves.is_empty():
				ap["moves"] = moves.duplicate()        # Momentum Armored Cars
			return ap
		"build":
			return {"spaces": selected, "choices": build_choice.duplicate()}
		"train":
			var place := {}
			var special := {}
			for sid in selected:
				var p: Dictionary = train_plan.get(sid, {"kind": "cubes", "n": 1})
				match String(p["kind"]):
					"base": special = {"type": "base", "space": sid}
					"civic": special = {"type": "civic", "space": sid, "steps": 1}
					_:
						var typ := "police" if _def().space(sid).type == CoinEnums.SpaceType.CITY else "troops"
						place[sid] = {typ: int(p["n"])}
			var out := {"spaces": selected, "place": place}
			if not special.is_empty():
				out["special"] = special
			return out
		_:
			return {"spaces": selected, "faction": faction}


# ---------------------------------------------------------------------------
# Spazi dove l'Operazione è efficace (guida all'evidenziazione)
#
# Approssimazione volutamente permissiva: il motore rivalida comunque all'esecuzione
# e l'anteprima (preview_operation) mostra il rifiuto prima del clic su "Esegui".
# ---------------------------------------------------------------------------

func valid_spaces(p_faction: String, p_op: String) -> Array:
	var s: GameState = _state()
	var out: Array = []
	for sid in _def().space_ids():
		var sd: SpaceDef = _def().space(sid)
		var st: SpaceState = s.space_state(sid)
		var ok := false
		match p_op:
			"train":
				# Addestramento: Città oppure spazio con una Base del Governo.
				ok = sd.type == CoinEnums.SpaceType.CITY or st.count("government", "base") > 0
			"garrison", "march", "sweep":
				ok = true   # Operazioni a spostamento: libere (trascina i pezzi)
			"rally":
				ok = sd.has_population()
				if p_faction == "m26" and st.support > 0: ok = false
				if p_faction == "directorio" and absi(int(st.support)) == 2: ok = false
			"attack":
				ok = st.count(p_faction, "guerrilla") > 0 and _enemy_present(p_faction, st)
			"terror":
				ok = st.count(p_faction, "guerrilla", "underground") > 0
			"build":
				ok = sd.has_population() and (st.control == "government" or st.control == "syndicate") \
					and _gc.module.can_place_base(s, sid, true)
			"assault":
				# Assalto efficace: Truppe del Governo e bersagli scoperti.
				var enemy := st.count("m26", "guerrilla", "active") + st.count("directorio", "guerrilla", "active") \
					+ st.count("m26", "base") + st.count("directorio", "base") + st.count("syndicate", "casino", "open")
				ok = st.count("government", "troops") > 0 and enemy > 0
		if ok:
			out.append(sid)
	return out


## Almeno un pezzo nemico presente nello spazio (per la Fazione data).
func _enemy_present(p_faction: String, st: SpaceState) -> bool:
	for e in ["government", "m26", "directorio", "syndicate"]:
		if e != p_faction and st.count(e) > 0:
			return true
	return false
