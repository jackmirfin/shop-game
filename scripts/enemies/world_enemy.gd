class_name WorldEnemy
extends CharacterBody2D
## Roaming overworld enemy, shared by every ground or flying world enemy.
##
## This is the OVERWORLD entity only: it wanders inside a small radius, and when the
## player physically touches its EncounterTrigger it plays its own approach animation.
## Combat begins at the frame where that strike visually lands.
##
## It never deals combat damage itself, never chases, and never talks to combat
## internals — it only asks the EncounterManager (autoload) for a battle, handing it
## the enemy's own combat configuration so each enemy fights as it should.
##
## Animation names are supplied per enemy (see the exported tables below), because an
## enemy's scene decides what it can play: the spider walks and has idle/an attack, the
## moth only has directional flight plus a death. Left is always the right-facing
## animation flipped, matching the project's convention.
##
## Collision:
##   body   layer 2  mask 1  -> collides with terrain and the player's body
##   trigger layer 0 mask 4   -> monitors ONLY the player's encounter layer bit

enum EncounterState {
	ROAMING,
	STARTING_COMBAT,
	IN_COMBAT,
	RESOLVING_VICTORY,
	DEFEATED,
	## Spotted the player and is scuttling in to striking range. It will NOT swing
	## from a distance: combat only starts once it is close enough to strike.
	CLOSING,
	RETURNING_HOME,
}

const CARDINAL: Dictionary = {
	"down": Vector2.DOWN,
	"right": Vector2.RIGHT,
	"up": Vector2.UP,
	"left": Vector2.LEFT,
}
## Keys selecting which animation table an enemy should use. Named so the call sites
## read the same for every enemy, whatever that scene calls its animations.
const IDLE_PREFIX: String = "idle"
const WALK_PREFIX: String = "walk"
## Compass directions the spider may wander in. Eight keeps the motion organic;
## the facing (and therefore the animation) uses the dominant axis. Diagonals are
## pre-normalised as literals so this stays a constant expression.
const DIAGONAL: float = 0.7071068
const DIRECTIONS: Array[Vector2] = [
	Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0),
	Vector2(DIAGONAL, DIAGONAL), Vector2(-DIAGONAL, DIAGONAL),
	Vector2(DIAGONAL, -DIAGONAL), Vector2(-DIAGONAL, -DIAGONAL),
]
# --- Tunable roaming values ---
## How far the spider may wander from where it was placed in the level.
@export var roam_radius: float = 48.0
## Sped up from 22: the spider reads as deliberately patrolling rather than
## drifting, while still staying well below the player's 100 px/s.
@export var move_speed: float = 44.0
@export var idle_time_min: float = 0.7
@export var idle_time_max: float = 1.8
@export var direction_time_min: float = 0.9
@export var direction_time_max: float = 2.0
## How far the spider notices the player. Applied to the EncounterTrigger shape at
## runtime, so it spots you from a distance and then closes in.
@export var sight_range: float = 180.0
## Speed while closing on a spotted player: brisker than a patrol, still below the
## player's 100 px/s, so a determined player can outrun it.
@export var chase_speed: float = 70.0
@export var territorial: bool = false
@export var territory_radius: float = 180.0
## Centre-to-centre distance at which it stops closing and swings. Its body (20x14)
## and the player's collide well inside this, so the strike lands at contact.
@export var contact_range: float = 22.0
## Gives up and resumes patrolling if it cannot reach the player in this long.
@export var chase_timeout: float = 4.0
## Stable identity for this placed spider. Reserved for a future world-state /
## save system; this pass keeps defeat in memory only, so it is stored but unused.
@export var encounter_id: String = ""
## Runtime room marker for grouping authored cave encounters; defeats are not persisted.
var dungeon_room_id: int = -1

# --- Animation names, per facing axis ---
# Each enemy supplies what its own scene can actually play. Left always reuses the
# right-facing animation with flip_h, matching the project's sprite convention. The
# spider's values are the defaults, so its scene needs no overrides; the moth — which
# only has directional flight plus a death — overrides every table in its own scene.
@export var idle_anims: Dictionary = {
	"down": &"Idle", "right": &"Idle_right", "up": &"Idle_up", "left": &"Idle_right",
}
@export var walk_anims: Dictionary = {
	"down": &"Walk", "right": &"Walk_right", "up": &"Walk_up", "left": &"Walk_right",
}
## Played as the wind-up before combat starts.
@export var attack_anims: Dictionary = {
	"down": &"Attack", "right": &"Attack_right", "up": &"Attack_up", "left": &"Attack_right",
}
@export var death_animation: StringName = &"Death"
## Frame of the wind-up at which the strike visually lands, and so the frame that
## starts the encounter. Measured from spider.png: Attack and Attack_right peak on
## frame 1, but starting the battle there cut the swing off after a single frame, so
## the hit is delayed to the end of the 4-frame swing, letting the whole attack play.
@export var impact_frame: int = 3

var _state: EncounterState = EncounterState.ROAMING
## The placed position, used as the roaming origin so the spider can never drift
## across the level.
var _home: Vector2 = Vector2.ZERO
## Actual 8-way velocity direction (may be diagonal).
var _move_dir: Vector2 = Vector2.DOWN
## Cardinal axis used to pick the animation.
var _facing_axis: String = "down"
var _idle_left: float = 0.0
var _move_left: float = 0.0
var _target_player: Node2D = null
## Guards against the impact firing twice for one attack.
var _impact_fired: bool = false
## How long the current close-in has been running, against chase_timeout.
var _chase_time: float = 0.0
var _returning_home: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var encounter_trigger: Area2D = $EncounterTrigger

## Emitted once the death animation has completely finished.
signal death_finished


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("encounter_enemy")
	_home = global_position
	_move_dir = DIRECTIONS[randi() % DIRECTIONS.size()]
	_apply_sight_range()
	_apply_animation(animated_sprite, IDLE_PREFIX)
	encounter_trigger.body_entered.connect(_on_trigger_body_entered)
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	_begin_idle()
	if _is_persistently_defeated():
		become_corpse()


## Makes sight_range the single source of truth by resizing this instance's own
## copy of the trigger shape (duplicated, so spiders with different ranges cannot
## affect each other).
func _apply_sight_range() -> void:
	var shape_node: CollisionShape2D = encounter_trigger.get_node_or_null("CollisionShape2D")
	if shape_node == null or not (shape_node.shape is CircleShape2D):
		return
	var circle: CircleShape2D = (shape_node.shape as CircleShape2D).duplicate() as CircleShape2D
	circle.radius = sight_range
	shape_node.shape = circle


func _persistent_enemy_id() -> String:
	if not encounter_id.is_empty():
		return encounter_id
	var scene: Node = get_tree().current_scene
	if scene == null:
		return ""
	return "%s::%s" % [scene.scene_file_path, get_path()]


func _is_persistently_defeated() -> bool:
	if dungeon_room_id >= 0:
		return false
	var state: Node = get_node_or_null("/root/GameState")
	return state != null and state.has_method("is_enemy_defeated") \
		and bool(state.call("is_enemy_defeated", _persistent_enemy_id()))


# --- Public API used by the EncounterManager ---

## The combat configuration this enemy fights with, handed straight to the combat
## scene's begin_encounter() by the EncounterManager. Empty means "an ordinary ground
## battle with no special capabilities", which is what the spider wants.
func combat_config() -> Dictionary:
	return {"enemy_scene": scene_file_path}


## The sprite, so the manager can measure an animation's real length.
func animation_sprite() -> AnimatedSprite2D:
	return animated_sprite


func current_state() -> EncounterState:
	return _state


## Called once combat has been won: stop dead and disable BOTH collision shapes
## before the overworld is revealed, so the spider can never be walked into or
## trigger anything again for the rest of the finisher.
func freeze_for_finisher() -> void:
	_state = EncounterState.RESOLVING_VICTORY
	velocity = Vector2.ZERO
	_move_left = 0.0
	_idle_left = 0.0
	_disable_collisions()


## Plays the complete death animation from frame zero, exactly once, and never
## loops or falls back to idle. Returns the animation's name for timing.
func play_death() -> StringName:
	_state = EncounterState.DEFEATED
	velocity = Vector2.ZERO
	_disable_collisions()
	animated_sprite.flip_h = false
	animated_sprite.frame = 0
	animated_sprite.play(death_animation)
	return death_animation


## Called once the death animation has finished. Rather than deleting the spider,
## it is left in the world as a corpse held on the final frame: inert, no longer
## colliding, no longer an enemy, and unable to start another encounter.
func become_corpse() -> void:
	_state = EncounterState.DEFEATED
	if dungeon_room_id < 0:
		var state: Node = get_node_or_null("/root/GameState")
		if state != null and state.has_method("mark_enemy_defeated"):
			state.call("mark_enemy_defeated", _persistent_enemy_id())
	velocity = Vector2.ZERO
	_move_left = 0.0
	_idle_left = 0.0
	_disable_collisions()
	# Hold the last death frame explicitly, so the corpse can never flick back to
	# an idle or walking pose.
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(death_animation):
		animated_sprite.pause()
		animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count(death_animation) - 1
	remove_from_group("enemy")
	remove_from_group("encounter_enemy")
	add_to_group("corpse")
	set_physics_process(false)


## The frame of the attack at which the strike visually lands.
func attack_impact_frame() -> int:
	return impact_frame


## Plays the attack animation toward a world point WITHOUT any encounter
## transition. Used by the encounter manager for the overworld defeat sequence,
## where the spider strikes a defeated player but no new battle may start (the
## frame/impact handlers only act while STARTING_COMBAT, so this is inert).
## Returns the animation name so the caller can time it.
func play_attack_at(target: Vector2) -> StringName:
	_move_dir = global_position.direction_to(target)
	_apply_facing()
	var anim: StringName = _anim_name(attack_anims, _facing_axis)
	if not (animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim)):
		push_warning("WorldEnemy: wind-up animation '%s' is missing on %s." % [anim, name])
		return &""
	animated_sprite.frame = 0
	animated_sprite.play(anim)
	return anim


## Used if an encounter ends without the spider being removed, so it can wander
## again instead of staying frozen.
func return_to_roaming() -> void:
	if _state == EncounterState.DEFEATED:
		return
	_state = EncounterState.ROAMING
	_target_player = null
	_impact_fired = false
	_chase_time = 0.0
	velocity = Vector2.ZERO
	# A spider that survived a sequence (for instance one that defeated the player)
	# is a live obstacle and a live pair of eyes again.
	_enable_collisions()
	_begin_idle()


# --- Roaming ---

func _physics_process(delta: float) -> void:
	# Closing on a spotted player: move in, and never swing from a distance.
	if _state == EncounterState.CLOSING:
		_update_closing(delta)
		return
	if _returning_home:
		_update_return_home()
		return

	# Not roaming: never move, never change the animation. This is what keeps the
	# spider frozen during combat and during the victory finisher's death anim.
	if _state != EncounterState.ROAMING:
		velocity = Vector2.ZERO
		return

	# Defensive re-check. body_entered only fires on entry, so a player who is
	# already inside the sight radius when a cooldown ends — or whose approach was
	# refused because another battle was starting — would otherwise never be
	# noticed. This also debounces repeated entered signals.
	if _try_acquire_player():
		return

	if _idle_left > 0.0:
		_idle_left -= delta
		velocity = Vector2.ZERO
		_apply_animation(animated_sprite, IDLE_PREFIX)
		return

	_move_left -= delta
	if _move_left <= 0.0:
		_begin_idle()
		return

	# Steer back if wandering has taken the spider near the edge of its radius.
	var away: Vector2 = _home - global_position
	if away.length() > roam_radius * 0.8:
		_move_dir = away.normalized()

	velocity = _move_dir * move_speed
	move_and_slide()

	# A wall is a direction change, never an encounter.
	if is_on_wall():
		_pick_direction()

	_apply_animation(animated_sprite, WALK_PREFIX)


func _begin_idle() -> void:
	velocity = Vector2.ZERO
	_idle_left = randf_range(idle_time_min, idle_time_max)
	# The next walking stretch gets its own duration up front, so the frame the
	# idle expires is guaranteed to have a positive move time to spend.
	_move_left = randf_range(direction_time_min, direction_time_max)
	_apply_animation(animated_sprite, IDLE_PREFIX)


func _pick_direction() -> void:
	var options: Array[Vector2] = []
	var home_dir: Vector2 = _home - global_position
	var outward: bool = home_dir.length() > roam_radius * 0.6
	for d: Vector2 in DIRECTIONS:
		if outward and d.dot(home_dir.normalized()) < 0.2:
			continue  # heading further out while already far: skip
		options.append(d)
	if options.is_empty():
		options = DIRECTIONS.duplicate()
	_move_dir = options[randi() % options.size()]
	# A fresh direction always gets its own walking stretch, so hitting a corner
	# cannot make the spider vibrate between two directions.
	_move_left = randf_range(direction_time_min, direction_time_max)


## The animation this enemy should play for its current facing, taken from one of its
## own name tables. Left always reuses the right-facing animation.
func _anim_name(table: Dictionary, axis: String) -> StringName:
	return StringName(str(table.get(axis, "")))


## Switches to the right animation for the enemy's current facing. `kind` selects which
## of the enemy's own tables to use, so call sites read the same for every enemy.
func _apply_animation(sprite: AnimatedSprite2D, kind: String) -> void:
	_facing_axis = _axis_of(_move_dir)
	sprite.flip_h = _facing_axis == "left"
	var table: Dictionary = idle_anims if kind == IDLE_PREFIX else walk_anims
	var anim: StringName = _anim_name(table, _facing_axis)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) \
			and sprite.animation != anim:
		sprite.play(anim)


# --- Encounter detection ---

func _on_trigger_body_entered(body: Node2D) -> void:
	if _state != EncounterState.ROAMING:
		return  # Already closing on someone, fighting, or dead.
	# Structural identification: the trigger's mask already limits it to the
	# player's encounter layer, and the group check keeps it honest.
	if not body.is_in_group("player"):
		return
	_begin_closing(body)


## Returns true if a player already inside the sight radius was noticed. Keeps the
## approach reliable regardless of signal timing, and debounces repeated entered
## signals. (No attack: it only begins closing.)
func _try_acquire_player() -> bool:
	if _state != EncounterState.ROAMING or not encounter_trigger.monitoring:
		return false
	for body: Node2D in encounter_trigger.get_overlapping_bodies():
		if body.is_in_group("player"):
			_begin_closing(body)
			return true
	return false


## Spots the player and starts moving in. Combat is deliberately NOT started here:
## the spider has to reach striking range first.
func _begin_closing(player: Node2D) -> void:
	if _state == EncounterState.CLOSING:
		return
	var manager: Node = _encounter_manager()
	if manager == null or not manager.can_start_encounter():
		return  # Another fight is running, or the global cooldown is active.
	_state = EncounterState.CLOSING
	_target_player = player
	_chase_time = 0.0
	_impact_fired = false


## Scuttles toward the spotted player and swings once it is in striking range.
## Loses interest if the player outruns its sight or it cannot reach them in time.
func _update_closing(delta: float) -> void:
	if not is_instance_valid(_target_player):
		_lose_interest()
		return
	var to_player: Vector2 = _target_player.global_position - global_position
	var distance: float = to_player.length()
	if territorial and _target_player.global_position.distance_to(_home) > territory_radius:
		_lose_interest()
		_returning_home = true
		return
	if distance > sight_range:
		_lose_interest()   # player escaped the spider's sight
		return
	_chase_time += delta
	if _chase_time > chase_timeout:
		_lose_interest()   # could not get there: give up and patrol again
		return

	if distance <= contact_range:
		velocity = Vector2.ZERO
		var manager: Node = _encounter_manager()
		if manager != null and manager.can_start_encounter():
			if encounter_id == "tutorial_spider" or territorial:
				_state = EncounterState.IN_COMBAT
				if manager.request_encounter(self):
					return
				_state = EncounterState.CLOSING
			_start_attack_sequence(_target_player)
		return

	_move_dir = to_player.normalized()
	velocity = _move_dir * chase_speed
	move_and_slide()
	_apply_animation(animated_sprite, WALK_PREFIX)


func _lose_interest() -> void:
	_state = EncounterState.ROAMING
	_returning_home = false
	_target_player = null
	_chase_time = 0.0
	velocity = Vector2.ZERO
	_begin_idle()


func _update_return_home() -> void:
	var to_home: Vector2 = _home - global_position
	if to_home.length() <= 6.0:
		_returning_home = false
		global_position = _home.round()
		velocity = Vector2.ZERO
		_begin_idle()
		return
	_move_dir = to_home.normalized()
	velocity = _move_dir * move_speed
	move_and_slide()
	_apply_animation(animated_sprite, WALK_PREFIX)


func _start_attack_sequence(player: Node2D) -> void:
	_state = EncounterState.STARTING_COMBAT
	_target_player = player
	_impact_fired = false
	velocity = Vector2.ZERO
	# Face the player, then strike.
	_move_dir = global_position.direction_to(player.global_position)
	_apply_facing()
	var anim: StringName = _anim_name(attack_anims, _facing_axis)
	if not (animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim)):
		# Missing wind-up animation: report it and fall back to a clean exit rather
		# than leaving the enemy stuck in STARTING_COMBAT forever.
		push_warning("WorldEnemy: wind-up animation '%s' is missing on %s; cannot start an encounter." % [anim, name])
		_state = EncounterState.ROAMING
		_begin_idle()
		return
	animated_sprite.frame = 0
	animated_sprite.play(anim)


func _on_animation_frame_changed() -> void:
	if _state != EncounterState.STARTING_COMBAT or _impact_fired:
		return
	if animated_sprite.animation != _anim_name(attack_anims, _facing_axis):
		return
	if animated_sprite.frame < impact_frame:
		return
	_impact_fired = true
	# The strike has to actually land on the player: if they backed out of range
	# during the swing, the spider just goes back to wandering.
	if not _player_in_striking_range():
		_state = EncounterState.ROAMING
		_begin_idle()
		return
	var manager: Node = _encounter_manager()
	if manager == null or not manager.request_encounter(self):
		_state = EncounterState.ROAMING
		_begin_idle()
		return
	_state = EncounterState.IN_COMBAT
	velocity = Vector2.ZERO


func _on_animation_finished() -> void:
	if animated_sprite.animation == death_animation:
		death_finished.emit()
		return
	if _state == EncounterState.STARTING_COMBAT:
		# The swing completed without landing (or the impact signal never came).
		_state = EncounterState.ROAMING
		_begin_idle()


## True while the player is still within striking distance, so a swing that whiffs
## (the player backed off during the attack) does not start a battle.
func _player_in_striking_range() -> bool:
	if not is_instance_valid(_target_player):
		return false
	return global_position.distance_to(_target_player.global_position) <= contact_range


# --- Helpers ---

func _apply_facing() -> void:
	_facing_axis = _axis_of(_move_dir)
	animated_sprite.flip_h = _facing_axis == "left"


func _axis_of(dir: Vector2) -> String:
	if is_zero_approx(dir.x) and is_zero_approx(dir.y):
		return "down"
	if absf(dir.x) >= absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func _disable_collisions() -> void:
	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if body_shape:
		body_shape.set_deferred("disabled", true)
	var trigger_shape: CollisionShape2D = encounter_trigger.get_node_or_null("CollisionShape2D")
	if trigger_shape:
		trigger_shape.set_deferred("disabled", true)
	encounter_trigger.set_deferred("monitoring", false)


func _enable_collisions() -> void:
	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if body_shape:
		body_shape.set_deferred("disabled", false)
	var trigger_shape: CollisionShape2D = encounter_trigger.get_node_or_null("CollisionShape2D")
	if trigger_shape:
		trigger_shape.set_deferred("disabled", false)
	encounter_trigger.set_deferred("monitoring", true)


func _encounter_manager() -> Node:
	return get_node_or_null("/root/EncounterManager")


# --- Inherited signal shims ---
# spider.tscn wires Sight.body_entered / body_exited to these method names. The
# overworld spider does not chase, and the inherited Sight shape is disabled in
# world_spider.tscn, so both are deliberately inert: they exist only so the
# inherited connections still resolve.

func _on_sight_body_entered(_body: Node2D) -> void:
	pass


func _on_sight_body_exited(_body: Node2D) -> void:
	pass