extends RefCounted
# Content definitions: one rule can interact with any compatible source of a status.
const DEFAULTS = {
	"warrior": ["keen_edge"],
	"ranger": ["venom_arrow"],
	"wizard": ["ember_spell"],
	"cleric": ["healing_ward"]
}
const RULES = {
	"keen_edge": {"trigger": "before_attack", "action": "crit", "chance": 0.25, "multiplier": 1.75},
	"venom_arrow": {"trigger": "hit", "action": "status", "status": "poison", "duration": 4.0, "power": 4.0},
	"ember_spell": {"trigger": "hit", "action": "status", "status": "burn", "duration": 3.0, "power": 6.0},
	"healing_ward": {"trigger": "heal", "action": "shield", "factor": 0.35},
	"frost_quiver": {"trigger": "hit", "action": "status", "class_id": "ranger", "status": "chill", "duration": 3.0, "power": 0.30},
	"blood_pact": {"trigger": "hit", "action": "lifesteal", "factor": 0.20},
	"ash_crown": {"trigger": "death", "action": "explosion", "requires_status": "burn", "power": 24.0, "radius": 2.7},
	"echo_stone": {"trigger": "crit", "action": "echo", "factor": 0.35},
	"iron_oath": {"trigger": "battle_start", "action": "shield", "factor": 0.15}
}
const REACTIONS = [
	{"requires": ["burn", "poison"], "name": "TOXIC BLAST", "power": 18.0, "radius": 2.4, "color": "a6e56c"},
	{"requires": ["burn", "chill"], "name": "THERMAL SHOCK", "power": 28.0, "radius": 0.0, "color": "f8ce91"}
]
