class_name WorldBear
extends WorldEnemy
## Roaming overworld bear.
##
## It shares all of the roaming, sighting and encounter machinery (this class inherits
## WorldEnemy) and its fight is an ordinary ground battle: no Flight, no Strength, no
## multi-hit flurries. What it does have is its own moveset and its own health, both
## handed to the combat screen as encounter data.
##
## Animation names. This scene's animations do NOT follow the project's standard
## naming, so they are declared explicitly rather than inherited:
##   idle_down, idle_left, idle_up, walk_down, walk_right, walk_up,
##   attack_down, attack_left, dying
## The authored back-view animations are used for upward movement.
##
## Facing. The project's convention is that a table's "left" entry reuses the
## right-facing artwork and is mirrored by flip_h. The bear breaks that twice over: its
## IDLE and ATTACK side artwork is drawn facing LEFT, while its WALK side artwork faces
## RIGHT (the two are mirror images of each other — measured from the silhouettes: the
## head apex sits 46% and 48% across the span for idle_left and attack_left, but 55%
## for walk_right, which is idle_left mirrored). The flip is therefore inverted for the
## two tables whose artwork faces the other way, so the bear always faces the way it
## walks.

const COMBAT_SCALE: float = 11.0
const OVERWORLD_DEATH_SCALE: float = 0.82
## Placed so the bear's visible art sits centred under the enemy health bar (which ends
## at y 332) and clear of the hand (which starts at y 575). The art occupies columns
## 1..22 and rows 1..19 of its 34x34 frame, so at this scale it spans roughly
## x 686..929 and y 350..560.
const COMBAT_POSITION: Vector2 = Vector2(868, 532)

## How hard the bear hits, what it does, and how much it can take. Drawn at random from
## the pool, never repeating back-to-back.
const MOVESET: Array[int] = [
	CombatTest.EnemyAction.ATTACK_7,     # attack for 6
	CombatTest.EnemyAction.ATTACK_WEAK,  # attack for 4 and apply 2 Weak to the player
	CombatTest.EnemyAction.ATTACK_6,     # attack for 10
	CombatTest.EnemyAction.DEFEND_2,     # defend for 4
]
## Raised to 25 alongside the heavier blows. The bear is meant to be the fight the player
## cannot win on their own, so it has to comfortably outlast them.
const MAX_HP: int = 25


const BEAR_SCENE: String = "res://bear.tscn"

## Some of this bear's animations are drawn at noticeably different sizes within their
## own sheets. Measured from the artwork itself, the visible bear is 19 source pixels
## tall in idle_down, but 25 in attack_down and 30 in dying — so left alone it would
## swell every time it attacked or died. These multipliers normalise each animation to
## the idle's height, so the bear stays the same size whatever it is doing.
##
## They are applied on top of the enemy's base scale in combat, and on top of the
## scene's own sprite scale in the overworld, so nothing here is baked into the sprite
## frames and no asset needs re-cutting.
const ANIM_SCALES: Dictionary = {
	&"idle_down": 1.0,
	&"idle_left": 1.05,
	&"idle_up": 1.0,
	&"walk_down": 0.68,
	&"walk_right": 0.90,
	&"walk_up": 0.90,
	&"attack_down": 0.76,
	&"attack_left": 0.79,
	&"dying": 0.58,
}

# --- Animation names, declared once ---
# These are constants rather than values set up in _ready(), because the COMBAT screen
# needs them too: it takes the enemy's animation names as encounter data, and a static
# combat_setup() has no instance to read. One description, used by both.
const IDLE_ANIMS: Dictionary = {
	"down": &"idle_down", "right": &"idle_left", "up": &"idle_up", "left": &"idle_left",
}
const WALK_ANIMS: Dictionary = {
	"down": &"walk_down", "right": &"walk_right", "up": &"walk_up", "left": &"walk_right",
}
const ATTACK_ANIMS: Dictionary = {
	"down": &"attack_down", "right": &"attack_left", "up": &"attack_down", "left": &"attack_left",
}
const DEATH_ANIM: StringName = &"dying"
## The scene's own sprite scale, captured in _ready as the baseline that ANIM_SCALES
## multiplies.
var _base_sprite_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	territorial = true
	territory_radius = 180.0
	chase_speed = 90.0
	# Captured before anything can change it: every animation scale is measured from the
	# scene's own sprite scale.
	_base_sprite_scale = animated_sprite.scale
	# Assigned before the base class runs, because the base class picks its opening
	# animation from these tables in its own _ready().
	idle_anims = IDLE_ANIMS
	walk_anims = WALK_ANIMS
	attack_anims = ATTACK_ANIMS
	death_animation = DEATH_ANIM
	super._ready()


## The bear's fight as plain data, so a standalone test scene can run it without a
## placed bear to ask. combat_config() below returns exactly this, so there is only one
## description of how the bear fights.
##
## The animation tables travel with it: without them the combat screen would fall back
## to the project's standard names (Idle / Attack / Death), which this scene does not
## have, and would end up playing the wrong animation.
static func combat_setup() -> Dictionary:
	return {
		"enemy_type": "bear",
		# The combat screen takes its animations straight from this scene.
		"enemy_scene": BEAR_SCENE,
		"sprite_scale": COMBAT_SCALE,
		"sprite_position": COMBAT_POSITION,
		"max_hp": MAX_HP,
		"intent_pool": MOVESET,
		# Per-animation size corrections: some of this bear's animations are drawn larger
		# than others within their own sheets, so this keeps it a consistent size.
		"anim_scales": ANIM_SCALES,
		"idle_anims": IDLE_ANIMS,
		"attack_anims": ATTACK_ANIMS,
		"death_animation": DEATH_ANIM,
	}


func combat_config() -> Dictionary:
	return combat_setup()


# --- Facing -------------------------------------------------------------------
# See the class comment: the bear's idle/attack side art is drawn facing left, which is
# the opposite of what the base class assumes, so those two tables get the flip
# inverted. The walk table follows the normal convention.

func _apply_animation(sprite: AnimatedSprite2D, kind: String) -> void:
	super._apply_animation(sprite, kind)
	# Keep the bear the same size whatever it is doing: several of its animations are
	# drawn larger than others within their own sheets. This is the overworld's share of
	# ANIM_SCALES; the combat screen applies the same table to its own base scale.
	var anim: StringName = sprite.animation
	if ANIM_SCALES.has(anim):
		var animation_scale: float = float(ANIM_SCALES[anim])
		if sprite == animated_sprite and anim == DEATH_ANIM:
			animation_scale *= OVERWORLD_DEATH_SCALE
		sprite.scale = _base_sprite_scale * animation_scale
	# Only the SIDE views are affected. The front-facing art (down/up) is never mirrored,
	# and the walk table already follows the normal convention.
	if _facing_axis in ["left", "right"] and kind != WALK_PREFIX:
		sprite.flip_h = not sprite.flip_h


func _apply_facing() -> void:
	super._apply_facing()
	# _apply_facing is only ever used for the wind-up, which comes from the attack table.
	if _facing_axis in ["left", "right"]:
		animated_sprite.flip_h = not animated_sprite.flip_h
