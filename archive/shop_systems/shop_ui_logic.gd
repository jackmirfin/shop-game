extends Control
## Logic script attached to the ShopUI created by ShopManager.
## Handles item listing, selection, buy/sell actions.

var _shop_data: ShopData
var _player_inv: InventoryComponent
var _selected_shop_item: ItemData = null
var _selected_player_item: ItemData = null
var _mode: String = "buy"  ## "buy" or "sell"


func _on_shop_opened() -> void:
	_shop_data = get_meta("shop_data")
	_player_inv = get_meta("player_inv")

	# Update labels
	get_node("Panel/MainVBox/TitleBar/GoldLabel").text = "Gold: %d" % get_node('/root/GameState').player_gold
	get_node("Panel/MainVBox/TitleBar/ShopLabel").text = _shop_data.shop_name

	_refresh_shop_list()
	_refresh_player_list()
	_clear_info()


func _refresh_shop_list() -> void:
	var shop_list: VBoxContainer = get_meta("shop_list")
	for child: Node in shop_list.get_children():
		child.queue_free()

	for stock_entry: Dictionary in _shop_data.stock_items:
		var uid: String = stock_entry.get("unique_id", "")
		var item_path: String = "res://resources/items/%s.tres" % uid
		if not ResourceLoader.exists(item_path):
			continue
		var item: ItemData = load(item_path) as ItemData
		if not item:
			continue

		var price: int = _shop_data.get_item_price(item, true)
		var can_afford: bool = get_node('/root/GameState').player_gold >= price

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.text = item.get_display_name()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "%dg" % price
		if not can_afford:
			price_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.2))
		row.add_child(price_label)

		row.set_meta("item", item)
		row.set_meta("price", price)
		row.gui_input.connect(_on_shop_row_clicked.bind(row))

		shop_list.add_child(row)


func _refresh_player_list() -> void:
	var player_list: VBoxContainer = get_meta("player_list")
	for child: Node in player_list.get_children():
		child.queue_free()

	for slot: Dictionary in _player_inv.get_all_items():
		var item: ItemData = slot.item
		var count: int = slot.count
		var price: int = _shop_data.get_item_price(item, false)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.text = item.get_display_name()
		if count > 1:
			name_label.text += " x%d" % count
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "%dg" % price
		row.add_child(price_label)

		row.set_meta("item", item)
		row.set_meta("price", price)
		row.set_meta("count", count)
		row.gui_input.connect(_on_player_row_clicked.bind(row))

		player_list.add_child(row)


func _on_shop_row_clicked(event: InputEvent, row: HBoxContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		_selected_shop_item = row.get_meta("item")
		_selected_player_item = null
		_mode = "buy"
		_show_item_info(_selected_shop_item)
		_highlight_row(row, true)


func _on_player_row_clicked(event: InputEvent, row: HBoxContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		_selected_player_item = row.get_meta("item")
		_selected_shop_item = null
		_mode = "sell"
		_show_item_info(_selected_player_item)
		_highlight_row(row, false)


func _show_item_info(item: ItemData) -> void:
	var info_name: Label = get_meta("info_name")
	var info_desc: Label = get_meta("info_desc")
	var action_btn: Button = get_meta("action_btn")

	info_name.text = item.get_display_name()
	info_desc.text = item.description + "\n"

	if _mode == "buy":
		var price: int = _shop_data.get_item_price(item, true)
		info_desc.text += "\nPrice: %d gold" % price
		action_btn.text = "Buy"
		action_btn.disabled = get_node('/root/GameState').player_gold < price
	else:
		var price: int = _shop_data.get_item_price(item, false)
		info_desc.text += "\nSell for: %d gold" % price
		action_btn.text = "Sell"
		action_btn.disabled = _shop_data.shop_gold < price

	# Disconnect old connections
	for conn: Dictionary in action_btn.pressed.get_connections():
		action_btn.pressed.disconnect(conn.callable)

	action_btn.pressed.connect(_on_action_pressed)


func _clear_info() -> void:
	var info_name: Label = get_meta("info_name")
	var info_desc: Label = get_meta("info_desc")
	var action_btn: Button = get_meta("action_btn")
	info_name.text = "Select an item"
	info_desc.text = ""
	action_btn.text = "Buy"
	action_btn.disabled = true


func _highlight_row(active_row: HBoxContainer, is_shop: bool) -> void:
	# Reset all rows
	var lists: Array = [get_meta("shop_list"), get_meta("player_list")]
	for list: VBoxContainer in lists:
		for row: HBoxContainer in list.get_children():
			for child: Node in row.get_children():
				if child is Label:
					child.add_theme_color_override("font_color", Color.WHITE)

	# Highlight active
	for child: Node in active_row.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))


func _on_action_pressed() -> void:
	if _mode == "buy" and _selected_shop_item:
		_buy_item(_selected_shop_item)
	elif _mode == "sell" and _selected_player_item:
		_sell_item(_selected_player_item)


func _buy_item(item: ItemData) -> void:
	var price: int = _shop_data.get_item_price(item, true)
	if get_node('/root/GameState').player_gold < price:
		return

	get_node('/root/GameState').spend_gold(price)
	_shop_data.shop_gold += price
	_player_inv.add_item(item, 1)

	get_node('/root/EventBus').sale_completed.emit(item, price, _shop_data.shopkeeper_name)
	_refresh_shop_list()
	_refresh_player_list()
	_update_gold_display()
	_clear_info()


func _sell_item(item: ItemData) -> void:
	var price: int = _shop_data.get_item_price(item, false)
	if _shop_data.shop_gold < price:
		return

	var removed: int = _player_inv.remove_item(item.unique_id, 1)
	if removed <= 0:
		return

	GameState.add_gold(price)
	_shop_data.shop_gold -= price

	get_node('/root/EventBus').sale_completed.emit(item, price, _shop_data.shopkeeper_name)
	_refresh_shop_list()
	_refresh_player_list()
	_update_gold_display()
	_clear_info()


func _update_gold_display() -> void:
	var gold_label: Label = get_node("Panel/MainVBox/TitleBar/GoldLabel")
	gold_label.text = "Gold: %d" % get_node('/root/GameState').player_gold
