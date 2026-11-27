class_name RuneUnitData
extends Resource

@export var id: String = "wizard"
@export var display_name: String = "Wizard"
@export var model_scene: PackedScene

@export_group("Combat")
@export_range(1.0, 10000.0) var max_health: float = 100.0
@export_range(0.0, 1000.0) var attack_damage: float = 15.0
@export_range(0.1, 10.0) var move_speed: float = 2.5
@export_range(0.5, 10.0) var attack_range: float = 1.6
@export_range(0.1, 10.0) var attack_interval: float = 1.5
@export_range(0.0, 5.0) var hit_delay: float = 0.4
@export_range(0.0, 5.0) var attack_lock_time: float = 0.9
@export_range(0.0, 1000.0) var heal_amount: float = 0.0
@export_range(0.5, 10.0) var heal_range: float = 4.0

@export_group("Visual")
@export var feedback_height: float = 3.7
@export var visual_scale: float = 1.0
@export var visual_y_offset: float = 0.0
@export var visual_yaw_degrees: float = 0.0
@export var attack_animation: String = ""
@export var attack_candidates: PackedStringArray = PackedStringArray(["Staff_Attack", "Attack", "Punch"])
@export var heal_animation: String = "Spell1"

@export_group("Effects")
@export var use_default_effects: bool = true
@export var effect_ids: PackedStringArray = PackedStringArray()
