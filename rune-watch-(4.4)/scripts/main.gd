extends Node3D
const UNIT_SCENE: PackedScene = preload("res://scenes/unit.tscn")
const RunState = preload("res://scripts/rune_run.gd")
const Lever = preload("res://scripts/rune_lever.gd")
const TITLES: Dictionary = {"warrior":"SWORD", "ranger":"BOW", "wizard":"FIRE", "cleric":"HEAL", "gold":"GOLD"}
const COLORS: Dictionary = {"warrior":Color("e5c89a"), "ranger":Color("9bdd91"), "wizard":Color("ff9a61"), "cleric":Color("b6dfff"), "gold":Color("ffdc76")}
@export_range(1, 8, 1) var enemies_count: int = 4
@export_range(0.1, 3.0) var allies_damage_multiplier: float = 1.0
@export_range(0.1, 3.0) var enemies_damage_multiplier: float = 1.0
@export_range(10.0, 180.0) var battle_time_limit: float = 60.0
@export_group("Unit Classes")
@export var warrior: RuneUnitData = preload("res://data/units/warrior.tres")
@export var ranger: RuneUnitData = preload("res://data/units/ranger.tres")
@export var wizard: RuneUnitData = preload("res://data/units/wizard.tres")
@export var cleric: RuneUnitData = preload("res://data/units/cleric.tres")
@export_group("Synergy Trial")
@export var battle_seed: int = 12345
@export var trace_synergies: bool = true
@export var ally_relics: PackedStringArray = PackedStringArray(["frost_quiver", "ash_crown", "blood_pact", "iron_oath"])
@export var enemy_relics: PackedStringArray = PackedStringArray()

var run := RunState.new()
var effects_engine: RuneEffectEngine
var arena: Node3D
var roster_data: Dictionary = {}
var phase: String = "prep"
var spinning: bool = false
var elapsed: float = 0.0
var auto_clock: float = 0.0
var visual_rng := RandomNumberGenerator.new()
var cells: Array[Label] = []
var status_label: Label
var army_label: Label
var message_label: Label
var spin_button: Button
var fight_button: Button
var auto_button: CheckButton
var lever: Lever

func _ready() -> void:
	for child in get_children():
		if child is RuneUnit:
			push_error("Remove manually placed Unit nodes from Main.")
			set_process(false)
			return
	for data in [warrior, ranger, wizard, cleric]:
		if data == null:
			push_error("Assign all Unit Classes.")
			set_process(false)
			return
		restore_model(data)
		roster_data[data.id] = data
	for id in RunState.SYMBOLS:
		if id != "gold" and not roster_data.has(id):
			push_error("Missing unit class ID: " + id)
			set_process(false)
			return
	visual_rng.randomize()
	create_hud()
	run.setup(battle_seed)
	prepare_wave()

func prepare_wave() -> void:
	phase = "prep"
	elapsed = 0.0
	auto_clock = 0.0
	message_label.text = "Pull the lever or press SPIN."
	rebuild_preview()
	refresh_hud()

func rebuild_preview() -> void:
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	arena = Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	effects_engine = RuneEffectEngine.new()
	effects_engine.setup(battle_seed + run.wave, trace_synergies)
	for i in range(run.roster.size()):
		var entry: Dictionary = run.roster[i]
		spawn_unit(0, i, run.roster.size(), roster_data[entry.id] as RuneUnitData, int(entry.level))
	var count := wave_enemy_count()
	var enemy_ids: Array[String] = ["warrior", "ranger", "wizard", "cleric"]
	for i in range(count):
		spawn_unit(1, i, count, roster_data[enemy_ids[i % enemy_ids.size()]] as RuneUnitData, 1)

func wave_enemy_count() -> int:
	return clampi(enemies_count + run.wave - 2, 2, 8)

func spawn_unit(team_id: int, index: int, count: int, data: RuneUnitData, level: int) -> void:
	var unit := UNIT_SCENE.instantiate() as RuneUnit
	if unit == null:
		push_error("Unit scene root must use RuneUnit.")
		return
	unit.definition = data
	unit.name = ("Ally" if team_id == 0 else "Enemy") + "_%s_%02d" % [data.display_name, index + 1]
	unit.team = team_id
	unit.effects_engine = effects_engine
	unit.team_effect_ids = ally_relics if team_id == 0 else enemy_relics
	var growth := 1.0 + 0.12 * (level - 1) if team_id == 0 else 1.0 + 0.10 * (run.wave - 1)
	unit.damage_multiplier = (allies_damage_multiplier if team_id == 0 else enemies_damage_multiplier) * growth
	unit.battle_active = false
	var row_start: int = 0 if index < 4 else 4
	var row_count := mini(4, count - row_start)
	var z := (float(index - row_start) - float(row_count - 1) / 2.0) * 1.8
	var x := 4.5 + (1.7 if index >= 4 else 0.0)
	unit.position = Vector3(-x if team_id == 0 else x, 0.0, z)
	unit.rotation.y = PI / 2.0 if team_id == 0 else -PI / 2.0
	arena.add_child(unit)
	unit.max_health *= growth
	unit.health = unit.max_health
	unit.update_health_bar()

func request_spin() -> void:
	if phase != "prep" or spinning or not run.can_spin():
		return
	var board: Array[String] = run.spin()
	if board.is_empty():
		return
	spinning = true
	refresh_hud()
	# Cosmetic RNG is separate from gameplay RNG. Columns stop in sequence.
	for frame in range(12):
		for index in range(9):
			var column := index % 3
			var stop_frame := 5 + column * 3
			var id: String = board[index] if frame >= stop_frame else RunState.SYMBOLS[visual_rng.randi_range(0, 4)]
			paint_cell(index, id)
		await get_tree().create_timer(0.065).timeout
	for index in range(9):
		paint_cell(index, board[index])
	var result: Dictionary = run.resolve(board)
	var lines: Array[String] = result.log
	var visible_lines := PackedStringArray()
	for i in range(mini(3, lines.size())):
		visible_lines.append(lines[i])
	if lines.size() > 3:
		visible_lines.append("+ %d more rewards" % (lines.size() - 3))
	message_label.text = ("JACKPOT x%d!\n" % result.jackpots if result.jackpots > 0 else "") + ("\n".join(visible_lines) if not visible_lines.is_empty() else "Summon marks gained.")
	rebuild_preview()
	spinning = false
	auto_clock = 0.0
	refresh_hud()

func start_battle() -> void:
	if phase != "prep" or spinning:
		return
	phase = "battle"
	elapsed = 0.0
	for child in arena.get_children():
		if child is RuneUnit:
			child.battle_active = true
	effects_engine.start_battle()
	message_label.text = "Battle in progress..."
	refresh_hud()

func _process(delta: float) -> void:
	if not is_instance_valid(status_label):
		return
	if phase == "prep" and not spinning and auto_button.button_pressed and run.free_spins > 0:
		auto_clock += delta
		if auto_clock >= 0.6:
			auto_clock = 0.0
			request_spin()
	if phase != "battle":
		return
	elapsed += delta
	var allies: int = 0
	var enemies: int = 0
	for child in arena.get_children():
		if child is RuneUnit and not child.is_dead:
			if child.team == 0:
				allies += 1
			else:
				enemies += 1
	status_label.text = "Wave %d/%d | Gold %d\nAllies %d | Enemies %d | %.1fs" % [run.wave, RunState.WAVES, run.gold, allies, enemies, elapsed]
	if allies == 0 or enemies == 0 or elapsed >= battle_time_limit:
		finish_battle(allies > 0 and enemies == 0)

func finish_battle(won: bool) -> void:
	effects_engine.stopped = true
	for child in arena.get_children():
		if child is RuneUnit:
			child.finish_battle()
	if won and run.wave < RunState.WAVES:
		phase = "reward"
		message_label.text = "VICTORY! +3 gold next wave."
	elif won:
		phase = "end"
		message_label.text = "RUN COMPLETE! Press R to restart."
	else:
		phase = "end"
		message_label.text = "TIME LIMIT" if elapsed >= battle_time_limit else "DEFEAT"
		message_label.text += " — press R to restart."
	print("Wave ", run.wave, " result: ", "VICTORY" if won else "STOPPED")
	refresh_hud()

func fight_or_continue() -> void:
	if phase == "reward":
		if run.advance():
			prepare_wave()
	elif phase == "end":
		get_tree().reload_current_scene()
	else:
		start_battle()

func paint_cell(index: int, id: String) -> void:
	cells[index].text = TITLES[id]
	cells[index].add_theme_color_override("font_color", COLORS[id])

func refresh_hud() -> void:
	if phase != "battle":
		status_label.text = "Wave %d/%d | Gold %d\nFree spins: %d" % [run.wave, RunState.WAVES, run.gold, run.free_spins]
	var parts: Array[String] = []
	for id in RunState.SYMBOLS:
		if id == "gold":
			continue
		var count: int = 0
		var highest: int = 0
		for entry in run.roster:
			if entry.id == id:
				count += 1
				highest = maxi(highest, int(entry.level))
		parts.append("%s: %d | mark %d/2%s" % [TITLES[id], count, run.marks[id], (" | Lv %d" % highest) if highest > 1 else ""])
	army_label.text = "Army %d/%d\n" % [run.roster.size(), RunState.CAP] + "\n".join(PackedStringArray(parts))
	var allowed := phase == "prep" and not spinning and run.can_spin()
	spin_button.disabled = not allowed
	spin_button.text = "SPIN (free)" if run.free_spins > 0 else "SPIN (3 gold)"
	lever.set_enabled(allowed)
	fight_button.disabled = spinning or phase == "battle"
	fight_button.text = "NEXT WAVE" if phase == "reward" else ("RESTART" if phase == "end" else "BATTLE")
	auto_button.disabled = phase != "prep"

func create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size.x = 270
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202d2d")
	style.border_color = Color("a88b5d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "MIMIR / RUNE WATCH"
	title.add_theme_color_override("font_color", Color("e3bc76"))
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)
	status_label = Label.new()
	col.add_child(status_label)
	var row := HBoxContainer.new()
	col.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 3
	row.add_child(grid)
	for i in range(9):
		var slot := PanelContainer.new()
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color("172223")
		slot_style.border_color = Color("c5a36e") if i >= 3 and i <= 5 else Color("52655d")
		slot_style.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", slot_style)
		grid.add_child(slot)
		var cell := Label.new()
		cell.custom_minimum_size = Vector2(60, 38)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.text = "—"
		cell.add_theme_font_size_override("font_size", 13)
		slot.add_child(cell)
		cells.append(cell)
	lever = Lever.new()
	row.add_child(lever)
	lever.pulled.connect(request_spin)
	spin_button = Button.new()
	spin_button.pressed.connect(request_spin)
	col.add_child(spin_button)
	auto_button = CheckButton.new()
	auto_button.text = "Auto free spins"
	col.add_child(auto_button)
	army_label = Label.new()
	col.add_child(army_label)
	message_label = Label.new()
	message_label.custom_minimum_size = Vector2(245, 65)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(message_label)
	fight_button = Button.new()
	fight_button.pressed.connect(fight_or_continue)
	col.add_child(fight_button)
	var help := Label.new()
	help.text = "Space: spin | R: restart"
	help.add_theme_font_size_override("font_size", 13)
	col.add_child(help)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			get_viewport().set_input_as_handled()
			get_tree().reload_current_scene()
		elif event.physical_keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			request_spin()


# Recovery: use imported original models when present, otherwise keep the proxy.
func restore_model(data: RuneUnitData) -> void:
	if data.model_scene != null:
		return
	var candidates: Array[String] = [data.display_name]
	if data.id == "wizard":
		candidates.append("Wizard2")
	for stem in candidates:
		for extension in ["gltf", "glb"]:
			var path: String = "res://assets/models/characters/%s.%s" % [stem, extension]
			if ResourceLoader.exists(path, "PackedScene"):
				var model := load(path) as PackedScene
				if model != null:
					data.model_scene = model
					return
	# A separate scene for each proxy preserves class readability.
	data.model_scene = load("res://scenes/proxy_%s.tscn" % data.id) as PackedScene
