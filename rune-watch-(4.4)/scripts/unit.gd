class_name RuneUnit
extends Node3D

@export var unit_name: String = "Wizard"
@export var definition: RuneUnitData
@export var damage_multiplier: float = 1.0
@export_enum("Allies", "Enemies") var team: int = 0

@export_group("Combat")
@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var move_speed: float = 2.5
@export var attack_range: float = 1.6
@export var attack_interval: float = 1.5
@export var hit_delay: float = 0.4
@export var attack_lock_time: float = 0.9
@export var separation_radius: float = 0.9

@export_group("Animations")
@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Walk"
@export var attack_animation: String = "Staff_Attack"
@export var cast_animation: String = "Spell1"
@export var hit_animation: String = "RecieveHit"
@export var death_animation: String = "Death"

@export_group("Feedback")
# Local offset of the health bar, measured from the Unit root.
@export var feedback_height: float = 3.7
@export var health_bar_offset_x: float = 0.0
@export var health_bar_offset_z: float = 0.0

var heal_amount: float = 0.0
var heal_range: float = 4.0
var battle_active: bool = true
var pending_heal: bool = false
var health: float
var is_dead: bool = false
var target: RuneUnit
var animation_player: AnimationPlayer
var attack_timer: float = 0.0
var action_lock: float = 0.0
var pending_hit: float = -1.0
var attack_target: RuneUnit
var health_bar: Sprite3D
var bar_image: Image
var bar_texture: ImageTexture
var first_attack_logged: bool = false
var effects_engine: RuneEffectEngine
var class_id: String = "wizard"
var effect_ids: PackedStringArray = PackedStringArray()
var team_effect_ids: PackedStringArray = PackedStringArray()
var statuses: Dictionary = {}
var shield: float = 0.0
var effects_label: Label3D

# Small world-space margin prevents floating-point stalls at the attack boundary.
const REACH_EPSILON: float = 0.05
const APPROACH_INSET: float = 0.12


func _ready() -> void:
	apply_definition()
	health = maxf(1.0, max_health)
	add_to_group("units")
	var players = $Visual.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		configure_animations()
		set_loop(idle_animation, true)
		set_loop(walk_animation, true)
		set_loop(attack_animation, false)
		set_loop(cast_animation, false)
		set_loop(hit_animation, false)
		set_loop(death_animation, false)
	else:
		push_warning("No AnimationPlayer for " + unit_name)
	create_health_bar()
	create_effect_label()
	if effects_engine != null:
		effects_engine.register_unit(self)
	play_idle()


func _physics_process(delta: float) -> void:
	if is_dead or not battle_active:
		return
	if effects_engine != null:
		effects_engine.tick_unit(self, delta)
	if is_dead or statuses.has("freeze"):
		if not is_dead:
			# Freeze cancels the unfinished wind-up; cooldown resumes after thaw.
			pending_hit = -1.0
			attack_target = null
			pending_heal = false
			action_lock = 0.0
			play_idle()
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	action_lock = maxf(0.0, action_lock - delta)

	# Damage is resolved after a short wind-up, not on animation start.
	if pending_hit >= 0.0:
		pending_hit -= delta
		if pending_hit <= 0.0:
			pending_hit = -1.0
			resolve_hit()
			if is_dead:
				return

	if action_lock > 0.0 or pending_hit >= 0.0:
		return

	# Support chooses a wounded ally when healing is available.
	var patient: RuneUnit = find_heal_target() if heal_amount > 0.0 and attack_timer <= 0.0 else null
	if is_instance_valid(patient):
		start_action(patient, true)
		return

	if not is_instance_valid(target) or target.is_dead:
		target = find_nearest_enemy()
	if not is_instance_valid(target):
		play_idle()
		return

	var direction := target.global_position - global_position
	direction.y = 0.0
	var distance := direction.length()
	if distance > 0.01:
		rotation.y = atan2(direction.x, direction.z)

	if distance <= attack_range + REACH_EPSILON:
		if attack_timer <= 0.0:
			start_action(target, false)
		else:
			# Keep a stable position while waiting to strike.
			play_idle()
		return

	# Aim slightly inside the attack radius, not exactly at its edge.
	var forward := direction.normalized()
	var stop_distance := maxf(0.0, attack_range - APPROACH_INSET)
	var effective_speed := move_speed
	if statuses.has("chill"):
		effective_speed *= 1.0 - float(statuses["chill"].power)
	var step := minf(effective_speed * delta, distance - stop_distance)
	var separation := separation_offset(delta)
	# Preserve sideways avoidance without cancelling approach progress.
	separation -= forward * separation.dot(forward)
	var movement := forward * step + separation
	global_position += movement.limit_length(effective_speed * delta)
	play_walk()


func start_action(victim: RuneUnit, healing: bool) -> void:
	attack_timer = maxf(0.05, attack_interval)
	pending_hit = maxf(0.0, hit_delay)
	action_lock = maxf(attack_lock_time, pending_hit)
	attack_target = victim
	pending_heal = healing
	if not healing and not first_attack_logged:
		first_attack_logged = true
		print(name, " | FIRST ATTACK -> ", victim.name, " | clip: ", attack_animation)
	var direction := victim.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.0001:
		rotation.y = atan2(direction.x, direction.z)
	play_animation(cast_animation if healing else attack_animation, true)


func resolve_hit() -> void:
	var victim := attack_target
	var healing := pending_heal
	attack_target = null
	pending_heal = false
	if not is_instance_valid(victim) or victim.is_dead:
		return
	var offset := victim.global_position - global_position
	offset.y = 0.0
	var reach := heal_range if healing else attack_range
	if offset.length() > reach + 0.25:
		return
	if healing and victim.team == team:
		if effects_engine != null:
			effects_engine.heal(self, victim, heal_amount)
		else:
			victim.receive_heal(heal_amount)
	elif not healing and victim.team != team:
		if effects_engine != null:
			effects_engine.attack(self, victim, attack_damage)
		else:
			victim.take_damage(attack_damage)


func find_heal_target() -> RuneUnit:
	var patient: RuneUnit = null
	var lowest_ratio: float = 1.0
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as RuneUnit
		if unit == null or unit.is_dead or unit.team != team:
			continue
		var offset := unit.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() > heal_range * heal_range:
			continue
		# Avoid wasting a full action on a tiny scratch.
		if unit.max_health - unit.health < minf(heal_amount * 0.5, unit.max_health * 0.15):
			continue
		var ratio := unit.health / maxf(1.0, unit.max_health)
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			patient = unit
	return patient


func receive_heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var restored := minf(amount, max_health - health)
	if restored <= 0.0:
		return 0.0
	health += restored
	update_health_bar()
	show_damage(restored, true)
	return restored


func add_shield(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	shield = minf(max_health * 0.4, shield + amount)
	refresh_effect_label()


func finish_battle() -> void:
	battle_active = false
	attack_target = null
	pending_hit = -1.0
	pending_heal = false
	if not is_dead:
		play_idle()


func find_nearest_enemy() -> RuneUnit:
	var nearest: RuneUnit = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as RuneUnit
		if unit == null or unit == self or unit.team == team or unit.is_dead:
			continue
		var offset := unit.global_position - global_position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest


func separation_offset(delta: float) -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as RuneUnit
		if unit == null or unit == self or unit.is_dead or unit.team != team:
			continue
		var away := global_position - unit.global_position
		away.y = 0.0
		var distance := away.length()
		if distance >= separation_radius:
			continue
		if distance < 0.001:
			away = Vector3(0.0, 0.0, 1.0 if get_instance_id() > unit.get_instance_id() else -1.0)
		else:
			away /= distance
		push += away * (separation_radius - distance) * 2.0
	return push.limit_length(move_speed * 0.5) * delta


func take_damage(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var blocked := minf(shield, amount)
	shield -= blocked
	if blocked > 0.0:
		refresh_effect_label()
		if is_equal_approx(blocked, amount):
			effect_notice("BLOCK", Color("8fd8ff"))
	var actual_damage := minf(health, amount - blocked)
	health = maxf(0.0, health - actual_damage)
	update_health_bar()
	if actual_damage > 0.0:
		show_damage(actual_damage)
	if health <= 0.0:
		die()
	elif actual_damage > 0.0 and pending_hit < 0.0 and action_lock <= 0.0 and attack_timer > 0.25:
		action_lock = 0.25
		play_animation(hit_animation, true)
	return actual_damage


func die() -> void:
	is_dead = true
	target = null
	attack_target = null
	pending_hit = -1.0
	if is_instance_valid(health_bar):
		health_bar.hide()
	if is_instance_valid(effects_label):
		effects_label.hide()
	play_death()
	print(name, " defeated")
	pending_heal = false


func create_health_bar() -> void:
	bar_image = Image.create(64, 8, false, Image.FORMAT_RGBA8)
	bar_texture = ImageTexture.create_from_image(bar_image)
	health_bar = Sprite3D.new()
	health_bar.name = "HealthBar"
	health_bar.texture = bar_texture
	health_bar.pixel_size = 0.018
	health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# HUD feedback should remain visible even in crowded fights.
	health_bar.no_depth_test = true
	health_bar.position = Vector3(
		health_bar_offset_x,
		feedback_height,
		health_bar_offset_z
	)
	add_child(health_bar)
	update_health_bar()


func update_health_bar() -> void:
	if not is_instance_valid(health_bar):
		return
	bar_image.fill(Color("202829"))
	var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	var width := roundi(60.0 * ratio)
	var color := Color("8ddb9c") if team == 0 else Color("e47770")
	if width > 0:
		bar_image.fill_rect(Rect2i(2, 2, width, 4), color)
	bar_texture.update(bar_image)


func show_damage(amount: float, healing: bool = false) -> void:
	var label := Label3D.new()
	var number := str(roundi(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount
	label.text = ("+" if healing else "-") + number
	label.font_size = 48
	label.outline_size = 9
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("8ddb9c") if healing else Color("ffc6a0")
	# Sibling in the arena: the number does not follow a moving unit.
	get_parent().add_child(label)
	# Start above the same anchor as the health bar, in world space.
	label.global_position = health_bar.global_position + Vector3.UP * 0.65
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3.UP * 0.8, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_delay(0.15)
	await tween.finished
	label.queue_free()


func set_loop(animation_name: String, enabled: bool) -> void:
	if not animation_name.is_empty() and animation_player.has_animation(animation_name):
		var animation := animation_player.get_animation(animation_name)
		animation.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE


func play_animation(animation_name: String, restart: bool = false) -> void:
	if not is_instance_valid(animation_player):
		return
	if animation_name.is_empty() or not animation_player.has_animation(animation_name):
		return
	if animation_player.current_animation == animation_name and animation_player.is_playing():
		if not restart:
			return
		animation_player.stop()
	animation_player.play(animation_name, 0.12)


func play_idle() -> void:
	play_animation(idle_animation)


func play_walk() -> void:
	play_animation(walk_animation)


func play_death() -> void:
	play_animation(death_animation, true)


func apply_definition() -> void:
	if definition != null:
		class_id = definition.id
		if definition.use_default_effects:
			for rule_id in RuneEffectEngine.Catalog.DEFAULTS.get(class_id, []):
				effect_ids.append(rule_id)
		for rule_id in definition.effect_ids:
			if not effect_ids.has(rule_id):
				effect_ids.append(rule_id)
	else:
		effect_ids.append("ember_spell")
	for rule_id in team_effect_ids:
		if not RuneEffectEngine.Catalog.RULES.has(rule_id):
			push_warning("Unknown effect: " + rule_id)
		elif not effect_ids.has(rule_id):
			effect_ids.append(rule_id)
	if definition == null:
		attack_damage *= damage_multiplier
		return
	unit_name = definition.display_name
	max_health = definition.max_health
	attack_damage = definition.attack_damage * damage_multiplier
	move_speed = definition.move_speed
	attack_range = definition.attack_range
	attack_interval = definition.attack_interval
	hit_delay = definition.hit_delay
	attack_lock_time = definition.attack_lock_time
	heal_amount = definition.heal_amount
	heal_range = definition.heal_range
	feedback_height = definition.feedback_height
	var visual := $Visual as Node3D
	if definition.model_scene != null:
		var replacement := definition.model_scene.instantiate()
		if replacement is Node3D:
			for child in visual.get_children():
				visual.remove_child(child)
				child.queue_free()
			visual.add_child(replacement)
		else:
			replacement.free()
			push_warning("Model Scene must contain a Node3D root: " + unit_name)
	visual.scale *= maxf(0.01, definition.visual_scale)
	visual.position.y += definition.visual_y_offset
	visual.rotation.y += deg_to_rad(definition.visual_yaw_degrees)


func configure_animations() -> void:
	idle_animation = select_clip(idle_animation, PackedStringArray(["Idle", "Idle_Weapon"]), PackedStringArray(["idle"]))
	walk_animation = select_clip(walk_animation, PackedStringArray(["Walk", "Run", "Run_Weapon"]), PackedStringArray(["walk", "run"]))
	var candidates := PackedStringArray(["Attack", "Staff_Attack", "Punch"])
	var preferred := attack_animation
	if definition != null:
		candidates = definition.attack_candidates
		preferred = definition.attack_animation
		cast_animation = definition.heal_animation
	attack_animation = select_clip(preferred, candidates, PackedStringArray(["attack", "shoot", "spell", "punch"]))
	cast_animation = select_clip(cast_animation, PackedStringArray(["Spell1", "Spell2"]), PackedStringArray(["spell", "cast", "heal"]))
	if cast_animation.is_empty():
		cast_animation = attack_animation
	hit_animation = select_clip(hit_animation, PackedStringArray(["RecieveHit", "ReceiveHit"]), PackedStringArray(["hit"]))
	death_animation = select_clip(death_animation, PackedStringArray(["Death", "Die"]), PackedStringArray(["death", "die"]))
	if attack_animation.is_empty():
		push_warning("No attack animation for " + unit_name + ": " + str(animation_player.get_animation_list()))
	print(name, " | ANIMATIONS | idle: ", idle_animation, " | walk: ", walk_animation, " | attack: ", attack_animation, " | available: ", animation_player.get_animation_list())
	if definition != null and not definition.attack_animation.is_empty() and attack_animation != definition.attack_animation:
		push_warning("Requested attack clip not found: " + definition.attack_animation + " for " + unit_name)


func select_clip(preferred: String, candidates: PackedStringArray, tokens: PackedStringArray) -> String:
	if not preferred.is_empty() and animation_player.has_animation(preferred):
		return preferred
	var names := animation_player.get_animation_list()
	for candidate in candidates:
		for clip in names:
			if clip.to_lower() == candidate.to_lower():
				return clip
	for token in tokens:
		for clip in names:
			var lower: String = clip.to_lower()
			if token in lower and (token == "idle" or not ("idle" in lower)):
				return clip
	return ""


func create_effect_label() -> void:
	effects_label = Label3D.new()
	effects_label.name = "EffectsLabel"
	effects_label.font_size = 32
	effects_label.outline_size = 7
	effects_label.pixel_size = 0.007
	effects_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	effects_label.no_depth_test = true
	effects_label.modulate = Color("e6edff")
	effects_label.position = health_bar.position + Vector3.UP * 0.32
	add_child(effects_label)
	refresh_effect_label()


func refresh_effect_label() -> void:
	if not is_instance_valid(effects_label):
		return
	if is_dead:
		effects_label.hide()
		return
	var parts := PackedStringArray()
	if shield > 0.05:
		parts.append("SH %d" % ceili(shield))
	for kind in ["burn", "poison", "chill", "freeze"]:
		if statuses.has(kind):
			parts.append(kind.to_upper())
	effects_label.text = " · ".join(parts)
	effects_label.visible = not parts.is_empty()


func effect_notice(message: String, color: Color) -> void:
	if not is_instance_valid(health_bar):
		return
	var label := Label3D.new()
	label.text = message
	label.font_size = 40
	label.outline_size = 8
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	get_parent().add_child(label)
	label.global_position = health_bar.global_position + Vector3.UP * 1.0
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3.UP * 0.65, 0.85)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.35)
	await tween.finished
	label.queue_free()
