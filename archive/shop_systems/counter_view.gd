extends CanvasLayer
## First-person counter view. Player sees shop interior from behind the counter.
## NPC customers arrive with speech bubbles showing requested items.
## Player manually gives items from inventory to fulfill orders.

signal customer_served(customer_name: String, item_sold: String, price: int)
signal counter_closed()

# --- Customer Data ---
class Customer:
	var c_name: String
	var sprite_node: Sprite2D = null
	var name_label: Label = null
	var speech_bubble: Control = null
	var request_item: String = ""
	var request_count: int = 1
	var offer_price: int = 0
	var dialogue_lines: Array[String] = []
	var mood: String = "neutral"
	var arrival_time: float = 0.0
	var patience: float = 20.0
	var served: bool = false
	var leaving: bool = false
	var position_t: float = 0.0     # 0.0 = door, 1.0 = counter
	var at_counter: bool = false    # true when fully at counter


var _background_rect: ColorRect = null
var _customers: Array = []
var _customer_container: Control = null
var _inventory_panel: Panel = null
var _inventory_items: VBoxContainer = null
var _dialogue_label: Label = null
var _gold_label: Label = null
var _status_label: Label = null
var _player_inventory = null
var _spawn_timer: float = 0.0
var _spawn_interval: float = 8.0
var _max_customers: int = 3
var _active_customer = null  # Customer currently at counter waiting to be served

var _customer_names: Array[String] = ["Aldric", "Bryn", "Cedric", "Della", "Eldon", "Fiora", "Garrett", "Hilda", "Ingrid", "Jorah"]
var _customer_requests: Array[Dictionary] = [
	{"item": "health_potion", "count": 1, "price": 35, "dialogue": ["Got any healing potions?", "That will do nicely.", "Thanks!"]},
	{"item": "bread", "count": 2, "price": 12, "dialogue": ["Two loaves of bread, please.", "Thank you kindly!"]},
	{"item": "iron_sword", "count": 1, "price": 180, "dialogue": ["I need a decent blade.", "This looks sturdy.", "Appreciate it."]},
	{"item": "tea_leaf", "count": 1, "price": 20, "dialogue": ["I hear you sell tea leaves?", "Perfect, just what I needed."]},
	{"item": "leather_armor", "count": 1, "price": 130, "dialogue": ["Something to protect me out there.", "Good leather. I will take it."]},
	{"item": "health_potion", "count": 3, "price": 90, "dialogue": ["I am stocking up for a journey.", "Three will do.", "Safe travels!"]},
	{"item": "slime_gel", "count": 5, "price": 30, "dialogue": ["Got any slime gel? Odd request, I know.", "For... research. Thanks!"]},
]


func setup(player_inv) -> void:
	_player_inventory = player_inv
	_create_background()
	_create_customer_area()
	_create_inventory_panel()
	_create_dialogue_area()
	_create_status_bar()
	layer = 40


func _create_background() -> void:
	var bg := ColorRect.new()
	bg.name = "CounterBG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.03, 0.02, 1.0)
	add_child(bg)
	
	var bg_tex: Texture2D = load("res://assets/generated/shop_counter_view_bg.png")
	if bg_tex:
		var tex_rect := TextureRect.new()
		tex_rect.name = "ShopInterior"
		tex_rect.texture = bg_tex
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(tex_rect)
	
	_background_rect = bg


func _create_customer_area() -> void:
	_customer_container = Control.new()
	_customer_container.name = "CustomerContainer"
	_customer_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_customer_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_customer_container)


func _create_inventory_panel() -> void:
	_inventory_panel = Panel.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.set_anchor(SIDE_RIGHT, 1.0)
	_inventory_panel.set_anchor(SIDE_LEFT, 0.72)
	_inventory_panel.set_anchor(SIDE_TOP, 0.0)
	_inventory_panel.set_anchor(SIDE_BOTTOM, 1.0)
	_inventory_panel.offset_left = 0
	_inventory_panel.offset_right = 0
	_inventory_panel.offset_top = 0
	_inventory_panel.offset_bottom = 0
	add_child(_inventory_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "PanelVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_inventory_panel.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	margin.add_child(inner_vbox)

	var header := Label.new()
	header.text = "Your Inventory"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	inner_vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(scroll)

	_inventory_items = VBoxContainer.new()
	_inventory_items.name = "InventoryItems"
	_inventory_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inventory_items)

	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_font_size_override("font_size", 14)
	inner_vbox.add_child(_gold_label)

	# Current order section
	var order_header := Label.new()
	order_header.text = "Current Orders"
	order_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_header.add_theme_font_size_override("font_size", 13)
	order_header.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	inner_vbox.add_child(order_header)

	var close_btn := Button.new()
	close_btn.text = "Stop Tending (ESC)"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_close_counter)
	inner_vbox.add_child(close_btn)

	_refresh_inventory()


func _create_dialogue_area() -> void:
	var panel := Panel.new()
	panel.name = "DialoguePanel"
	panel.set_anchor(SIDE_LEFT, 0.0)
	panel.set_anchor(SIDE_RIGHT, 0.72)
	panel.set_anchor(SIDE_TOP, 0.78)
	panel.set_anchor(SIDE_BOTTOM, 1.0)
	panel.offset_left = 4
	panel.offset_right = -4
	panel.offset_top = 0
	panel.offset_bottom = -4
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	_dialogue_label = Label.new()
	_dialogue_label.name = "DialogueText"
	_dialogue_label.add_theme_font_size_override("font_size", 13)
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_dialogue_label)


func _create_status_bar() -> void:
	var bar := Panel.new()
	bar.name = "StatusBar"
	bar.set_anchor(SIDE_LEFT, 0.0)
	bar.set_anchor(SIDE_RIGHT, 0.72)
	bar.set_anchor(SIDE_TOP, 0.0)
	bar.set_anchor(SIDE_BOTTOM, 0.0)
	bar.offset_left = 4
	bar.offset_right = -4
	bar.offset_top = 4
	bar.offset_bottom = 32
	add_child(bar)

	_status_label = Label.new()
	_status_label.name = "StatusText"
	_status_label.text = "Tending shop — customers will arrive soon..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_label.add_theme_font_size_override("font_size", 12)
	bar.add_child(_status_label)


# --- Process ---

func _process(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer >= _spawn_interval and _customers.size() < _max_customers:
		_spawn_timer = 0.0
		_spawn_customer()
	
	_update_customers(delta)


func _spawn_customer() -> void:
	if _customers.size() >= _max_customers:
		return
	
	var c := Customer.new()
	c.c_name = _customer_names[randi() % _customer_names.size()]
	var request: Dictionary = _customer_requests[randi() % _customer_requests.size()]
	c.request_item = request["item"]
	c.request_count = request["count"]
	c.offer_price = request["price"]
	c.dialogue_lines = request["dialogue"]
	c.arrival_time = Time.get_ticks_msec() / 1000.0
	c.patience = 15.0 + randf() * 10.0
	c.position_t = 0.0
	
	# Sprite
	var sprite := Sprite2D.new()
	sprite.name = "Sprite_" + c.c_name
	sprite.scale = Vector2(2.5, 2.5)
	sprite.centered = true
	sprite.modulate.a = 0.3
	_customer_container.add_child(sprite)
	c.sprite_node = sprite
	
	# Name label
	var nl := Label.new()
	nl.name = "Label_" + c.c_name
	nl.text = c.c_name
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 10)
	_customer_container.add_child(nl)
	c.name_label = nl
	
	# Speech bubble (hidden until at counter)
	var bubble := _create_speech_bubble(c)
	bubble.visible = false
	_customer_container.add_child(bubble)
	c.speech_bubble = bubble
	
	_customers.append(c)
	_show_dialogue(c.c_name + " enters the shop.")


func _create_speech_bubble(c: Customer) -> Control:
	var bubble := Control.new()
	bubble.name = "Bubble_" + c.c_name
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background panel
	var panel := Panel.new()
	panel.name = "BubblePanel"
	panel.size = Vector2(64, 64)
	panel.position = Vector2(-32, -80)  # Above customer head
	bubble.add_child(panel)
	
	# Item icon
	var item_icon := TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.size = Vector2(40, 40)
	item_icon.position = Vector2(12, 4)
	panel.add_child(item_icon)
	
	# Question mark
	var qm := Label.new()
	qm.name = "QuestionMark"
	qm.text = "?"
	qm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qm.add_theme_font_size_override("font_size", 20)
	qm.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	qm.size = Vector2(64, 20)
	qm.position = Vector2(0, 42)
	panel.add_child(qm)
	
	return bubble


func _update_customers(delta: float) -> void:
	if not _customer_container:
		return
	
	var cs: Vector2 = _customer_container.size
	var counter_y: float = cs.y * 0.42
	var door_y: float = cs.y * 0.1
	var lane_x: float = cs.x * 0.36
	
	var to_remove: Array = []
	
	for c in _customers:
		if c.leaving:
			c.position_t -= delta * 0.5
			if c.speech_bubble:
				c.speech_bubble.visible = false
			if c.at_counter:
				c.at_counter = false
				if _active_customer == c:
					_active_customer = null
					_refresh_inventory()
			if c.position_t <= 0.0:
				c.position_t = 0.0
				to_remove.append(c)
		else:
			c.position_t += delta * 0.5
			if c.position_t >= 1.0:
				c.position_t = 1.0
				if not c.at_counter:
					c.at_counter = true
					_show_request(c)
			elif c.at_counter:
				c.at_counter = false
				if _active_customer == c:
					_active_customer = null
					_refresh_inventory()
		
		# Update sprite
		if c.sprite_node:
			var y: float = lerp(door_y, counter_y, c.position_t)
			c.sprite_node.position = Vector2(lane_x, y)
			c.sprite_node.modulate.a = 0.3 + c.position_t * 0.7
		
		# Update name label
		if c.name_label:
			var y2: float = lerp(door_y, counter_y, c.position_t)
			c.name_label.position = Vector2(lane_x - 40, y2 - 30)
		
		# Update speech bubble position
		if c.speech_bubble:
			var by: float = lerp(door_y, counter_y, c.position_t)
			c.speech_bubble.position = Vector2(lane_x, by)
			c.speech_bubble.visible = c.at_counter and not c.served
	
	for c in to_remove:
		_remove_customer(c)


func _show_request(c: Customer) -> void:
	if c.served:
		return
	
	_active_customer = c
	
	var item_path: String = "res://resources/items/" + c.request_item + ".tres"
	var item: Resource = load(item_path)
	var item_name: String = item.get("item_name") if item else c.request_item
	
	# Load item icon into speech bubble
	if c.speech_bubble:
		var panel: Panel = c.speech_bubble.get_node_or_null("BubblePanel")
		if panel:
			var icon: TextureRect = panel.get_node_or_null("ItemIcon")
			if icon:
				# Try to generate a small icon from the item resource
				icon.texture = _generate_item_icon(item)
	
	_show_dialogue(c.c_name + ": " + chr(34) + c.dialogue_lines[0] + chr(34)
	_refresh_inventory()  # Show Give buttons


func _generate_item_icon(item: Resource) -> Texture2D:
	if not item:
		return null
	# Create a small colored icon based on item type
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var item_type: int = item.get("item_type") if item else 0
	match item_type:
		1: img.fill(Color(0.5, 0.5, 0.6))   # Weapon - steel blue
		2: img.fill(Color(0.6, 0.4, 0.2))   # Armor - brown
		3: img.fill(Color(0.2, 0.8, 0.3))   # Consumable - green
		4: img.fill(Color(0.7, 0.6, 0.3))   # Material - gold
		_: img.fill(Color(0.5, 0.5, 0.5))   # Generic - gray
	return ImageTexture.create_from_image(img)


func _remove_customer(c: Customer) -> void:
	if c == _active_customer:
		_active_customer = null
		_refresh_inventory()
	if c.sprite_node:
		c.sprite_node.queue_free()
	if c.name_label:
		c.name_label.queue_free()
	if c.speech_bubble:
		c.speech_bubble.queue_free()
	_customers.erase(c)


func _show_dialogue(text: String) -> void:
	if _dialogue_label:
		_dialogue_label.text = text
	if _status_label:
		_status_label.text = ""


func _refresh_inventory() -> void:
	if not _inventory_items:
		return
	
	# Clear existing
	for child in _inventory_items.get_children():
		child.queue_free()
	
	if not _player_inventory or not _player_inventory.has_method("get_stored_items"):
		var empty := Label.new()
		empty.text = "(No inventory)"
		_inventory_items.add_child(empty)
		return
	
	var items: Array = _player_inventory.get_stored_items()
	
	if items.is_empty():
		var empty := Label.new()
		empty.text = "(Empty)"
		_inventory_items.add_child(empty)
	else:
		for stored in items:
			var uid: String = stored.get("unique_id", "")
			var count: int = stored.get("count", 0)
			var item_data = stored.get("item")
			var item_name: String = item_data.get("item_name") if item_data else uid
			
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var name_lbl := Label.new()
			name_lbl.text = item_name + " x" + str(count)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 12)
			row.add_child(name_lbl)
			
			# Check if this item matches what the active customer wants
			if _active_customer and not _active_customer.served:
				if uid == _active_customer.request_item and count >= _active_customer.request_count:
					var give_btn := Button.new()
					give_btn.text = "Give to " + _active_customer.c_name
					give_btn.add_theme_font_size_override("font_size", 9)
					var this_customer = _active_customer  # Capture for lambda
					give_btn.pressed.connect(func(): _give_item(this_customer))
					row.add_child(give_btn)
			
			_inventory_items.add_child(row)
	
	# Update gold
	if _gold_label:
		var gs: Node = get_node("/root/GameState")
		_gold_label.text = "Gold: " + str(gs.player_gold)


func _give_item(c: Customer) -> void:
	if c.served:
		return
	
	if not _player_inventory or not _player_inventory.has_method("remove_item"):
		return
	
	if not _player_inventory.has_item(c.request_item, c.request_count):
		_show_dialogue(c.c_name + ": "Oh... you do not have any?"")
		c.leaving = true
		return
	
	# Remove item from inventory
	_player_inventory.remove_item(c.request_item, c.request_count)
	
	# Add gold
	var gs: Node = get_node("/root/GameState")
	gs.add_gold(c.offer_price)
	
	# Success!
	_show_dialogue(c.c_name + ": "" + c.dialogue_lines[1] + ""
[Sold for " + str(c.offer_price) + "g!]")
	c.served = true
	c.leaving = true
	
	# Hide speech bubble
	if c.speech_bubble:
		c.speech_bubble.visible = false
	
	customer_served.emit(c.c_name, c.request_item, c.offer_price)
	_refresh_inventory()


func _close_counter() -> void:
	counter_closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_counter()
