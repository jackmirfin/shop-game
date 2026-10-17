class_name WorldSkeleton
extends WorldEnemy
## Roaming overworld skeleton.
##
## It shares all of the roaming and encounter machinery (this class inherits
## WorldEnemy), and its scene's animation names already follow the project's standard
## convention — Idle / Walk / Attack with "", "_right" and "_up" variants, plus Death —
## so it needs no animation-table overrides at all. The combat screen therefore plays
## exactly the same animations its overworld sprite does, through the shared machinery.
##
## Its fight is an ordinary ground battle — no Flight, no Strength, no multi-hit
## flurries — with its own lighter moveset and its own health.

const COMBAT_SCALE: float = 9.0
## Placed so its visible art sits clear of the enemy health bar and above the hand.
const COMBAT_POSITION: Vector2 = Vector2(828, 440)

## How hard the skeleton hits, what it does, and how much it can take. Drawn at random
## from the pool, never repeating back-to-back.
const MOVESET: Array[int] = [
	CombatTest.EnemyAction.ATTACK_2,  # attack for 4
	CombatTest.EnemyAction.ATTACK_1,  # attack for 2
	CombatTest.EnemyAction.DEFEND_3,  # defend for 3
]
const MAX_HP: int = 14


const SKELETON_SCENE: String = "res://scenes/enemies/skeleton.tscn"


## The skeleton's fight as plain data, so a standalone test scene can run it without a
## placed skeleton to ask. combat_config() below returns exactly this, so there is only
## one description of how the skeleton fights. Its animation names already follow the
## project's standard convention, so no animation tables need to travel with it.
static func combat_setup() -> Dictionary:
	return {
		"enemy_type": "skeleton",
		# The combat screen takes its animations straight from this scene.
		"enemy_scene": SKELETON_SCENE,
		"sprite_scale": COMBAT_SCALE,
		"sprite_position": COMBAT_POSITION,
		"max_hp": MAX_HP,
		"intent_pool": MOVESET,
	}


func combat_config() -> Dictionary:
	return combat_setup()