extends CharacterBody2D
## Minimal Player — 4-direction movement, collision, directional idle/walk animations, Camera2D follow.

@export var speed: float = 100.0

## Cleared by the encounter system while control is locked (e.g. during a combat
## encounter and its victory finisher). Defaults to true, so normal gameplay is
## completely unaffected by its existence.
var movement_enabled: bool = true

## The player's death animation. It does not loop, so its final frame is held.
const DYING_ANIMATION: StringName = &"dying"

var last_direction: Vector2 = Vector2.DOWN

## Interactable areas the player is currently standing in.
var _interactables: Array[Interactable] = []
var _opening_locked_spider: Node = null

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and get_tree().current_scene.scene_file_path.contains("namura"):
		state.set("has_been_to_namura", true)
	_set_camera_limits()
	_apply_spawn_marker()
	var root: Window = get_tree().root
	if get_tree().current_scene.scene_file_path.contains("namura") \
			and root.has_meta("namura_shop_exit"):
		root.remove_meta("namura_shop_exit")
		var encounter_manager: Node = get_node_or_null("/root/EncounterManager")
		if encounter_manager != null and encounter_manager.has_method("start_blacksmith_intro"):
			encounter_manager.call_deferred("start_blacksmith_intro", self)
	call_deferred("_maybe_show_opening_message")


func _maybe_show_opening_message() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or bool(state.get("opening_message_seen_v2")):
		return
	state.set("opening_message_seen_v2", true)
	set_control_enabled(false)
	_opening_locked_spider = get_tree().current_scene.find_child("WorldSpider", true, false)
	if is_instance_valid(_opening_locked_spider):
		_opening_locked_spider.set_process(false)
		_opening_locked_spider.set_physics_process(false)
	if DialogueManager.has_method("show_system_message"):
		DialogueManager.show_system_message("...The air smells like pie.", 470.0,
			Callable(self, "_finish_opening_message"), 2.5)

func _finish_opening_message() -> void:
	set_control_enabled(true)
	if is_instance_valid(_opening_locked_spider):
		_opening_locked_spider.set_process(true)
		_opening_locked_spider.set_physics_process(true)
	_opening_locked_spider = null


func _apply_spawn_marker() -> void:
	var root: Window = get_tree().root

	# Preferred: named spawn marker (existing transition architecture).
	var target_spawn: String = root.get_meta("target_spawn", "")
	if not target_spawn.is_empty():
		root.remove_meta("target_spawn")
		var marker: Marker2D = get_tree().current_scene.find_child(target_spawn, true, false)
		if marker:
			global_position = marker.global_position
		return

	# Fallback: explicit pixel position (used by Interactable teleports).
	var target_position: Vector2 = root.get_meta("target_position", Vector2.ZERO)
	if target_position != Vector2.ZERO:
		root.remove_meta("target_position")
		global_position = target_position


func _set_camera_limits() -> void:
	var bounds: CameraBounds = get_tree().current_scene.find_child("CameraBounds", true, false)
	if bounds:
		camera.limit_left = bounds.limit_left
		camera.limit_right = bounds.limit_right
		camera.limit_top = bounds.limit_top
		camera.limit_bottom = bounds.limit_bottom
		return

	# Fallback: detect by scene filename
	var scene_path: String = get_tree().current_scene.scene_file_path

	if scene_path.contains("level_1") or scene_path.contains("base_level"):
		camera.limit_left = -14
		camera.limit_right = 703
		camera.limit_top = -50
		camera.limit_bottom = 989
	elif scene_path.contains("Navaria"):
		camera.limit_left = -80
		camera.limit_right = 1376
		camera.limit_top = -80
		camera.limit_bottom = 784
	elif scene_path.contains("shop"):
		camera.limit_left = -1000
		camera.limit_right = 1000
		camera.limit_top = -1000
		camera.limit_bottom = 1000


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if movement_enabled and not _ui_blocks_input():
		direction = Input.get_vector("left", "right", "up", "down")

	if direction != Vector2.ZERO:
		velocity = direction * speed
		last_direction = direction
	else:
		velocity = Vector2.ZERO

	# While control is locked an attack animation may be playing; running the
	# walk/idle update here would overwrite it instantly.
	if movement_enabled:
		_update_animation()
	move_and_slide()


func _update_animation() -> void:
	if velocity != Vector2.ZERO:
		_play_directional("run")
	else:
		_play_directional("idle")


func _play_directional(anim_name: String) -> void:
	if last_direction.x > 0.0:
		# Moving right
		animated_sprite.flip_h = false
		animated_sprite.play(anim_name + "_right")
	elif last_direction.x < 0.0:
		# Moving left — flip the right-facing animation
		animated_sprite.flip_h = true
		animated_sprite.play(anim_name + "_right")
	elif last_direction.y < 0.0:
		# Moving up
		animated_sprite.play(anim_name + "_up")
	else:
		# Moving down (or idle default)
		animated_sprite.play(anim_name + "_down")


# --- Interaction (E) ---

## Called by an Interactable when this player enters its Area2D.
func register_interactable(interactable: Interactable) -> void:
	if interactable not in _interactables:
		_interactables.append(interactable)


## Called by an Interactable when this player leaves its Area2D.
func unregister_interactable(interactable: Interactable) -> void:
	_interactables.erase(interactable)


func _nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_dist: float = INF
	for interactable: Interactable in _interactables:
		if not is_instance_valid(interactable) or not interactable.can_interact():
			continue
		var distance: float = global_position.distance_squared_to(interactable.global_position)
		if distance < best_dist:
			best_dist = distance
			best = interactable
	return best


func _ui_blocks_input() -> bool:
	var ui: Node = get_node_or_null("/root/InteractionUI")
	return ui != null and ui.has_method("blocks_player") and ui.blocks_player()


func _unhandled_input(event: InputEvent) -> void:
	if not movement_enabled:
		return  # Control is locked (an encounter or its finisher owns the player).
	if not event.is_action_pressed("interact"):
		return
	if _ui_blocks_input():
		return  # The open popup consumes its own dismiss input.
	var target: Interactable = _nearest_interactable()
	if target:
		# Mark the input handled BEFORE running the interaction: a TELEPORT
		# interaction calls change_scene_to_file(), which immediately removes
		# this Player from the tree — after which get_viewport() would be null.
		get_viewport().set_input_as_handled()
		target.interact()


# --- Encounter control (driven by the EncounterManager autoload) ---
## These only ever run when an overworld encounter is being resolved. Nothing in
## normal gameplay calls them, and movement_enabled defaults to true.

## Locks or restores player control. Disabling stops all input-driven movement and
## stops the walk/idle update from overwriting an externally played animation.
## This is a top-down setup with no gravity, so zeroing velocity holds position.
func set_control_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_play_directional("idle")


## Turns to face a world point using the dominant axis, playing that direction's
## idle so the turn is visible.
func face_towards(target: Vector2) -> void:
	last_direction = _facing_for(target)
	_play_directional("idle")


## Plays the existing directional attack toward a world point and returns the
## animation name used. Left-facing attacks reuse attack_right with flip_h, which
## is this sprite's existing convention — there is no attack_left row.
func play_attack_towards(target: Vector2) -> String:
	var face: Vector2 = _facing_for(target)
	last_direction = face
	animated_sprite.flip_h = false
	var anim_name: String = "attack_down"
	if face == Vector2.UP:
		anim_name = "attack_up"
	elif face == Vector2.LEFT:
		anim_name = "attack_right"
		animated_sprite.flip_h = true
	elif face == Vector2.RIGHT:
		anim_name = "attack_right"
	if not (animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name)):
		push_warning("Player: attack animation '%s' is missing; the finisher will use its safe fallback." % anim_name)
		return anim_name
	animated_sprite.frame = 0
	animated_sprite.play(anim_name)
	return anim_name


## Plays the death animation, holding its final frame (it does not loop). Used by
## the encounter system when the player is defeated in an overworld fight. The
## facing is left alone, so the player falls as they were standing.
func play_dying() -> StringName:
	velocity = Vector2.ZERO
	if not (animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(DYING_ANIMATION)):
		push_warning("Player: animation '%s' is missing; the defeat sequence uses its safe fallback." % DYING_ANIMATION)
		return &""
	animated_sprite.frame = 0
	animated_sprite.play(DYING_ANIMATION)
	return DYING_ANIMATION


## Returns the sprite to the normal idle for the direction it is facing.
func restore_idle() -> void:
	_play_directional("idle")


## Cardinal facing from the dominant axis of the direction toward a world point.
func _facing_for(target: Vector2) -> Vector2:
	var dir: Vector2 = global_position.direction_to(target)
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y >= 0.0 else Vector2.UP
