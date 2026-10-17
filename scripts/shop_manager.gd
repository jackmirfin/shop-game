extends Node
## Autoload for managing shop UI lifecycle (registered as "ShopManager" in project.godot).

var _shop_ui: Control = null
var _is_open: bool = false
var _current_shop: ShopData = null
var _player_inventory: InventoryComponent = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func open_shop(shop_data: ShopData, player_inv: InventoryComponent) -> void:
	if _is_open:
		return
	_current_shop = shop_data
	_player_inventory = player_inv
	_is_open = true

	if _shop_ui == null:
		_create_shop_ui()

	_shop_ui.set_meta("shop_data", shop_data)
	_shop_ui.set_meta("player_inv", player_inv)
	_shop_ui.call("_on_shop_opened")
	_shop_ui.show()

	EventBus.shop_opened.emit()


func close_shop() -> void:
	if not _is_open:
		return
	_is_open = false
	if _shop_ui:
		_shop_ui.hide()
	EventBus.shop_closed.emit()


func is_shop_open() -> bool:
	return _is_open


func _create_shop_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ShopCanvas"
	canvas.layer = 30
	get_tree().root.add_child(canvas)

	_shop_ui = Control.new()
	_shop_ui.name = "ShopUI"
	_shop_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_ui.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks through
	canvas.add_child(_shop_ui)

	# Dark background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	_shop_ui.add_child(bg)

	# Main panel centered
	var panel := Panel.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(600, 420)
	panel.position = -panel.size / 2
	_shop_ui.add_child(panel)

	# VBox for layout
	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 6)
	panel.add_child(main_vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.name = "TitleBar"
	main_vbox.add_child(title_bar)

	var shop_label := Label.new()
	shop_label.name = "ShopLabel"
	shop_label.text = "Shop"
	shop_label.add_theme_font_size_override("font_size", 20)
	title_bar.add_child(shop_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)

	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title_bar.add_child(gold_label)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_on_close_pressed)
	title_bar.add_child(close_btn)

	# Content area: Shop items (left) | Center info | Player items (right)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	main_vbox.add_child(content)

	# Shop items list (left)
	var shop_panel := Panel.new()
	shop_panel.name = "ShopItemsPanel"
	shop_panel.custom_minimum_size = Vector2(220, 0)
	content.add_child(shop_panel)

	var shop_vbox := VBoxContainer.new()
	shop_vbox.name = "ShopVBox"
	shop_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_vbox.add_theme_constant_override("separation", 2)
	shop_panel.add_child(shop_vbox)

	var shop_header := Label.new()
	shop_header.name = "ShopHeader"
	shop_header.text = "Shop Items"
	shop_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_header.add_theme_font_size_override("font_size", 14)
	shop_vbox.add_child(shop_header)

	var shop_scroll := ScrollContainer.new()
	shop_scroll.name = "ShopScroll"
	shop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_vbox.add_child(shop_scroll)

	var shop_list := VBoxContainer.new()
	shop_list.name = "ShopList"
	shop_list.add_theme_constant_override("separation", 2)
	shop_scroll.add_child(shop_list)

	# Center info panel
	var info_panel := Panel.new()
	info_panel.name = "InfoPanel"
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(info_panel)

	var info_vbox := VBoxContainer.new()
	info_vbox.name = "InfoVBox"
	info_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(info_vbox)

	var info_name := Label.new()
	info_name.name = "InfoName"
	info_name.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(info_name)

	var info_desc := Label.new()
	info_desc.name = "InfoDesc"
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.add_theme_font_size_override("font_size", 12)
	info_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(info_desc)

	var action_btn := Button.new()
	action_btn.name = "ActionButton"
	action_btn.text = "Buy"
	action_btn.size_flags_horizontal = Control.SIZE_FILL
	info_vbox.add_child(action_btn)

	# Player items list (right)
	var player_panel := Panel.new()
	player_panel.name = "PlayerItemsPanel"
	player_panel.custom_minimum_size = Vector2(220, 0)
	content.add_child(player_panel)

	var player_vbox := VBoxContainer.new()
	player_vbox.name = "PlayerVBox"
	player_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	player_vbox.add_theme_constant_override("separation", 2)
	player_panel.add_child(player_vbox)

	var player_header := Label.new()
	player_header.name = "PlayerHeader"
	player_header.text = "Your Items"
	player_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_header.add_theme_font_size_override("font_size", 14)
	player_vbox.add_child(player_header)

	var player_scroll := ScrollContainer.new()
	player_scroll.name = "PlayerScroll"
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_vbox.add_child(player_scroll)

	var player_list := VBoxContainer.new()
	player_list.name = "PlayerList"
	player_list.add_theme_constant_override("separation", 2)
	player_scroll.add_child(player_list)

	# Store references as meta
	_shop_ui.set_meta("shop_list", shop_list)
	_shop_ui.set_meta("player_list", player_list)
	_shop_ui.set_meta("info_name", info_name)
	_shop_ui.set_meta("info_desc", info_desc)
	_shop_ui.set_meta("action_btn", action_btn)
	_shop_ui.set_meta("gold_label", gold_label)
	_shop_ui.set_meta("shop_label", shop_label)

	# Attach UI logic script
	var ui_script := load("res://scripts/shop_ui_logic.gd")
	_shop_ui.set_script(ui_script)

	_shop_ui.hide()


func _on_close_pressed() -> void:
	close_shop()
