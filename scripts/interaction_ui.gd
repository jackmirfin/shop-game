extends CanvasLayer
## Minimal, reusable interaction UI — registered as the "InteractionUI" autoload.
##
## Provides the smallest possible popups needed by the interaction system:
##   * a dismissible text/dialogue/container message box
##   * a Yes / No confirmation dialog
##
## The whole UI is built at runtime, so NO level scene needs a UI node and no
## scene artwork or layout is touched. While a popup is open, blocks_player()
## returns true so the Player stops moving.

const PANEL_WIDTH: float = 660.0

var _message_panel: Panel
var _title_label: Label
var _message_label: Label
var _hint_label: Label

var _confirm_panel: Panel
var _confirm_label: Label
var _yes_button: Button
var _no_button: Button

var _open: bool = false
var _mode: String = "" ## "" | "message" | "confirm"
var _confirmation_id: String = ""
var _on_confirmed: Callable = Callable()


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## True while a popup is open — the Player uses this to pause movement.
func blocks_player() -> bool:
	return _open


# --- Public API ---

func show_message(text: String) -> void:
	_open_message("", text, "Press E to close")


func show_dialogue(dialogue_id: String, text: String = "") -> void:
	var speaker: String = dialogue_id.replace("_", " ").capitalize()
	var body: String = text
	if body.is_empty():
		body = "(no dialogue system is active yet — placeholder hook for \"%s\")" % dialogue_id
	_open_message(speaker, body, "Press E to close")


func show_inventory(inventory_id: String) -> void:
	var body: String = "(container \"%s\" — inventory UI not implemented yet)" % inventory_id
	_open_message("Container: %s" % inventory_id, body, "Press E to close")


func show_confirm(text: String, confirmation_id: String, on_result: Callable) -> void:
	_confirmation_id = confirmation_id
	_on_confirmed = on_result
	_confirm_label.text = text
	_hide_all()
	_confirm_panel.visible = true
	_open = true
	_mode = "confirm"


func close() -> void:
	_hide_all()


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return

	if _mode == "confirm":
		if event.is_action_pressed("ui_cancel"):
			_resolve_confirm(false)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Internal ---

func _open_message(title: String, body: String, hint: String) -> void:
	_title_label.text = title
	_title_label.visible = not title.is_empty()
	_message_label.text = body
	_hint_label.text = hint
	_hide_all()
	_message_panel.visible = true
	_open = true
	_mode = "message"


func _hide_all() -> void:
	_message_panel.visible = false
	_confirm_panel.visible = false
	_open = false
	_mode = ""


func _resolve_confirm(accepted: bool) -> void:
	var callback: Callable = _on_confirmed
	_confirmation_id = ""
	_on_confirmed = Callable()
	_hide_all()
	if callback.is_valid():
		callback.call(accepted)


func _on_yes_pressed() -> void:
	_resolve_confirm(true)


func _on_no_pressed() -> void:
	_resolve_confirm(false)


func _build() -> void:
	var root := Control.new()
	root.name = "InteractionUIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Message panel (TEXT / DIALOGUE / INVENTORY) ---
	_message_panel = Panel.new()
	_message_panel.name = "MessagePanel"
	_message_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_message_panel.visible = false
	_message_panel.anchor_left = 0.5
	_message_panel.anchor_right = 0.5
	_message_panel.anchor_top = 1.0
	_message_panel.anchor_bottom = 1.0
	_message_panel.offset_left = -PANEL_WIDTH * 0.5
	_message_panel.offset_right = PANEL_WIDTH * 0.5
	_message_panel.offset_top = -200.0
	_message_panel.offset_bottom = -30.0
	root.add_child(_message_panel)

	var message_margin := MarginContainer.new()
	message_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	message_margin.add_theme_constant_override("margin_left", 18)
	message_margin.add_theme_constant_override("margin_top", 14)
	message_margin.add_theme_constant_override("margin_right", 18)
	message_margin.add_theme_constant_override("margin_bottom", 12)
	_message_panel.add_child(message_margin)

	var message_box := VBoxContainer.new()
	message_box.add_theme_constant_override("separation", 8)
	message_margin.add_child(message_box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	message_box.add_child(_title_label)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_label.add_theme_font_size_override("font_size", 16)
	message_box.add_child(_message_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	message_box.add_child(_hint_label)

	# --- Confirm panel (CONFIRM) ---
	_confirm_panel = Panel.new()
	_confirm_panel.name = "ConfirmPanel"
	_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_panel.visible = false
	_confirm_panel.anchor_left = 0.5
	_confirm_panel.anchor_right = 0.5
	_confirm_panel.anchor_top = 1.0
	_confirm_panel.anchor_bottom = 1.0
	_confirm_panel.offset_left = -PANEL_WIDTH * 0.5
	_confirm_panel.offset_right = PANEL_WIDTH * 0.5
	_confirm_panel.offset_top = -180.0
	_confirm_panel.offset_bottom = -30.0
	root.add_child(_confirm_panel)

	var confirm_margin := MarginContainer.new()
	confirm_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_margin.add_theme_constant_override("margin_left", 18)
	confirm_margin.add_theme_constant_override("margin_top", 14)
	confirm_margin.add_theme_constant_override("margin_right", 18)
	confirm_margin.add_theme_constant_override("margin_bottom", 12)
	_confirm_panel.add_child(confirm_margin)

	var confirm_box := VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 10)
	confirm_margin.add_child(confirm_box)

	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_label.add_theme_font_size_override("font_size", 16)
	confirm_box.add_child(_confirm_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	confirm_box.add_child(buttons)

	_yes_button = Button.new()
	_yes_button.text = "Yes"
	_yes_button.pressed.connect(_on_yes_pressed)
	buttons.add_child(_yes_button)

	_no_button = Button.new()
	_no_button.text = "No"
	_no_button.pressed.connect(_on_no_pressed)
	buttons.add_child(_no_button)
