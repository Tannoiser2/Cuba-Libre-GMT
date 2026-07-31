class_name LogView
extends RichTextLabel

## Registro delle azioni: righe colorate per Fazione, divisori di fine turno e
## tracce della logica dei Bot espandibili con un clic ("[+] logica").
##
## Si occupa da sé della propria resa: la scena aggiunge le righe con `add_line()` /
## `add_decision()` e non deve sapere nulla di BBCode.

const MAX_ENTRIES := 300   ## oltre questa soglia le righe più vecchie vengono scartate

var _entries: Array = []   ## {t: testo, f: fazione, tr: traccia, exp: espansa}
var _dropped := 0          ## righe scartate per il limite (segnalate in testa)


func _init() -> void:
	bbcode_enabled = true
	scroll_following = true
	scroll_active = true
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size",
			"bold_italics_font_size", "mono_font_size"]:
		add_theme_font_size_override(fs, 11)
	add_theme_constant_override("line_separation", 2)
	meta_clicked.connect(_on_meta_clicked)


func clear_log() -> void:
	_entries.clear()
	_dropped = 0
	render()


## Riga semplice (azione, esito, messaggio di sistema).
func add_line(text: String, faction: String = "") -> void:
	_entries.append({"t": text, "f": faction, "tr": []})
	render()


## Decisione di un Bot, con la traccia del ragionamento richiudibile.
func add_decision(text: String, faction: String, trace: Array) -> void:
	_entries.append({"t": text, "f": faction, "tr": trace})
	render()


func _on_meta_clicked(meta: Variant) -> void:
	var i := int(meta)
	if i >= 0 and i < _entries.size():
		_entries[i]["exp"] = not bool(_entries[i].get("exp", false))
		render()


func render() -> void:
	if _entries.size() > MAX_ENTRIES:
		var cut := _entries.size() - MAX_ENTRIES
		_dropped += cut
		_entries = _entries.slice(cut)
	var s := ""
	# Il taglio non è più silenzioso: si vede che qualcosa è stato omesso.
	if _dropped > 0:
		s += "[center][font_size=9][color=#5b6571]… %d righe precedenti omesse[/color][/font_size][/center]\n" % _dropped
	var turn := 0
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var txt := String(e["t"])
		# Fine carta = fine di un turno: divisore prominente col numero del turno.
		if String(e["f"]) == "" and txt.find("Carta conclusa") != -1:
			turn += 1
			s += "[center][b][color=#f1c40f]=====  Fine turno %d  =====[/color][/b][/center]\n" % turn
			continue
		if String(e["f"]) == "" and txt.find("FINE PARTITA") != -1:
			s += "\n[center][b][font_size=16][color=#f1c40f]===  FINE PARTITA  ===[/color][/font_size][/b][/center]\n"
			continue
		s += CLTheme.faction_chip(txt, String(e["f"]))
		if (e["tr"] as Array).size() > 0:
			var exp: bool = e.get("exp", false)
			s += " [url=%d][font_size=10][color=#7fb0ff]%s[/color][/font_size][/url]\n" % [
				i, ("[-] logica" if exp else "[+] logica")]
			if exp:
				s += _render_trace(e["tr"])
		else:
			s += "\n"
	text = s
	scroll_to_line(maxi(0, get_line_count() - 1))


## Traccia del Bot come albero: le condizioni del retro rientrano più delle altre.
func _render_trace(trace: Array) -> String:
	var s := ""
	var depth := 1   # livello base delle sotto-righe sotto una carta
	for tl in trace:
		var raw := String(tl)
		# Indentazione "originale" (le sotto-priorità hanno spazi iniziali).
		var lead := 0
		while lead < raw.length() and raw[lead] == " ":
			lead += 1
		var line := raw.strip_edges()
		if line == "":
			continue
		var extra := lead / 2
		var lvl := depth
		if line.begins_with("Carta Calixto"):
			depth = 1
			lvl = 0
		elif line.begins_with("-> giro") or line.find("(retro)") != -1:
			lvl = depth
			depth += 1
		elif line.begins_with("Operazione scelta") or line.begins_with("Attività Speciale") \
				or line.begins_with("Nessuna Operazione"):
			lvl = 0
		s += "  [font_size=9][color=#9fb3c8]%s%s[/color][/font_size]\n" % ["  ".repeat(lvl + extra), line]
	return s
