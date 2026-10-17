class_name ChestInventoryUI
extends CanvasLayer

const TEX_GRID: Texture2D = preload("res://assets/Inventory/9-Inventory.png")
const ART_SCALE: float = 3.8
const GRID_REGION := Rect2(131.0, 132.0, 78.0, 81.0)
const SLOT_REGION := Rect2(134.0, 138.0, 70.0, 69.0)
const UI_FONT: Font = preload("res://assets/Fonts/cardfont.ttf")

var chest: StandardChest
var panel: Control
var chest_buttons: Array[Button] = []
var player_buttons: Array[Button] = []
var held: InventoryItem = null
var held_source: String = ""
var held_index: int = -1

func open_for(target: StandardChest) -> void:
	chest = target
	_build()
	_refresh()
	visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS

func close() -> void:
	if held != null:
		_put_back_held()
	if chest != null:
		chest.close_inventory()
	chest = null
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()

func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	panel = Control.new()
	panel.name = "ChestInventoryPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)
	_create_inventory(Vector2(484, 28), false)
	_create_inventory(Vector2(484, 370), true)

func _create_inventory(origin: Vector2, player: bool) -> void:
	var art := TextureRect.new()
	var cropped_grid := AtlasTexture.new()
	cropped_grid.atlas = TEX_GRID
	cropped_grid.region = GRID_REGION
	art.texture = cropped_grid
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = origin
	art.size = GRID_REGION.size * ART_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	var slot_origin: Vector2 = origin + (SLOT_REGION.position - GRID_REGION.position) * ART_SCALE
	var cell: Vector2 = SLOT_REGION.size * ART_SCALE / Vector2(3, 3)
	for index in 9:
		var button := Button.new()
		button.name = ("Player" if player else "Chest") + "Slot%d" % index
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.position = (slot_origin + Vector2(index % 3, floori(float(index) / 3.0)) * cell).round()
		button.size = cell
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.set_meta("container", "player" if player else "chest")
		button.set_meta("index", index)
		button.pressed.connect(_on_slot_pressed.bind(button))
		button.set_drag_forwarding(_get_drag_data.bind(button), _can_drop_data.bind(button), _drop_data.bind(button))
		panel.add_child(button)
		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon"
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = button.position + Vector2(2, 2)
		icon.size = cell - Vector2(4, 4)
		panel.add_child(icon)
		button.set_meta("icon", icon)
		if player:
			player_buttons.append(button)
		else:
			chest_buttons.append(button)

func _on_slot_pressed(button: Button) -> void:
	var container: String = str(button.get_meta("container"))
	var index: int = int(button.get_meta("index"))
	if held == null:
		held = _item_at(container, index)
		if held == null:
			return
		held_source = container
		held_index = index
		_set_item(container, index, null)
	else:
		var target: InventoryItem = _item_at(container, index)
		_set_item(container, index, held)
		held = target
		if held == null:
			held_source = ""
			held_index = -1
		else:
			held_source = container
			held_index = index
	_refresh()

func _item_at(container: String, index: int) -> InventoryItem:
	if container == "player":
		var inventory: Node = get_node_or_null("/root/Inventory")
		return inventory.item_at(index) if inventory != null else null
	return chest.inventory.item_at(index) if chest != null else null

func _set_item(container: String, index: int, item: InventoryItem) -> void:
	if container == "player":
		var inventory: Node = get_node_or_null("/root/Inventory")
		if inventory != null and index >= 0 and index < inventory.slots.size():
			inventory.slots[index] = item
			inventory.changed.emit()
	elif chest != null:
		chest.inventory.slots[index] = item
		chest.inventory.changed.emit()

func _get_drag_data(_at_position: Vector2, button: Button) -> Variant:
	var item: InventoryItem = _item_at(str(button.get_meta("container")), int(button.get_meta("index")))
	if item == null:
		return null
	var preview := TextureRect.new()
	preview.texture = item.icon
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = button.size * 0.9
	preview.position = -preview.size * 0.5
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.set_drag_preview(preview)
	return {"source": str(button.get_meta("container")), "index": int(button.get_meta("index"))}

func _can_drop_data(_at_position: Vector2, data: Variant, _button: Button) -> bool:
	return data is Dictionary and data.has("source") and data.has("index") and _item_at(str(data.source), int(data.index)) != null

func _drop_data(_at_position: Vector2, data: Variant, button: Button) -> void:
	var source: String = str(data.source)
	var source_index: int = int(data.index)
	var target: String = str(button.get_meta("container"))
	var target_index: int = int(button.get_meta("index"))
	var source_item: InventoryItem = _item_at(source, source_index)
	var target_item: InventoryItem = _item_at(target, target_index)
	if source_item == null:
		return
	if source == target and source_index == target_index:
		return
	# Remove from the source first, then place it in the destination. If the
	# destination was occupied, its item is swapped back into the source slot.
	_set_item(source, source_index, target_item)
	_set_item(target, target_index, source_item)
	_refresh()

func _put_back_held() -> void:
	if held != null and held_source != "":
		_set_item(held_source, held_index, held)
	held = null

func _refresh() -> void:
	for button: Button in chest_buttons:
		_update_button(button, _item_at("chest", int(button.get_meta("index"))))
	for button: Button in player_buttons:
		_update_button(button, _item_at("player", int(button.get_meta("index"))))

func _update_button(button: Button, item: InventoryItem) -> void:
	button.text = ""
	button.tooltip_text = "" if item == null else item.description
	var icon: TextureRect = button.get_meta("icon") as TextureRect
	if icon != null:
		icon.texture = item.icon if item != null else null
		icon.pivot_offset = icon.size * 0.5
		icon.scale = Vector2.ONE * _item_icon_scale(item)

func _item_icon_scale(item: InventoryItem) -> float:
	if item == null:
		return 1.0
	match item.item_name:
		"Amethyst Sword":
			return 0.55
		"Minor Healing Potion":
			return 0.32
	return 0.55

func _item_text(item: InventoryItem) -> String:
	return "" if item == null else item.item_name
