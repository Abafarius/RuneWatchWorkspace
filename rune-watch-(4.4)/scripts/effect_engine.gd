class_name RuneEffectEngine
extends RefCounted

const Catalog = preload("res://scripts/effect_catalog.gd")
const MAX_EVENTS: int = 96
const MAX_DEPTH: int = 8
var rng := RandomNumberGenerator.new()
var units: Array = []
var queue: Array[Dictionary] = []
var processing: bool = false
var depth: int = 0
var event_count: int = 0
var trace: bool = false
var stopped: bool = false

func setup(seed_value: int, trace_enabled: bool = false) -> void:
	rng.seed = seed_value
	trace = trace_enabled

func register_unit(unit) -> void:
	units.append(unit)

func start_battle() -> void:
	for unit in units:
		if is_instance_valid(unit):
			emit_event("battle_start", unit, unit, unit.max_health)

func attack(source, target, base_amount: float) -> void:
	if stopped or not alive(source) or not alive(target) or source.team == target.team:
		return
	var amount: float = base_amount
	var critical: bool = false
	for rule_id in source.effect_ids:
		var rule: Dictionary = Catalog.RULES.get(rule_id, {})
		if rule.get("trigger") == "before_attack" and rule.get("action") == "crit" and matches(rule, source):
			if rng.randf() < float(rule.chance):
				amount *= float(rule.multiplier)
				critical = true
	if critical:
		target.effect_notice("CRIT", Color("ffd36d"))
		log_effect("CRIT", target)
	# Hold death events until direct hit effects have been enqueued; all secondary damage is bounded.
	processing = true
	depth = 0
	event_count = 0
	var actual: float = damage(source, target, amount)
	emit_event("hit", source, target, actual)
	if critical:
		emit_event("crit", source, target, actual)
	processing = false
	drain()

func heal(source, target, amount: float) -> void:
	if stopped or not alive(source) or not alive(target) or source.team != target.team:
		return
	var actual: float = target.receive_heal(amount)
	if actual > 0.0:
		emit_event("heal", source, target, actual)

func damage(source, target, amount: float) -> float:
	if stopped or not alive(target) or amount <= 0.0:
		return 0.0
	var actual: float = target.take_damage(amount)
	if target.is_dead:
		emit_event("death", source, target, actual)
	return actual

func emit_event(kind: String, source, target, amount: float) -> void:
	if stopped or depth >= MAX_DEPTH or queue.size() >= MAX_EVENTS:
		return
	queue.append({"kind": kind, "source": source, "target": target, "amount": amount, "depth": depth + 1})
	if not processing:
		drain()

func drain() -> void:
	processing = true
	event_count = 0
	while not queue.is_empty() and event_count < MAX_EVENTS:
		var event: Dictionary = queue.pop_front()
		depth = int(event.depth)
		event_count += 1
		apply_event(event)
	if not queue.is_empty():
		push_warning("Effect event budget reached; remaining events discarded.")
	queue.clear()
	depth = 0
	processing = false

func matches(rule: Dictionary, source) -> bool:
	return not rule.has("class_id") or rule.class_id == source.class_id

func apply_event(event: Dictionary) -> void:
	var source = event.source
	var target = event.target
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	for rule_id in source.effect_ids:
		var rule: Dictionary = Catalog.RULES.get(rule_id, {})
		if rule.get("trigger") != event.kind or not matches(rule, source):
			continue
		if rule.has("requires_status") and not target.statuses.has(rule.requires_status):
			continue
		match rule.action:
			"status":
				if alive(source) and alive(target):
					apply_status(source, target, rule.status, float(rule.duration), float(rule.power))
			"shield":
				if alive(target):
					var amount: float = float(event.amount) * float(rule.factor)
					target.add_shield(amount)
			"lifesteal":
				if alive(source) and float(event.amount) > 0.0:
					# Direct heal, not a new heal event: avoids self-proccing healing loops.
					source.receive_heal(float(event.amount) * float(rule.factor))
			"explosion":
				target.effect_notice("ASH BURST", Color("ff9955"))
				log_effect("ASH BURST", target)
				area_damage(source, target, float(rule.power), float(rule.radius))
			"echo":
				if alive(target):
					target.effect_notice("ECHO", Color("c4b5ff"))
					damage(source, target, float(event.amount) * float(rule.factor))

func apply_status(source, target, kind: String, duration: float, power: float) -> void:
	if not alive(target):
		return
	var previous: Dictionary = target.statuses.get(kind, {})
	# Refresh, never multiply stacks. Preserve tick timer when refreshing.
	target.statuses[kind] = {"remaining": duration, "power": power, "tick": float(previous.get("tick", 1.0)), "source": source}
	if kind == "chill" and not previous.is_empty() and not target.statuses.has("freeze"):
		target.statuses.erase("chill")
		target.statuses["freeze"] = {"remaining": 0.8, "power": 0.0, "tick": 1.0, "source": source}
		target.effect_notice("FREEZE", Color("85def8"))
		log_effect("FREEZE", target)
	else:
		for reaction in Catalog.REACTIONS:
			if target.statuses.has(reaction.requires[0]) and target.statuses.has(reaction.requires[1]):
				target.statuses.erase(reaction.requires[0])
				target.statuses.erase(reaction.requires[1])
				target.effect_notice(reaction.name, Color(reaction.color))
				log_effect(reaction.name, target)
				damage(source, target, float(reaction.power))
				if float(reaction.radius) > 0.0:
					area_damage(source, target, float(reaction.power), float(reaction.radius))
				break
	target.refresh_effect_label()

func tick_unit(unit, delta: float) -> void:
	if stopped or not alive(unit):
		return
	for kind in unit.statuses.keys():
		if not alive(unit):
			break
		var status: Dictionary = unit.statuses[kind]
		var active_delta: float = minf(delta, float(status.remaining))
		status.remaining = float(status.remaining) - active_delta
		if kind == "burn" or kind == "poison":
			status.tick = float(status.tick) - active_delta
			while float(status.tick) <= 0.00001 and alive(unit):
				status.tick = float(status.tick) + 1.0
				damage(status.source, unit, float(status.power))
		if float(status.remaining) <= 0.00001:
			unit.statuses.erase(kind)
			unit.refresh_effect_label()

func area_damage(source, center, amount: float, radius: float) -> void:
	for unit in units:
		if not alive(unit) or unit == center or unit.team != center.team:
			continue
		if unit.global_position.distance_squared_to(center.global_position) <= radius * radius:
			damage(source, unit, amount)

func alive(unit) -> bool:
	return is_instance_valid(unit) and not unit.is_dead

func log_effect(label: String, target) -> void:
	if trace:
		print("[SYNERGY] ", label, " -> ", target.name)
