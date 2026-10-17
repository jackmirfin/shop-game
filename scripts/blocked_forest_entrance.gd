class_name BlockedForestEntrance
extends Area2D

@export var message: String = "This isn't the right way to the village..."
var _message_showing: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if _message_showing or not body.is_in_group("player"):
		return
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and bool(state.get("has_been_to_namura")):
		return
	_message_showing = true
	if DialogueManager.has_method("show_system_message"):
		DialogueManager.show_system_message(message, 470.0,
			Callable(self, "_finish_message"), 2.0, 22)

func _finish_message() -> void:
	_message_showing = false

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_message_showing = false
		DialogueManager.hide_system_message()
