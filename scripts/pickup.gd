extends Area2D
## A ground pickup that the player can collect.
## Place in levels as a child of the Entities node.

@export var item_data: ItemData
@export var count: int = 1
@export var despawn_time: float = 0.0  ## 0 = never despawns

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("pickup")

	# Use item icon if available, otherwise show a default shape
	if item_data and item_data.icon_texture:
		sprite.texture = item_data.icon_texture
	else:
		# Create a small default square
		sprite.texture = null
		modulate = Color.YELLOW if item_data else Color.RED

	body_entered.connect(_on_body_entered)

	if despawn_time > 0.0:
		var tween: Tween = create_tween()
		tween.tween_interval(despawn_time)
		tween.tween_callback(queue_free)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	# Special case: Adventurer's Bag unlocks inventory and changes sprite
	if item_data and item_data.unique_id == "adventurers_bag":
		if body.has_method("equip_bag"):
			body.equip_bag()
			_pickup_effect()
			queue_free()
		return

	var inventory: Node = body.get_node_or_null("Inventory")
	if not inventory:
		# Try to find inventory component
		for child: Node in body.get_children():
			if child is InventoryComponent:
				inventory = child
				break

	if inventory and inventory is InventoryComponent:
		var inv: InventoryComponent = inventory as InventoryComponent
		var added: int = inv.add_item(item_data, count)
		if added > 0:
			EventBus.item_picked_up.emit(item_data, added)
			_pickup_effect()
			queue_free()
	else:
		print("No InventoryComponent found on player!")


func _pickup_effect() -> void:
	# Simple flash + scale effect
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15)
	tween.tween_callback(queue_free)
