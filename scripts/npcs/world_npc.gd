class_name WorldNpc
extends CharacterBody2D
## An ambient townsperson that walks a ROUTE you lay out by hand.
##
## The route is just the Marker2D nodes in the level named after this NPC plus a number
## — OldLady_1, OldLady_2, OldLady_3 — visited in numeric order and then walked back down
## again, so each NPC goes from one checkpoint to the next and back. Placing, moving or
## deleting a marker is the whole editing experience: there is nothing about the route to
## configure in code.
##
## Checkpoints are matched by NAME, searched for across the whole level, and sorted by
## their number — so _2 really does come before _10, whatever order the level lists them
## in, and the markers can sit wherever is convenient (a Y-Sort, a folder of their own).
##
## Movement still LOOKS where it is going: before each step it casts a short ray along
## each candidate heading and discards any that has something solid in it, so an NPC
## steps around a tree, a sign, a building or the player rather than walking into it. With
## the checkpoints laid along clear ground that rarely comes into play, which is the
## point — it is a safety net, not the navigation.
##
## Animation names follow the project's convention — idle / walk with the "_right" and
## "_up" variants, left being the right-facing art flipped — so every NPC scene works
## with this one script and none of them needs overrides.

## Walking pace. Well below the player's, so townsfolk never feel like they are fleeing.
@export var move_speed: float = 34.0
## How close to a checkpoint counts as arrived.
@export var arrive_range: float = 6.0
## How far ahead it looks for things in the way.
@export var sight_distance: float = 28.0
## Seconds paused at each checkpoint before setting off again. Short, because a townsperson
## that lingers at every corner reads as stuck rather than busy; checkpoints that want a
## longer stay say so themselves with their own "wait".
@export var stop_time: float = 1.2
## Turn round at the end and walk the route back, rather than jumping to the start.
@export var ping_pong: bool = true
## What each checkpoint's name begins with. Left empty it uses this node's own name, so
## markers called OldLady_1, OldLady_2 ... simply work.
@export var route_prefix: String = ""
## What this NPC does at particular checkpoints, keyed by the checkpoint's NUMBER as a
## string — the part after the underscore. Every field is optional:
##   "wait":   [10, 20]  seconds to pause here, as a range (a single number works too)
##   "facing": "up"      pose to hold instead of the usual idle; "left" is the
##                       right-facing art flipped
##   "vanish": 20        seconds to disappear for before carrying on — for going into or
##                       coming out of a building
## A checkpoint with no entry pauses for the usual stop_time.
@export var checkpoint_actions: Dictionary = {}
## Side idle animation and artwork orientation can differ between NPC sprite sets.
@export var side_idle_animation: StringName = &"idle_right"
@export var side_idle_art_faces_left: bool = false
@export var initial_facing: String = "down"

## Headings tried each step, spread either side of the straight line to the checkpoint.
const STEER_STEPS: int = 9
## How far either side of that line they may turn, in degrees.
const STEER_SPREAD: float = 85.0
## What counts as "something in the way": the terrain, and anything solid on the body
## layers — which includes the player and other townsfolk. The NPC's own body is excluded
## from its own ray.
const VISION_MASK: int = 1 | 2

## The route, in order.
var _route: Array[Vector2] = []
## The same checkpoints' NUMBERS, so a behaviour can be looked up by the number in the
## marker's name however the route is stored.
var _route_numbers: Array[int] = []
## Which checkpoint it is heading for, and which way along the route it is going.
var _index: int = 0
var _direction: int = 1
var _stop_left: float = 0.0
## Counts down while the NPC is off the map inside a building.
var _vanish_left: float = 0.0
var _last_axis: String = "down"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("npc")
	# NPC scenes carry no collision of their own, so the body builds it: a small box at
	# the feet, which makes a townsperson solid to walk into without walling off a street.
	# Layer 2 against the terrain's layer 1, exactly like the overworld enemies.
	collision_layer = 2
	collision_mask = 1
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var box := RectangleShape2D.new()
		box.size = Vector2(12.0, 8.0)
		shape.shape = box
		shape.position = Vector2(0.0, 6.0)
		add_child(shape)
	_build_route()
	_last_axis = "left" if name == "ElderHolt_NPC" else initial_facing
	_play_idle_for_last_direction(true)


func _physics_process(delta: float) -> void:
	# Off the map, inside (or coming out of) a building. Wait it out where it stands.
	if _vanish_left > 0.0:
		_vanish_left -= delta
		velocity = Vector2.ZERO
		if _vanish_left <= 0.0:
			visible = true
			set_collision_enabled(true)
			_advance()
		return
	# Pausing at a checkpoint.
	if _stop_left > 0.0:
		_stop_left -= delta
		velocity = Vector2.ZERO
		if _stop_left <= 0.0:
			_advance()
		return
	if _route.is_empty():
		# No checkpoints placed yet: an NPC with no route stands about.
		velocity = Vector2.ZERO
		_play_idle_for_last_direction()
		return
	var goal: Vector2 = _route[_index]
	var to: Vector2 = goal - global_position
	if to.length() <= arrive_range:
		velocity = Vector2.ZERO
		_on_checkpoint_reached()
		return
	var heading: Vector2 = _choose_heading(to)
	if heading == Vector2.ZERO:
		# Every direction is blocked from here. Wait it out where it stands rather than
		# grinding against whatever it is; the next step tries again anyway.
		velocity = Vector2.ZERO
		_play_idle_for_last_direction()
		return
	velocity = heading * move_speed
	move_and_slide()
	_face_where_it_walks(heading)


# --- The route ------------------------------------------------------------------

## Collects this NPC's checkpoints from the level: Marker2D nodes named
## "<prefix>_<number>", sorted by that number so the route runs in the order they were
## numbered however the level happens to list them.
func _build_route() -> void:
	var prefix: String = route_prefix if not route_prefix.is_empty() else String(name)
	var found: Array = []
	for node: Node in _level_root().find_children(prefix + "_*", "Marker2D", true, false):
		var suffix: String = String(node.name).substr(prefix.length() + 1)
		if not suffix.is_valid_int():
			continue
		found.append({"number": suffix.to_int(), "at": (node as Node2D).global_position})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["number"]) < int(b["number"]))
	_route.clear()
	_route_numbers.clear()
	for entry: Dictionary in found:
		_route.append(entry["at"])
		_route_numbers.append(int(entry["number"]))
	# Start at the nearest checkpoint, so an NPC placed elsewhere in the village joins its
	# route at the closest point rather than walking back across town first.
	if not _route.is_empty():
		var best: int = 0
		for i in _route.size():
			if global_position.distance_to(_route[i]) < global_position.distance_to(_route[best]):
				best = i
		_index = best


## Moves on to the next checkpoint, turning round at either end of the route.
func _advance() -> void:
	if _route.size() <= 1:
		return
	if not ping_pong:
		_index = (_index + 1) % _route.size()
		return
	_index += _direction
	if _index >= _route.size():
		_direction = -1
		_index = maxi(0, _route.size() - 2)
	elif _index < 0:
		_direction = 1
		_index = mini(1, _route.size() - 1)


# --- What to do at a checkpoint -------------------------------------------------

## Reached a checkpoint: hold whatever pose it asks for, go off the map for a while if it
## is a doorway, and otherwise wait out its pause.
func _on_checkpoint_reached() -> void:
	var action: Dictionary = _checkpoint_action(_index)
	var facing: String = str(action.get("facing", ""))
	if facing.is_empty():
		_play_idle_for_last_direction(true)
	else:
		_face(facing)
	var vanish: float = float(action.get("vanish", 0.0))
	if vanish > 0.0:
		# Going into, or coming back out of, a building: off the map for a while, then
		# it reappears where it went in and carries on down the route.
		visible = false
		set_collision_enabled(false)
		_vanish_left = vanish
		return
	_stop_left = _pause_for(action)


## Holds one of the idle poses. "left" is the right-facing art flipped, matching the
## project's convention — so a checkpoint can ask for idle_right faced left.
func _face(axis: String) -> void:
	_last_axis = axis
	var anim: String = "idle"
	if axis == "up":
		anim = "idle_up"
	elif axis == "right" or axis == "left":
		anim = String(side_idle_animation)
	var left_art: bool = side_idle_art_faces_left
	animated_sprite.flip_h = axis == "right" if left_art else axis == "left"
	_play_anim(StringName(anim), true)


## How long to pause at a checkpoint: its own "wait" when it has one — a single number, or
## a [min, max] range drawn from at random — otherwise the NPC's default stop_time.
func _pause_for(action: Dictionary) -> float:
	var wait: Variant = action.get("wait", null)
	if wait == null:
		return stop_time
	if wait is Array:
		var pair: Array = wait
		if pair.size() >= 2:
			return randf_range(float(pair[0]), float(pair[1]))
		if pair.size() == 1:
			return float(pair[0])
		return stop_time
	return float(wait)


## This checkpoint's entry in checkpoint_actions, looked up by the number in its marker's
## name. Empty when it has none.
func _checkpoint_action(index: int) -> Dictionary:
	if index < 0 or index >= _route_numbers.size():
		return {}
	var entry: Variant = checkpoint_actions.get(str(_route_numbers[index]), null)
	return entry as Dictionary if entry is Dictionary else {}


## Turns the body's collision on or off — for while the NPC is off the map inside a
## building, so nobody walks into an invisible person.
func set_collision_enabled(enabled: bool) -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = not enabled


# --- Looking where it is going --------------------------------------------------

## The heading to move along this step: straight at the checkpoint when the way is clear,
## otherwise the clearest way round what is in the way. ZERO when every direction is
## blocked.
func _choose_heading(to: Vector2) -> Vector2:
	var want: Vector2 = to.normalized()
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for i in STEER_STEPS:
		var amount: float = float(i) / float(STEER_STEPS - 1)
		var offset: float = deg_to_rad(-STEER_SPREAD + STEER_SPREAD * 2.0 * amount)
		var dir: Vector2 = want.rotated(offset)
		if _is_blocked(dir):
			continue
		var score: float = cos(offset)     # 1 straight ahead, less when turned away from it
		if score > best_score:
			best_score = score
			best = dir
	return best


## True when something solid is within sight along `dir`. Cast from the NPC's feet, where
## its collision box sits, so a low obstacle is still noticed — and its own body is
## excluded, or it would see itself.
func _is_blocked(dir: Vector2) -> bool:
	var from: Vector2 = global_position + Vector2(0.0, 6.0)
	var query := PhysicsRayQueryParameters2D.create(
		from, from + dir * sight_distance, VISION_MASK)
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# --- Facing and animation -------------------------------------------------------

func _play_idle_for_last_direction(restart: bool = false) -> void:
	var anim: String = "idle"
	if _last_axis == "up":
		anim = "idle_up"
	elif _last_axis == "left" or _last_axis == "right":
		anim = String(side_idle_animation)
	var left_art: bool = side_idle_art_faces_left
	animated_sprite.flip_h = _last_axis == "right" if left_art else _last_axis == "left"
	_play_anim(StringName(anim), restart)


## Turns to face where it is walking and plays the matching walk. Left is the
## right-facing art flipped, matching the project's convention.
func _face_where_it_walks(to: Vector2) -> void:
	var axis: String = "down"
	if absf(to.x) >= absf(to.y):
		axis = "right" if to.x > 0.0 else "left"
	else:
		axis = "down" if to.y > 0.0 else "up"
	_last_axis = axis
	if axis == "left" or axis == "right":
		animated_sprite.flip_h = axis == "right" if side_idle_art_faces_left else axis == "left"
	else:
		animated_sprite.flip_h = false
	var anim: String = "walk" if axis == "down" else "walk_" + axis
	_play_anim(StringName(anim))


func _play_anim(anim: StringName, restart: bool = false) -> void:
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim):
		return
	if not restart and animated_sprite.animation == anim and animated_sprite.is_playing():
		return
	animated_sprite.play(anim)


## The level this NPC lives in: the topmost ancestor below the scene root, so checkpoint
## names are searched for across the whole level rather than this NPC's own scene.
func _level_root() -> Node:
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node
