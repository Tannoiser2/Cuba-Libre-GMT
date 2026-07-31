extends SceneTree

## Test di montaggio della scena (headless): da eseguire con
##   godot4 --headless --path godot -s res://tests/scene_smoke.gd
## Costruisce davvero la scena principale in headless: se il refactor avesse rotto
## il montaggio della UI (nodi mancanti, segnali su null, ordini sbagliati) si vedrebbe qui.

func _initialize() -> void:
	var fails := 0
	var gc = root.get_node("GameController")
	# In modalità -s il _ready() dell'autoload può non essere ancora scattato.
	if gc.state == null:
		gc.new_game()
	# --- Menu iniziale: si monta, avvia una partita e imposta le opzioni ---
	var menu_packed: PackedScene = load("res://scenes/MainMenu.tscn")
	if menu_packed == null:
		print("FAIL: MainMenu.tscn non caricata"); fails += 1
	else:
		var menu = menu_packed.instantiate()
		root.add_child(menu)
		await process_frame
		print("ok  menu iniziale montato (%d nodi figli)" % menu.get_child_count())
		if menu.get_child_count() == 0:
			print("FAIL: il menu non ha costruito nulla"); fails += 1
		# Avvio con scenario Variabile e partita breve.
		menu._set_scenario("variable")
		menu._toggle_short()
		menu._start_game()
		await process_frame
		if gc.scenario != "variable" or not gc.short_game:
			print("FAIL: opzioni non applicate (%s, breve=%s)" % [gc.scenario, str(gc.short_game)]); fails += 1
		else:
			print("ok  partita avviata dal menu: scenario=%s breve=%s carte=%d" % [
				gc.scenario, str(gc.short_game), gc.state.draw_deck.size() + 1])
		if is_instance_valid(menu):
			menu.free()
	# Torna allo scenario standard per il resto del test.
	gc.new_game("standard", false)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		print("FAIL: Main.tscn non caricata"); quit(1); return
	var main = packed.instantiate()
	root.add_child(main)
	# Il _ready() dei nodi (e quindi la costruzione della UI) scatta al primo frame.
	await process_frame
	print("ok  scena istanziata (%d nodi figli)" % main.get_child_count())
	# I sotto-componenti estratti devono esserci ed essere collegati.
	var side = null
	var anim = null
	var logv = null
	for c in main.get_children():
		var scr = c.get_script()
		var nm := "" if scr == null else String(scr.resource_path).get_file()
		if nm == "SidePanel.gd":
			side = c
	if side == null:
		print("FAIL: SidePanel non trovato"); fails += 1
	else:
		print("ok  SidePanel montato")
		if side.log_view == null:
			print("FAIL: LogView assente"); fails += 1
		else:
			logv = side.log_view
			print("ok  LogView collegato")
	# Il log deve ricevere davvero i messaggi del controller.
	if logv != null:
		var before: int = logv.text.length()
		gc.action_logged.emit("prova di registro", "m26")
		if logv.text.length() <= before:
			print("FAIL: il log non riceve i segnali"); fails += 1
		else:
			print("ok  il log riceve i segnali del controller")
	# Un giro di aggiornamento completo (carte, Vittoria, animazioni, banner).
	gc.state_changed.emit()
	print("ok  aggiornamento completo senza errori")
	# Simula il ciclo di gioco: una mossa bot e la Propaganda automatica.
	gc.set_role("government", "bot")
	for i in range(3):
		gc.bot_act_pending()
	print("ok  tre turni bot con la scena viva, carta ", gc.state.current_card)
	# Salva e ricarica con la UI montata.
	gc.save_game("user://_scene.json")
	if not gc.load_game("user://_scene.json"):
		print("FAIL: caricamento"); fails += 1
	else:
		gc.state_changed.emit()
		print("ok  salva/carica con la scena montata")
	print("FAILS=%d" % fails)
	quit(1 if fails > 0 else 0)
