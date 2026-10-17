class_name WorldMoth
extends WorldEnemy
## Flying overworld moth for the Forest level.
##
## It shares all of the roaming machinery with the ground spider (this class inherits
## WorldEnemy), and differs in two ways:
##
##   * it FLIES, so its scene has no idle or walk animations — only directional
##     flight (down / right / up, with left mirrored) plus a death animation;
##   * it fights with its own combat configuration — Flight, and its multi-hit
##     moveset — instead of a plain ground battle.
##
## The combat setup lives here as the single source of truth: the EncounterManager
## asks this enemy for it, and the standalone combat test scene reuses it too.

const MOTH_AIR: String = "res://assets/Combat/Moth.png"
const MOTH_GROUND: String = "res://assets/Combat/MothDazed.png"
## The moth's own scene — the single source of its overworld and combat animations.
const MOTH_SCENE: String = "res://moth.tscn"
const MOTH_COMBAT_SCALE: float = 7.2
## The grounded spot. Its art is off-centre within its frame, so this is nudged right to
## land the visible moth squarely under the middle of the enemy health bar, and raised to
## keep its combat pose clear of the lower HUD.
const MOTH_COMBAT_POSITION: Vector2 = Vector2(860, 320)
const MOTH_GROUP_COMBAT_Y: float = 320.0
const MOTH_COMBAT_HUD_Y_OFFSET: float = -50.0
const MOTH_GROUP_HEALTH_BAR_EXTRA_RAISE: float = 45.0
const MOTH_COMBAT_AIR_OFFSET: Vector2 = Vector2(0, -12)


## The moth's animation names, shared by its overworld scene and the combat screen, so
## there is one source of truth for both. Left always mirrors the right-facing frames.
const FLIGHT_ANIMS: Dictionary = {
	"down": &"down", "right": &"right", "up": &"up", "left": &"right",
}
const ATTACK_ANIMS: Dictionary = {
	"down": &"attack_down", "right": &"attack_right", "up": &"attack_up", "left": &"attack_right",
}
const DEATH_ANIM: StringName = &"dying"
## The moth's knocked-down animation, played while it is grounded and dazed.
const DAZED_ANIM: StringName = &"dazed"


## How a moth fight is configured. Static so the combat test scene can reuse it
## without needing a moth in the tree.
static func combat_setup() -> Dictionary:
	return {
		"enemy_type": "moth",
		"has_flight": true,
		"max_flight": 3,
		# Moveset: a 4x1 flurry, a plain 5 attack, Defend for 4, and +1 Strength.
		# Turn 1 is always the Strength move; from turn 2 the pool is chosen at random.
		"strengthen_on_turn": 1,
		"multi_hit_actions": [CombatTest.EnemyAction.ATTACK_2],
		"intent_pool": [
			CombatTest.EnemyAction.ATTACK_2,
			CombatTest.EnemyAction.ATTACK_5,
			CombatTest.EnemyAction.DEFEND_2,
			CombatTest.EnemyAction.STRENGTHEN,
		],
		# The flying artwork comes from this scene's own animations, as does the dazed one
		# it plays once knocked down. The combat screen plays exactly these animations.
		"grounded_animation": DAZED_ANIM,
		"idle_anims": FLIGHT_ANIMS,
		"attack_anims": ATTACK_ANIMS,
		"death_animation": DEATH_ANIM,
		# The scene its animations come from. Named here too, so the standalone combat
		# test scene (which has no moth in the tree to ask) uses the moth and not the
		# default spider.
		"enemy_scene": MOTH_SCENE,
		"sprite_scale": MOTH_COMBAT_SCALE,
		"sprite_position": MOTH_COMBAT_POSITION,
		"group_sprite_y": MOTH_GROUP_COMBAT_Y,
		"enemy_hud_y_offset": MOTH_COMBAT_HUD_Y_OFFSET,
		"group_health_bar_y_offset": -MOTH_GROUP_HEALTH_BAR_EXTRA_RAISE,
		"sprite_air_offset": MOTH_COMBAT_AIR_OFFSET,
	}


func combat_config() -> Dictionary:
	var config: Dictionary = combat_setup()
	# The combat screen takes its animations straight from this scene, so it plays the
	# moth's own flight, attack and death animations.
	config["enemy_scene"] = scene_file_path
	return config


func _ready() -> void:
	# In Room 6, all authored moths form one grouped dungeon encounter. Set this before
	# the inherited ready logic so dungeon defeats are excluded from persistence.
	var active_scene: Node = get_tree().current_scene
	if active_scene != null and active_scene.scene_file_path == "res://scenes/cave_rooms/room_6.tscn":
		dungeon_room_id = 6
		# Room 6's mid-room gap is a collision hole in the terrain layer. These cave
		# moths fly through it, so ignore terrain layer 1 while keeping their own enemy
		# layer and the separate EncounterTrigger intact.
		set_collision_mask_value(1, false)
	# Flight only: every facing plays the moth's directional flight animation, and the
	# scene's own "dying" plays when it is defeated. Set before super._ready(), which
	# immediately applies an idle animation. These are the same tables the combat screen
	# uses, so both play identical animations.
	idle_anims = FLIGHT_ANIMS
	walk_anims = FLIGHT_ANIMS
	attack_anims = ATTACK_ANIMS
	death_animation = DEATH_ANIM
	super._ready()