extends SceneTree

## Cattura uno screenshot della scena di partita (serve un display: xvfb-run).
##   xvfb-run godot --path godot --rendering-method gl_compatibility -s res://tools/screenshot.gd -- out.png [rally]
## Con "menu" fotografa il menu iniziale; con "rally" prepara un Rally del 26 Luglio in Sierra Maestra per mostrare il pannello azione.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var demo := args.size() > 1 and args[1] == "rally"
	if args.size() > 1 and args[1] == "menu":
		root.add_child(load("res://scenes/MainMenu.tscn").instantiate())
		for i in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out)
		print("salvato ", out)
		quit(0)
		return
	var gc = root.get_node("GameController")
	gc.new_game("standard", false)
	for f in ["government", "directorio", "syndicate"]:
		gc.set_role(f, "bot")
	gc.set_role("m26", "player")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	for i in range(10):
		await process_frame
	# Fa giocare i Bot finché non tocca al 26 Luglio (massimo qualche carta).
	for i in range(30):
		var st: Dictionary = gc.seq_status()
		var p := String(st.get("pending", ""))
		if p == "m26":
			break
		if p != "" and gc.is_bot(p):
			gc.bot_act_pending()
		else:
			gc.advance_card() if gc.has_method("advance_card") else null
		await process_frame
	if demo and main.has_method("_start_op"):
		main._start_op("rally")
		await process_frame
		main._on_space_clicked("sierra_maestra")
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("salvato ", out, " ", img.get_size())
	quit(0)
