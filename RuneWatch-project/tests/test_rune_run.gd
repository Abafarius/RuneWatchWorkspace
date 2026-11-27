extends SceneTree
const Run = preload("res://scripts/rune_run.gd")
var failures: int = 0
var checks: int = 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", title)

func _initialize() -> void:
	var a := Run.new()
	var b := Run.new()
	a.setup(42)
	b.setup(42)
	check(a.roster.size() == 2 and a.gold == 5, "initial roster")
	var board := a.spin()
	check(board.size() == 9 and board == b.spin(), "seed reproducibility")
	check(a.free_spins == 1 and not a.can_spin(), "spin pending")
	a.resolve(board)
	var gold_after: int = a.gold
	var size_after: int = a.roster.size()
	var marks_after: Dictionary = a.marks.duplicate()
	a.resolve(board)
	check(a.gold == gold_after and a.roster.size() == size_after and a.marks == marks_after, "no duplicate payout")
	board = a.spin()
	a.resolve(board)
	check(a.free_spins == 0, "two free spins")
	gold_after = a.gold
	board = a.spin()
	check(board.size() == 9 and a.gold == gold_after - 3 and a.paid_used, "paid spin")
	a.resolve(board)
	check(not a.can_spin() and a.spin().is_empty(), "paid limit")
	check(a.advance() and a.wave == 2 and a.free_spins == 2 and not a.paid_used, "advance")
	# Inject a known board to test exact intersection payouts without RNG luck.
	a.setup(1)
	a.last_result.assign(["gold", "gold", "gold", "gold", "gold", "gold", "gold", "gold", "gold"])
	a.awaiting_resolution = true
	var result: Dictionary = a.resolve(a.last_result.duplicate())
	check(result.jackpots == 5 and a.gold == 23, "five paylines and center")
	var log: Array[String] = []
	a.grant("warrior", 40, log)
	check(a.roster.size() == Run.CAP and int(a.roster[0].level) > 1, "auto fusion")
	a.grant("cleric", 2, log)
	check(a.gold == 25 and a.roster.size() == Run.CAP, "overflow conversion")
	for i in range(4):
		a.advance()
	check(a.wave == Run.WAVES and not a.advance(), "five wave limit")
	print("Rune tests: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
