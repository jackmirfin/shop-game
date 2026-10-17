extends Node
class_name TeaWorldNode

func _ready() -> void:
	var wsm: Node = get_node_or_null("/root/WorldStateManager")
	if wsm and wsm.has_method("register_tea_node"):
		wsm.register_tea_node(self)
		if wsm.has_method("is_tea_world"):
			_on_world_state_changed(wsm.is_tea_world())

func _exit_tree() -> void:
	var wsm: Node = get_node_or_null("/root/WorldStateManager")
	if wsm and wsm.has_method("unregister_tea_node"):
		wsm.unregister_tea_node(self)

func _on_world_state_changed(_entering_tea: bool) -> void:
	pass
