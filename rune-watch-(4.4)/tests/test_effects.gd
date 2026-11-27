extends SceneTree

const EngineScript = preload("res://scripts/effect_engine.gd")

class Dummy extends RefCounted:
	var name: String = "dummy"
	var class_id: String = "warrior"
	var team: int = 0
	var max_health: float = 100.0
	var health: float = 100.0
	var shield: float = 0.0
	var is_dead: bool = false
	var global_position: Vector3 = Vector3.ZERO
	var effect_ids: PackedStringArray = PackedStringArray()
	var statuses: Dictionary = {}
	var notices: Array[String] = []

	func take_damage(amount: float) -> float:
		var blocked := minf(shield, amount)
		shield -= blocked
		var actual := minf(health, amount - blocked)
		health -= actual
		is_dead = health <= 0.0
		return actual

	func receive_heal(amount: float) -> float:
		var actual := minf(max_health - health, amount)
		health += actual
		return actual

	func add_shield(amount: float) -> void:
		shield = minf(max_health * 0.4, shield + amount)

	func refresh_effect_label() -> void:
		pass

	func effect_notice(message: String, _color: Color) -> void:
		notices.append(message)

var failures: int = 0
var count: int = 0

func check(condition: bool, description: String) -> void:
	count += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		printerr("FAIL: ", description)

func _initialize() -> void:
	var engine = EngineScript.new()
	engine.setup(12345)
	var a := Dummy.new()
	var b := Dummy.new()
	var c := Dummy.new()
	b.team = 1
	c.team = 1
	c.global_position = Vector3(1, 0, 0)
	engine.register_unit(a)
	engine.register_unit(b)
	engine.register_unit(c)
	a.effect_ids = PackedStringArray(["ember_spell"])
	engine.attack(a, b, 10.0)
	check(b.statuses.has("burn") and is_equal_approx(b.health, 90.0), "direct hit applies burn")
	engine.tick_unit(b, 1.0)
	check(is_equal_approx(b.health, 84.0), "burn ticks for six damage")
	engine.apply_status(a, b, "burn", 3.0, 6.0)
	check(b.statuses.size() == 1, "refresh does not stack burn")
	engine.apply_status(a, b, "poison", 4.0, 4.0)
	check(b.statuses.is_empty() and is_equal_approx(b.health, 66.0) and is_equal_approx(c.health, 82.0), "toxic blast consumes statuses and hits nearby enemy")
	engine.apply_status(a, b, "burn", 3.0, 6.0)
	engine.apply_status(a, b, "chill", 3.0, 0.3)
	check(is_equal_approx(b.health, 38.0) and b.statuses.is_empty(), "thermal shock")
	engine.apply_status(a, b, "chill", 3.0, 0.3)
	engine.apply_status(a, b, "chill", 3.0, 0.3)
	check(b.statuses.has("freeze") and not b.statuses.has("chill"), "repeat chill freezes")
	engine.tick_unit(b, 1.0)
	check(b.statuses.is_empty(), "freeze expires")
	a.effect_ids = PackedStringArray(["healing_ward"])
	b.team = 0
	engine.heal(a, b, 20.0)
	b.team = 1
	check(is_equal_approx(b.health, 58.0) and is_equal_approx(b.shield, 7.0), "healing ward")
	a.effect_ids = PackedStringArray(["blood_pact"])
	a.health = 70.0
	engine.attack(a, b, 17.0)
	check(is_equal_approx(a.health, 72.0) and is_equal_approx(b.health, 48.0), "lifesteal uses actual HP loss after shield")
	a.effect_ids = PackedStringArray(["ash_crown"])
	engine.apply_status(a, b, "burn", 3.0, 6.0)
	engine.attack(a, b, 100.0)
	check(b.is_dead and is_equal_approx(c.health, 58.0), "ash explosion on death")
	engine.attack(a, b, 100.0)
	check(is_equal_approx(c.health, 58.0), "dead unit cannot trigger death twice")
	a.effect_ids = PackedStringArray(["iron_oath"])
	engine.start_battle()
	check(is_equal_approx(a.shield, 15.0), "start battle shield")
	engine.stopped = true
	engine.attack(a, c, 1000.0)
	check(not c.is_dead, "stopped battle ignores damage")
	check(engine.queue.is_empty() and not engine.processing, "queue returns to idle")
	# Fresh targets to verify a seeded critical and echo without other effects.
	var x := Dummy.new()
	var y := Dummy.new()
	x.effect_ids = PackedStringArray(["keen_edge", "echo_stone"])
	y.team = 1
	var e = EngineScript.new()
	e.setup(42)
	var critical_seen: bool = false
	for i in range(100):
		y.health = 100.0
		y.is_dead = false
		y.notices.clear()
		e.attack(x, y, 10.0)
		if y.notices.has("CRIT"):
			critical_seen = true
			check(y.notices.has("ECHO") and is_equal_approx(y.health, 76.375), "critical and echo damage")
			break
	check(critical_seen, "seeded critical observed")
	# Avoid retaining dummy objects via status source references in tests.
	for unit in [a, b, c, x, y]:
		unit.statuses.clear()
	print("Effect tests: ", count - failures, "/", count)
	quit(0 if failures == 0 else 1)
