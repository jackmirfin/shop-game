extends CharacterBody2D
## Shopkeeper NPC. When interacted with, opens the shop UI.
## Self-contained - does not require ShopManager autoload.

@export var shop_data: Resource
@export var interaction_range: float = 48.0

var interaction_area: Area2D = null
@onready var name_label: Label = $NameLabel
@onready var sprite: Sprite2D = $Sprite2D

var _player_in_range: bool = false
var _shop_ui: Control = null
var _shop_ui_active: bool = false
var _player_inventory = null


func _ready() -> void:
	print("[Shopkeeper] _ready() START - position: ", global_position)
	add_to_group("npc")
	
	# Ensure InteractionArea exists with proper collision shape
	if not has_node("InteractionArea"):
		var area := Area2D.new()
		area.name = "InteractionArea"
		var area_shape := CollisionShape2D.new()
		area_shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 48.0
		area_shape.shape = circle
		area.add_child(area_shape)
		add_child(area)
		interaction_area = area
	
	# Ensure CollisionShape2D exists
	if not has_node("CollisionShape2D"):
		var cs := CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		var body_circle := CircleShape2D.new()
		body_circle.radius = 8.0
		cs.shape = body_circle
		cs.disabled = true
		add_child(cs)
	
	name_label.text = shop_data.shopkeeper_name if shop_data else "Shopkeeper"
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	get_node("/root/EventBus").interact_pressed.connect(_on_interact_pressed)

	# Placeholder sprite
	if not sprite.texture:
		sprite.texture = _create_placeholder_sprite()
		sprite.scale = Vector2(3, 3)
		sprite.position = Vector2(-24, -40)
	
	# Cache interaction_area reference
	if has_node("InteractionArea"):
		interaction_area = get_node("InteractionArea") as Area2D
	
	print("[Shopkeeper] Ready complete, sprite.texture = ", sprite.texture != null)


func _create_placeholder_sprite() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.8, 0.0, 1.0))  # Bright gold
	var tex := ImageTexture.create_from_image(img)
	return tex


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		print("[Shopkeeper] Player entered range")


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		print("[Shopkeeper] Player left range")


func _on_interact_pressed() -> void:
	print("[Shopkeeper] interact_pressed received, player_in_range: ", _player_in_range, " shop_data: ", shop_data != null)
	if not _player_in_range or not shop_data:
		return
	
	if _shop_ui_active:
		_close_shop()
	else:
		_open_shop()


func _open_shop() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	# Find player inventory
	var inv = null
	for child: Node in player.get_children():
		var script_path: String = child.get_script().resource_path if child.get_script() else ""
		if script_path == "res://scripts/inventory_component.gd":
			inv = child
			break
	
	if not inv:
		print("[Shopkeeper] No player inventory found")
		return
	
	_player_inventory = inv
	
	# Create shop UI
	_shop_ui = _create_shop_ui(inv)
	if _shop_ui:
		_shop_ui_active = true
		get_node("/root/EventBus").shop_opened.emit()


func _close_shop() -> void:
	if _shop_ui:
		_shop_ui.queue_free()
		_shop_ui = null
	_shop_ui_active = false
	_player_inventory = null
	get_node("/root/EventBus").shop_closed.emit()


func _create_shop_ui(player_inv) -> Control:
	var canvas := CanvasLayer.new()
	canvas.name = "ShopUICanvas"
	canvas.layer = 30
	get_tree().root.add_child(canvas)
	
	var ui_root := Panel.new()
	ui_root.name = "ShopUIRoot"
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_root)
	
	# Semi-transparent dark background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	ui_root.add_child(bg)
	
	# Main shop panel
	var panel := Panel.new()
	panel.name = "ShopPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(600, 400)
	panel.position = -panel.size / 2
	ui_root.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	
	# Shop title
	var title := Label.new()
	title.name = "Title"
	title.text = shop_data.shop_name + " - " + shop_data.shopkeeper_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	
	# Gold display
	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	var gs: Node = get_node("/root/GameState")
	gold_label.text = "Your Gold: " + str(gs.player_gold)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(gold_label)
	
	vbox.add_child(HSeparator.new())
	
	# Content Row (Shop Items | Player Inventory)
	var hbox := HBoxContainer.new()
	hbox.name = "ContentRow"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)
	
	# Left: Shop Items
	var shop_list := _build_item_list("Shop Items", shop_data.stock_items, true)
	hbox.add_child(shop_list)
	
	# Right: Player Items
	var player_list := _build_player_items_list(player_inv)
	hbox.add_child(player_list)
	
	vbox.add_child(HSeparator.new())
	
	# Close button
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close Shop (ESC)"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_close_shop)
	vbox.add_child(close_btn)
	
	# Input handling
	ui_root.gui_input.connect(_on_shop_ui_input)
	
	return ui_root


func _on_shop_ui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("ui_cancel"):
		_close_shop()


func _build_item_list(title_text: String, stock_items: Array, _is_shop_side: bool) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var header := Label.new()
	header.text = title_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	container.add_child(header)
	
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var item_vbox := VBoxContainer.new()
	item_vbox.name = "ItemList"
	item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_vbox)
	
	for stock_entry in stock_items:
		var uid: String = stock_entry.get("unique_id", "")
		var price_override: int = stock_entry.get("price_override", -1)
		
		# Load item data
		var item_path: String = "res://resources/items/" + uid + ".tres"
		var item: Resource = load(item_path)
		if not item:
			continue
		
		var base_price: int = item.get("value") if item else 0
		var price: int = price_override if price_override >= 0 else base_price * shop_data.sell_multiplier
		
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl := Label.new()
		name_lbl.text = item.get("item_name") if item else uid
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		
		var price_lbl := Label.new()
		price_lbl.text = str(int(price)) + "g"
		price_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		row.add_child(price_lbl)
		
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.pressed.connect(func(): _buy_item(uid, price))
		row.add_child(buy_btn)
		
		item_vbox.add_child(row)
	
	return container


func _build_player_items_list(player_inv) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var header := Label.new()
	header.text = "Your Inventory"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	container.add_child(header)
	
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)
	
	var item_vbox := VBoxContainer.new()
	item_vbox.name = "PlayerItems"
	item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_vbox)
	
	var items: Array = player_inv.get_stored_items() if player_inv.has_method("get_stored_items") else []
	
	for stored in items:
		var uid: String = stored.get("unique_id", "")
		var count: int = stored.get("count", 0)
		
		var item_path: String = "res://resources/items/" + uid + ".tres"
		var item: Resource = load(item_path)
		if not item:
			continue
		
		var base_price: int = item.get("value") if item else 0
		var sell_price: int = base_price * shop_data.buy_multiplier
		
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl := Label.new()
		name_lbl.text = item.get("item_name") + " x" + str(count) if item else uid
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		
		var price_lbl := Label.new()
		price_lbl.text = str(int(sell_price)) + "g"
		price_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		row.add_child(price_lbl)
		
		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.pressed.connect(func(): _sell_item(uid, sell_price))
		row.add_child(sell_btn)
		
		item_vbox.add_child(row)
	
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(Empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_vbox.add_child(empty_lbl)
	
	return container


func _buy_item(item_id: String, price: int) -> void:
	var gs: Node = get_node("/root/GameState")
	if gs.player_gold < price:
		print("[Shop] Not enough gold!")
		return
	
	if not _player_inventory or not _player_inventory.has_method("add_item"):
		return
	
	# Add item to player
	var item_path := "res://resources/items/" + item_id + ".tres"
	var item := load(item_path)
	if not item:
		return
	
	var ok: bool = _player_inventory.add_item(item, 1)
	if ok:
		gs.spend_gold(price)
		print("[Shop] Bought ", item_id, " for ", price, "g")
		_close_shop()
		_open_shop()  # Refresh
	else:
		print("[Shop] Inventory full!")


func _sell_item(item_id: String, price: int) -> void:
	if not _player_inventory or not _player_inventory.has_method("remove_item"):
		return
	
	var ok: bool = _player_inventory.remove_item(item_id, 1)
	if ok:
		var gs: Node = get_node("/root/GameState")
		gs.add_gold(price)
		print("[Shop] Sold ", item_id, " for ", price, "g")
		_close_shop()
		_open_shop()  # Refresh
	else:
		print("[Shop] Failed to sell ", item_id)
