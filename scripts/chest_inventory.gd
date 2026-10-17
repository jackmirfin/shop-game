class_name ChestInventory
extends RefCounted

signal changed

const SLOT_COUNT: int = 9

var slots: Array[InventoryItem] = []

func _init() -> void:
	for _i in SLOT_COUNT:
		slots.append(null)

func item_at(index: int) -> InventoryItem:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

func add_item(item: InventoryItem) -> int:
	if item == null:
		return -1
	if item.is_stackable():
		for i in slots.size():
			var existing: InventoryItem = slots[i]
			if existing != null and existing.item_name == item.item_name and existing.max_stack > existing.max_stack:
				slots[i] = existing
				changed.emit()
				return i
	for i in slots.size():
		if slots[i] == null:
			slots[i] = item
			changed.emit()
			return i
	return -1

func move_item(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= slots.size() or to_index < 0 or to_index >= slots.size():
		return false
	if from_index == to_index:
		return false
	var held: InventoryItem = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = held
	changed.emit()
	return true

func clear_slot(index: int) -> InventoryItem:
	var item: InventoryItem = item_at(index)
	if item != null:
		slots[index] = null
		changed.emit()
	return item

func has_items() -> bool:
	for item: InventoryItem in slots:
		if item != null:
			return true
	return false

func save_data() -> Array:
	var result: Array = []
	for item: InventoryItem in slots:
		if item == null:
			result.append(null)
		else:
			result.append({"item_name": item.item_name, "max_stack": item.max_stack,
				"kind": int(item.kind), "icon_path": item.icon.resource_path if item.icon else "",
				"description": item.description, "consumed_on_use": item.consumed_on_use})
	return result
