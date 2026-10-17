extends CharacterBody2D
class_name WanderingNPC
## NPC that wanders around with directional idle and walk animations.
## Prefers walking on path tiles rather than aimlessly wandering.
## Spritesheet layout: 4 sub-frames per row (horizontal), 12 rows (vertical).
##   4 directions x 3 frame-rows each = 12 rows.
##   Each row has 4 sub-poses for a smooth walk cycle.

enum Direction { DOWN = 0, LEFT = 1, RIGHT = 2, UP = 3 }

# --- Exports ---
@export var npc_name: String = "NPC"
@export var spritesheet: Texture2D
@export var frame_width: int = 17
@export var frame_height: int = 23
@export var move_speed: float = 40.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
@export var walk_time_min: float = 1.5
@export var walk_time_max: float = 3.5
@export var path_check_distance: float = 48.0  ## How far ahead to check for path tiles

# --- State ---
enum State { IDLE, WALKING }
var _state: State = State.IDLE
var _current_direction: Direction = Direction.DOWN
var _state_timer: float = 0.0
var _anim_timer: float = 0.0
var _current_subframe: int = 0

# --- Path-following ---
var _ground_tilemap: TileMapLayer = null
## Atlas Y coordinates that represent path tiles (not grass).
const PATH_ATLAS_Y: Array[int] = [12, 14, 15, 16, 17]

# --- Nodes ---
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interaction_area: Area2D = $InteractionArea

const DIRECTION_NAMES: Array[String] = ["down", "left", "right", "up"]
const DIRECTION_VECTORS: Array[Vector2] = [
	Vector2.DOWN,
	Vector2.LEFT,
	Vector2.RIGHT,
	Vector2.UP,
]
const SUBFRAMES_PER_ROW: int = 4
const WALK_FRAME_DURATION: float = 0.12
const IDLE_FRAME_DURATION: float = 0.4


func _ready() -> void:
	add_to_group("npc")

	if spritesheet:
		_sprite.texture = spritesheet
		_sprite.region_enabled = true
		_update_sprite_region()

	_interaction_area.body_entered.connect(_on_body_entered)
	_interaction_area.body_exited.connect(_on_body_exited)
	var eb: Node = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("interact_pressed"):
		eb.interact_pressed.connect(_on_interact_pressed)

	_find_ground_tilemap()
	_enter_state(State.IDLE)


func _find_ground_tilemap() -> void:
	var parent: Node = get_parent()
	if parent:
		_ground_tilemap = parent.get_node_or_null("Ground") as TileMapLayer


## Returns the atlas Y at a world position, or -1 if no tile.
func _get_atlas_y_at(world_pos: Vector2) -> int:
	if not _ground_tilemap:
		return -1
	var cell: Vector2i = _ground_tilemap.local_to_map(world_pos)
	var coords: Vector2i = _ground_tilemap.get_cell_atlas_coords(cell)
	if coords.x < 0 and coords.y < 0:
		return -1
	return coords.y


## Returns true if the tile at world_pos is a path tile.
func _is_path(world_pos: Vector2) -> bool:
	return _get_atlas_y_at(world_pos) in PATH_ATLAS_Y


func _update_sprite_region() -> void:
	var row: int
	var col: int
	if _state == State.IDLE:
		row = 0
		col = 0
	else:
		@warning_ignore("integer_division")
		row = _current_subframe / 4
		col = _current_subframe % 4

	var frame_row: int = _current_direction * 3 + row
	_sprite.region_rect = Rect2(col * frame_width, frame_row * frame_height, frame_width, frame_height)


func _enter_state(new_state: State) -> void:
	_state = new_state
	_current_subframe = 0
	_anim_timer = 0.0
	match _state:
		State.IDLE:
			velocity = Vector2.ZERO
			_state_timer = randf_range(idle_time_min, idle_time_max)
		State.WALKING:
			_pick_direction()
			_state_timer = randf_range(walk_time_min, walk_time_max)
	_update_sprite_region()


## Pick a walking direction, preferring path tiles.
func _pick_direction() -> void:
	var dirs: Array[Dictionary] = [
		{"vec": Vector2.DOWN,  "dir": Direction.DOWN},
		{"vec": Vector2.LEFT,  "dir": Direction.LEFT},
		{"vec": Vector2.RIGHT, "dir": Direction.RIGHT},
		{"vec": Vector2.UP,    "dir": Direction.UP},
	]

	# Score each direction: +3 if it leads to a path, +1 baseline
	var scored: Array[Dictionary] = []
	for d: Dictionary in dirs:
		var check_pos: Vector2 = global_position + d["vec"] * path_check_distance
		var score: int = 3 if _is_path(check_pos) else 1
		# Bonus if currently on a path and continuing on it
		if _is_path(global_position) and _is_path(check_pos):
			score += 2
		scored.append({"dir": d["dir"], "vec": d["vec"], "score": score})

	# Weighted random selection
	var total: int = 0
	for s: Dictionary in scored:
		total += s["score"]

	var roll: int = randi() % total
	var cumulative: int = 0
	for s: Dictionary in scored:
		cumulative += s["score"]
		if roll < cumulative:
			_current_direction = s["dir"]
			return

	# Fallback
	_current_direction = Direction.DOWN


func _physics_process(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_toggle_state()

	_anim_timer += delta
	var frame_dur: float = WALK_FRAME_DURATION if _state == State.WALKING else IDLE_FRAME_DURATION
	var max_subframes: int = 12 if _state == State.WALKING else 4
	if _anim_timer >= frame_dur:
		_anim_timer -= frame_dur
		_current_subframe = (_current_subframe + 1) % max_subframes
		_update_sprite_region()

	if _state == State.WALKING:
		velocity = DIRECTION_VECTORS[_current_direction] * move_speed
	else:
		velocity = Vector2.ZERO

	z_index = int(global_position.y)
	move_and_slide()


func _toggle_state() -> void:
	if _state == State.IDLE:
		_enter_state(State.WALKING)
	else:
		_enter_state(State.IDLE)


# --- Interaction ---
var _player_in_range: bool = false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _on_interact_pressed() -> void:
	if not _player_in_range:
		return
	call_deferred("_start_dialogue")


func _start_dialogue() -> void:
	var dm: Node = get_node("/root/DialogueManager")
	if dm and dm.has_method("start"):
		var fallback: DialogueLineData = DialogueLineData.new()
		fallback.speaker_name = npc_name
		fallback.text = "Hello there! I am " + npc_name + "."
		dm.start([fallback], "0")
