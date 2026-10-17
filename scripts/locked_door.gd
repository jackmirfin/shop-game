extends Area2D
## Locked shop door. Player needs shop_keys to enter.
## Shows a prompt when the player is nearby and presses E.

@export var required_key_id: String = "shop_keys"
@export var door_label: String = "The Adventurer's Emporium"

@onready var prompt_label: Label = $PromptLabel

var player_in_range: bool = false
var is_unlocked: bool = false


func _ready() -> void:
	add_to_group("interactable")

	if prompt_label:
		prompt_label.text = door_label + "\n[LOCKED]"
		prompt_label.visible = false

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	EventBus.interact_pressed.connect(_on_interact_pressed)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		if prompt_label and not is_unlocked:
			prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		if prompt_label:
			prompt_label.visible = false


func _on_interact_pressed() -> void:
	if not player_in_range:
		return

	if is_unlocked:
		_enter_shop()
		return

	# Check if player has the keys
	var player: Node = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var inventory: Node = player.get_node_or_null("Inventory")
	if not inventory:
		for child: Node in player.get_children():
			if child is InventoryComponent:
				inventory = child
				break

	if inventory and inventory is InventoryComponent:
		var inv: InventoryComponent = inventory as InventoryComponent
		if inv.has_item(required_key_id):
			_unlock_door(inv)
		else:
			_show_locked_message()
	else:
		_show_locked_message()


func _unlock_door(inv: InventoryComponent) -> void:
	is_unlocked = true
	inv.remove_item(required_key_id, 1)

	if prompt_label:
		prompt_label.text = door_label + "\n[UNLOCKED!]"

	# Brief celebration then enter
	await get_tree().create_timer(0.8).timeout
	_enter_shop()


func _enter_shop() -> void:
	# Transition to shop interior
	if prompt_label:
		prompt_label.visible = false

	# Use the ShopSystem to enter the shop
	var shop_system: Node = get_node_or_null("/root/ShopSystem")
	if shop_system and shop_system.has_method("enter_shop"):
		shop_system.enter_shop()
	else:
		print("Shop system not found! Trying alternative...")
		# Fallback: try WorldStateManager's shop system
		var wsm: Node = get_node_or_null("/root/WorldStateManager")
		if wsm:
			# WorldStateManager creates ShopSystemNode at startup
			print("Shop entry via WorldStateManager")


func _show_locked_message() -> void:
	if prompt_label:
		var original_text: String = prompt_label.text
		prompt_label.text = "It's locked. You need\n" + required_key_id.replace("_", " ") + "."
		await get_tree().create_timer(2.0).timeout
		prompt_label.text = original_text
