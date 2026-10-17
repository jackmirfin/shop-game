class_name Interactable
extends Area2D
## Reusable world-interaction trigger.
##
## Attach this to an existing Area2D and configure everything through the
## exported fields below — behaviour is NEVER inferred from the node's name.
##
## How it works:
##   * The Player registers with this area when it enters and unregisters when
##     it leaves (via body_entered / body_exited).
##   * Nothing happens automatically while the player is inside. The Player
##     calls interact() only when the "interact" action (E) is pressed, and only
##     for the single nearest active Interactable — so one press = one action.
##   * Teleports reuse the project's existing transition mechanism: the
##     "target_spawn" / "target_position" meta on the SceneTree root is read by
##     Player._apply_spawn_marker() after change_scene_to_file().

enum InteractionType { TEXT, TELEPORT, INVENTORY, DIALOGUE, CONFIRM }

## Pixel size of one TileMap cell in this project. Exported destination cells
## (target_cell) are multiplied by this to get world pixels.
const TILE_SIZE: int = 16

@export var interaction_type: InteractionType = InteractionType.TEXT
@export_multiline var interaction_text: String = ""

# --- Teleport ---
@export var target_scene: String = ""
@export var use_spawn_marker: bool = false
@export var target_spawn_marker: String = ""
## Destination as TileMap cell coordinates (converted with TILE_SIZE).
@export var target_cell: Vector2i = Vector2i.ZERO
## Optional explicit pixel destination. Takes priority over target_cell when non-zero.
@export var target_position: Vector2 = Vector2.ZERO

# --- Data ids ---
@export var inventory_id: String = ""
@export var dialogue_id: String = ""
@export var confirmation_id: String = ""

## Placeholder signal for CONFIRM interactions once accepted.
signal shop_open_requested()

var _player_in_range: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if body.has_method("register_interactable"):
		body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)


## True while the player body is overlapping this area.
func can_interact() -> bool:
	return _player_in_range


## Called by the Player when the interact action is pressed.
func interact() -> void:
	match interaction_type:
		InteractionType.TEXT:
			_interact_text()
		InteractionType.TELEPORT:
			_interact_teleport()
		InteractionType.INVENTORY:
			_interact_inventory()
		InteractionType.DIALOGUE:
			_interact_dialogue()
		InteractionType.CONFIRM:
			_interact_confirm()


func _interact_text() -> void:
	_ui().show_message(interaction_text)


func _interact_teleport() -> void:
	if target_scene.is_empty():
		push_warning("Interactable '%s' has no target_scene set." % name)
		return

	var root: Window = get_tree().root
	if target_scene == "res://namura.tscn" and get_tree().current_scene.scene_file_path.contains("shop_interior"):
		root.set_meta("namura_shop_exit", true)
	if use_spawn_marker and not target_spawn_marker.is_empty():
		root.set_meta("target_spawn", target_spawn_marker)
	else:
		var destination: Vector2 = target_position
		if destination == Vector2.ZERO and target_cell != Vector2i.ZERO:
			destination = Vector2(target_cell) * float(TILE_SIZE)
		if destination != Vector2.ZERO:
			root.set_meta("target_position", destination)

	get_tree().change_scene_to_file(target_scene)


func _interact_inventory() -> void:
	_ui().show_inventory(inventory_id)


func _interact_dialogue() -> void:
	_ui().show_dialogue(dialogue_id, interaction_text)


func _interact_confirm() -> void:
	_ui().show_confirm(interaction_text, confirmation_id, _on_confirm_result)


## Resolves the InteractionUI autoload by node path (avoids a compile-time
## dependency on the autoload global, which is not always registered).
func _ui() -> Node:
	return get_node_or_null("/root/InteractionUI")


func _on_confirm_result(accepted: bool) -> void:
	if accepted:
		shop_open_requested.emit()
		print("[Interactable] '%s' confirmed -> shop_open_requested (id=%s)" % [name, confirmation_id])
