extends RefCounted
## Pure run state. No scene nodes or animation timing.
const SYMBOLS: Array[String] = ["warrior", "ranger", "wizard", "cleric", "gold"]
const CAP: int = 8
const WAVES: int = 5
const PAID_PRICE: int = 3
var rng := RandomNumberGenerator.new()
var roster: Array[Dictionary] = []
var marks: Dictionary = {}
var gold: int = 5
var wave: int = 1
var free_spins: int = 2
var paid_used: bool = false
var last_result: Array[String] = []
var awaiting_resolution: bool = false

func setup(seed_value: int) -> void:
	rng.seed = seed_value
	roster.clear()
	marks.clear()
	gold = 5
	wave = 1
	free_spins = 2
	paid_used = false
	last_result.clear()
	awaiting_resolution = false
	for id in SYMBOLS:
		if id != "gold":
			marks[id] = 0
	roster.append({"id": "warrior", "level": 1})
	roster.append({"id": "wizard", "level": 1})

func can_spin() -> bool:
	return not awaiting_resolution and (free_spins > 0 or (not paid_used and gold >= PAID_PRICE))

func spin() -> Array[String]:
	if not can_spin():
		return []
	if free_spins > 0:
		free_spins -= 1
	else:
		gold -= PAID_PRICE
		paid_used = true
	var board: Array[String] = []
	for i in range(9):
		board.append(SYMBOLS[rng.randi_range(0, SYMBOLS.size() - 1)])
	last_result = board.duplicate()
	awaiting_resolution = true
	return board

func resolve(board: Array[String]) -> Dictionary:
	# Caller invokes this once per successful spin. Each of 5 lines pays once.
	var log: Array[String] = []
	var jackpots: int = 0
	if not awaiting_resolution or board != last_result or board.size() != 9:
		return {"log": log, "jackpots": jackpots}
	for id in board:
		if not SYMBOLS.has(id):
			return {"log": log, "jackpots": jackpots}
	awaiting_resolution = false
	for i in [3, 4, 5]:
		grant(board[i], 1, log)
	for line in [[0,1,2], [3,4,5], [6,7,8], [0,4,8], [2,4,6]]:
		if board[line[0]] == board[line[1]] and board[line[1]] == board[line[2]]:
			jackpots += 1
			grant(board[line[0]], 3, log)
	return {"log": log, "jackpots": jackpots}

func grant(id: String, amount: int, log: Array[String]) -> void:
	if id == "gold":
		gold += amount
		log.append("+%d gold" % amount)
		return
	marks[id] = int(marks.get(id, 0)) + amount
	while int(marks[id]) >= 2:
		marks[id] = int(marks[id]) - 2
		if roster.size() < CAP:
			roster.append({"id": id, "level": 1})
			log.append("Summoned " + id)
		else:
			var best: int = -1
			for i in range(roster.size()):
				if roster[i].id == id and (best == -1 or int(roster[i].level) > int(roster[best].level)):
					best = i
			if best >= 0:
				roster[best]["level"] = int(roster[best].level) + 1
				log.append("%s -> Lv %d" % [id, roster[best].level])
			else:
				gold += 2
				log.append("Reserve full: +2 gold")

func advance() -> bool:
	if awaiting_resolution or wave >= WAVES:
		return false
	gold += 3
	wave += 1
	free_spins = 2
	paid_used = false
	return true
