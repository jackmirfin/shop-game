class_name SceneTransition
extends Area2D
## Automatic scene transition trigger. Attach to an Area2D, set destination_scene,
## and pick ONE destination method:
##   * spawn_marker_name            — a Marker2D in the destination scene, or
##   * use_target_position + target_position — an explicit pixel position.
## Ensure a CollisionShape2D child exists. Fires when the Player enters the area;
## no key press is required (that is what Interactable is for).

@export var destination_scene: String = ""
@export var spawn_marker_name: String = ""
## Use an explicit pixel destination instead of a spawn marker (e.g. a tile
## coordinate converted to pixels).
@export var use_target_position: bool = false
@export var target_position: Vector2 = Vector2.ZERO

var _transitioning: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Guard against duplicate body_entered firing while the scene is changing.
	if _transitioning:
		return
	if not body.is_in_group("player"):
		return
	_transitioning = true
	call_deferred("_do_transition")


func _do_transition() -> void:
	var root: Window = get_tree().root
	if use_target_position and target_position != Vector2.ZERO:
		root.set_meta("target_position", target_position)
	elif not spawn_marker_name.is_empty():
		root.set_meta("target_spawn", spawn_marker_name)
	get_tree().change_scene_to_file(destination_scene)
