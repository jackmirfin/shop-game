class_name StandardChest
extends Interactable

enum ChestState { CLOSED, OPEN_FULL, OPEN_EMPTY }

@export var chest_id: String = "standard_chest"
@export var starting_contents: Array[String] = []
@export var starting_quantities: Array[int] = []
@export_enum("none", "treasure", "room5") var dungeon_loot_kind: String = "none"

const OPEN_SPEED: float = 8.0
var inventory: ChestInventory = ChestInventory.new()
var state: ChestState = ChestState.CLOSED
var ui: ChestInventoryUI = null
var _animation_kind: StringName = &""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	if name == "TestStandardChest" and chest_id == "standard_chest":
		chest_id = "shop_basement_test_chest"
		starting_contents = ["Amethyst Sword", "Aquamarine Sword II", "Sunbronze Sword IV", "Minor Healing Potion"]
		starting_quantities = [1, 1, 1, 1]
	interaction_type = InteractionType.INVENTORY
	super._ready()
	_load_or_create_contents()
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inventory.changed.connect(_save_contents)

func interact() -> void:
	if state != ChestState.CLOSED:
		return
	_animation_kind = &"open_full" if inventory.has_items() else &"open_empty"
	state = ChestState.OPEN_FULL if inventory.has_items() else ChestState.OPEN_EMPTY
	animated_sprite.play(_animation_kind)
	ui = ChestInventoryUI.new()
	get_tree().root.add_child(ui)
	ui.open_for(self)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_control_enabled"):
		player.set_control_enabled(false)

func close_inventory() -> void:
	if ui != null and is_instance_valid(ui):
		ui.visible = false
		ui.queue_free()
		ui = null
	if _animation_kind != &"":
		animated_sprite.play_backwards(_animation_kind)
	await animated_sprite.animation_finished
	animated_sprite.stop()
	animated_sprite.frame = 0
	state = ChestState.CLOSED
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_control_enabled"):
		player.set_control_enabled(true)

func _load_or_create_contents() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	var saved: Variant = game_state.get_chest_contents(chest_id) if game_state != null and game_state.has_method("get_chest_contents") else null
	if saved is Array:
		inventory.slots = []
		for entry: Variant in saved:
			inventory.slots.append(_item_from_saved(entry))
		while inventory.slots.size() < ChestInventory.SLOT_COUNT:
			inventory.slots.append(null)
		return
	for i in mini(starting_contents.size(), ChestInventory.SLOT_COUNT):
		inventory.slots[i] = _make_item(starting_contents[i], starting_quantities[i] if i < starting_quantities.size() else 1)
	_add_dungeon_loot()
	_save_contents()

func _add_dungeon_loot() -> void:
	if dungeon_loot_kind == "none":
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var knife_material_local: String = KnifeCardFactory.MATERIALS[rng.randi_range(0, KnifeCardFactory.MATERIALS.size() - 1)]
	inventory.add_item(InventoryItem.make_knife(knife_material_local))
	var relic_names: Array[String] = ["Strange Mask", "Photo of a Ghost", "Mysterious Orb", "Mysterious Crown", "Talisman"]
	var relic_count: int = 2 if dungeon_loot_kind == "treasure" else 1
	for _relic_index: int in relic_count:
		var relic_index: int = rng.randi_range(0, relic_names.size() - 1)
		var relic_name: String = relic_names[relic_index]
		relic_names.remove_at(relic_index)
		inventory.add_item(_make_item(relic_name, 1))

func _make_item(item_name: String, quantity: int) -> InventoryItem:
	match item_name:
		"Amethyst Sword": return InventoryItem.make_sword("amethyst", 0)
		"Aquamarine Sword II": return InventoryItem.make_sword("aquamarine", 2)
		"Sunbronze Sword IV": return InventoryItem.make_sword("sunbronze", 4)
		"Strange Mask": return InventoryItem.make_relic(item_name, "res://assets/Inventory/Items/strangemask_item.png", "Every time you apply a status, draw 1 card.")
		"Photo of a Ghost": return InventoryItem.make_relic(item_name, "res://assets/Inventory/Items/photoofaghost_item.png", "Gain 1 Intangible on turn 4.")
		"Mysterious Orb": return InventoryItem.make_relic(item_name, "res://assets/Inventory/Items/mysteriousorb_item.png", "Playing 3 cards in one turn grants 1 additional energy.")
		"Mysterious Crown": return InventoryItem.make_relic(item_name, "res://assets/Inventory/Items/mysteriouscrown_item.png", "The first non-Attack card each combat costs 0 energy.")
		"Talisman": return InventoryItem.make_relic(item_name, "res://assets/Inventory/Items/talisman_item.png", "The first time each combat you drop below 50% health, gain 6 Block.")
		"Minor Healing Potion": return InventoryItem.make(item_name, "res://assets/Inventory/Items/minorhealingpotion_item.png", InventoryItem.Kind.CONSUMABLE, maxi(1, quantity), true, "Restores health when used.")
		"Long Stick": return InventoryItem.make(item_name, "res://assets/Inventory/Items/longstick_item.png", InventoryItem.Kind.WEAPON, 1, false, "A sturdy length of wood.")
		"Bark Shield": return InventoryItem.make(item_name, "res://assets/Inventory/Items/barkshield_item.png", InventoryItem.Kind.SHIELD, 1, false, "Rough bark, surprisingly tough.")
		"Stone": return InventoryItem.make(item_name, "res://assets/Inventory/Items/stone_item.png", InventoryItem.Kind.CONSUMABLE, maxi(1, quantity), true, "Good for throwing.")
		"Nightiron Throwing Knives": return InventoryItem.make_knife("nightiron")
		"Bloodsteel Throwing Knives": return InventoryItem.make_knife("bloodsteel")
		"Swamp-gold Throwing Knives": return InventoryItem.make_knife("swamp-gold")
		"Froststeel Throwing Knives": return InventoryItem.make_knife("froststeel")
		"Stormfire Throwing Knives": return InventoryItem.make_knife("stormfire")
	return null

func _item_from_saved(entry: Variant) -> InventoryItem:
	if not entry is Dictionary:
		return null
	return _make_item(str(entry.get("item_name", "")), int(entry.get("max_stack", 1)))

func _save_contents() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("set_chest_contents"):
		game_state.set_chest_contents(chest_id, inventory.save_data())
