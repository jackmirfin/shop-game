class_name InventoryComponent
extends Node
## Reusable inventory system. Attach to Player, chests, shop containers, etc.
## Emits signals through EventBus for UI updates.

signal item_added(item: ItemData, count: int)
signal item_removed(item: ItemData, count: int)
signal item_count_changed(item: ItemData, new_count: int)

@export var max_slots: int = 20
@export var owner_id: String = ""  ## "player", "chest_village", etc.

var items: Array[Dictionary] = []  ## [{item: ItemData, count: int}]


func _ready() -> void:
	# Register with EventBus for save/load awareness
	if owner_id == "player":
		get_node('/root/EventBus').item_picked_up.connect(_on_global_item_picked_up)


# --- Public API ---

## Returns a shallow copy of stored items for UI display.
## Each entry: { unique_id: String, count: int, item: ItemData }
func get_stored_items() -> Array:
	var result: Array = []
	for stored: Dictionary in items:
		var item: ItemData = stored.get("item", null)
		result.append({
			"unique_id": item.unique_id if item else "",
			"count": stored.get("count", 0),
			"item": item
		})
	return result

func add_item(item: ItemData, count: int = 1) -> int:
	"""Add items to inventory. Returns the number actually added (may be less if full)."""
	var added: int = 0

	if item.stackable:
		# Try to stack with existing
		for slot: Dictionary in items:
			if slot.item.unique_id == item.unique_id and slot.count < item.max_stack:
				var space: int = item.max_stack - slot.count
				var to_add: int = min(space, count)
				slot.count += to_add
				added += to_add
				count -= to_add
				item_count_changed.emit(slot.item, slot.count)
				if count <= 0:
					item_added.emit(item, added)
					return added

	# Add new slots for remaining
	while count > 0 and items.size() < max_slots:
		var to_add: int = min(count, item.max_stack if item.stackable else 1)
		items.append({"item": item, "count": to_add})
		added += to_add
		count -= to_add

	if added > 0:
		item_added.emit(item, added)
	else:
		# Inventory full
		get_node('/root/EventBus').inventory_full.emit()

	return added


func remove_item(unique_id: String, count: int = 1) -> int:
	"""Remove items by unique_id. Returns # actually removed."""
	var removed: int = 0

	for i: int in range(items.size() - 1, -1, -1):
		if items[i].item.unique_id == unique_id:
			var to_remove: int = min(count - removed, items[i].count)
			items[i].count -= to_remove
			removed += to_remove
			item_count_changed.emit(items[i].item, items[i].count)
			if items[i].count <= 0:
				var item: ItemData = items[i].item
				items.remove_at(i)
				item_removed.emit(item, 0)
			if removed >= count:
				break

	return removed


func has_item(unique_id: String, count: int = 1) -> bool:
	return count_item(unique_id) >= count


func count_item(unique_id: String) -> int:
	var total: int = 0
	for slot: Dictionary in items:
		if slot.item.unique_id == unique_id:
			total += slot.count
	return total


func get_all_items() -> Array[Dictionary]:
	return items


func get_total_value() -> int:
	var total: int = 0
	for slot: Dictionary in items:
		total += slot.item.value * slot.count
	return total


func clear() -> void:
	items.clear()


# --- Save/Load ---

func get_save_data() -> Array:
	var data: Array = []
	for slot: Dictionary in items:
		data.append({
			"unique_id": slot.item.unique_id,
			"count": slot.count
		})
	return data


func load_save_data(data: Array) -> void:
	clear()
	for entry: Dictionary in data:
		var item: ItemData = load("res://resources/items/%s.tres" % entry.unique_id) as ItemData
		if item:
			add_item(item, entry.count)


# --- Internal ---

func _on_global_item_picked_up(_item: ItemData, _count: int) -> void:
	# Could trigger UI refresh, quest checks, etc.
	pass
