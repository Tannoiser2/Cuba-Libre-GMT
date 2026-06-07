extends SceneTree

## Simulazione: gioca N partite completamente automatiche (bot vs bot) e produce un report
## con vittorie, valori e margini finali per Fazione.
##   godot4 --headless --path godot -s res://tests/sim_runner.gd -- 20

const FACTIONS := ["government", "m26", "directorio", "syndicate"]
const NAMES := {
	"government": "Governo", "m26": "26 Luglio",
	"directorio": "Directorio", "syndicate": "Sindacato",
}


func _initialize() -> void:
	randomize()
	var n := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		n = int(args[0])

	var wins := {"government": 0, "m26": 0, "directorio": 0, "syndicate": 0}
	var win_by_condition := 0
	var sum_value := {"government": 0, "m26": 0, "directorio": 0, "syndicate": 0}
	var sum_margin := {"government": 0, "m26": 0, "directorio": 0, "syndicate": 0}
	var best_value := {"government": -999, "m26": -999, "directorio": -999, "syndicate": -999}
	var rows: Array = []

	for g in range(n):
		var gc = load("res://scenes/GameController.gd").new()
		gc.new_game()
		gc.run_full_game()
		var vs: Dictionary = gc.module.victory_status(gc.state)

		# Vincitore: per condizione (se in partita) altrimenti per margine maggiore (7.3)
		var winner: String = gc.winner
		var by_condition := winner != ""
		if winner == "":
			winner = _best_by_margin(vs, gc.module.tiebreak_order())
		if by_condition:
			win_by_condition += 1
		wins[winner] += 1

		for f in FACTIONS:
			sum_value[f] += int(vs[f].value)
			sum_margin[f] += int(vs[f].margin)
			best_value[f] = maxi(best_value[f], int(vs[f].value))

		rows.append({
			"game": g + 1, "winner": winner, "by_cond": by_condition,
			"gov": vs["government"].margin, "m26": vs["m26"].margin,
			"dr": vs["directorio"].margin, "syn": vs["syndicate"].margin,
		})
		gc.free()

	_print_report(n, wins, win_by_condition, sum_value, sum_margin, best_value, rows)
	quit(0)


func _best_by_margin(vs: Dictionary, tiebreak: PackedStringArray) -> String:
	var best := ""
	var best_m := -9999
	for f in FACTIONS:
		var m: int = int(vs[f].margin)
		if m > best_m:
			best_m = m; best = f
		elif m == best_m and best != "":
			# parità: usa l'ordine di tie-break del modulo
			if tiebreak.find(f) < tiebreak.find(best):
				best = f
	return best


func _print_report(n, wins, win_by_condition, sum_value, sum_margin, best_value, rows) -> void:
	print("\n==================================================")
	print("  REPORT SIMULAZIONE — %d partite (bot vs bot)" % n)
	print("==================================================\n")
	print("Dettaglio partite (margine di vittoria per Fazione; * = vittoria per condizione):")
	print("  #  Vincitore      Gov   M26    DR   Syn")
	for r in rows:
		print("  %2d %-12s %4d  %4d  %4d  %4d %s" % [
			r.game, NAMES[r.winner], r.gov, r.m26, r.dr, r.syn,
			"*" if r.by_cond else "",
		])

	print("\nVittorie per Fazione:")
	for f in FACTIONS:
		var pct: float = 100.0 * int(wins[f]) / n
		print("  %-12s %2d / %d  (%.0f%%)  %s" % [
			NAMES[f], wins[f], n, pct, _bar(wins[f], n)])
	print("\n  Vittorie per condizione (in partita): %d / %d" % [win_by_condition, n])
	print("  Vittorie ai margini (dopo Propaganda finale): %d / %d" % [n - win_by_condition, n])

	print("\nMedie finali per Fazione:")
	print("  Fazione        Valore medio   Margine medio   Valore max")
	for f in FACTIONS:
		print("  %-12s %10.1f %14.1f %12d" % [
			NAMES[f], float(sum_value[f]) / n, float(sum_margin[f]) / n, best_value[f]])
	print("\nSoglie di vittoria: Governo>18 · 26 Luglio>15 · Directorio>9 · Sindacato Casinò>7 & Ris>30")
	print("==================================================\n")


func _bar(v: int, n: int) -> String:
	var blocks := int(round(20.0 * v / maxi(n, 1)))
	return "#".repeat(blocks)
