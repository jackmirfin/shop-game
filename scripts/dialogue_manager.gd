extends Node
## Autoload for dialogue display (registered as "DialogueManager" in project.godot).
## The actual UI is created and managed programmatically.
## Use DialogueManager.start(npc_dialogue_lines) to trigger conversation.

var _display: Control = null
var _system_display: SystemMessageDisplay = null
var _system_canvas: CanvasLayer = null
const LEFT_BOX: Texture2D = preload("res://assets/Dialogue/UI/dialoguebox-left.png")
const RIGHT_BOX: Texture2D = preload("res://assets/Dialogue/UI/dialoguebox-right.png")
const DETERMINATION_FONT: Font = preload("res://assets/Fonts/cardfont.ttf")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(lines: Array[DialogueLineData], start_id: String = "0") -> void:
	if _display == null:
		_create_display()
	_display.start_dialogue(lines, start_id)


func show_system_message(text: String, visible_top: float = 360.0,
		advance_callback: Callable = Callable(), presentation_scale: float = 4.0,
		message_font_size: int = 30, font_path: String = "",
		backdrop_path: String = "", font_color: Color = Color(1.0, 0.95, 0.82, 1.0)) -> void:
	if _system_display == null:
		_system_canvas = CanvasLayer.new()
		_system_canvas.name = "SystemMessageCanvas"
		_system_canvas.layer = 60
		_system_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_system_canvas)
		_system_display = SystemMessageDisplay.new()
		_system_display.name = "SystemMessageDisplay"
		_system_canvas.add_child(_system_display)
	_system_display.presentation_scale = presentation_scale
	_system_display.message_font_size = message_font_size
	var message_font: Font = null
	if not font_path.is_empty():
		message_font = load(font_path) as Font
	var backdrop: Texture2D = null
	if not backdrop_path.is_empty():
		backdrop = load(backdrop_path) as Texture2D
	_system_display.show_system_message(text, visible_top, advance_callback, message_font,
		backdrop, Vector2.ZERO, Vector2.ZERO, font_color)

func hide_system_message() -> void:
	if _system_display != null:
		_system_display.hide_system_message()

func set_dialogue_visible(visible: bool) -> void:
	if _display == null:
		return
	_display.visible = visible
	_display.set_process_input(visible)
	_display.set_process_unhandled_key_input(visible)

func is_active() -> bool:
	return _display != null and _display.is_active


func end() -> void:
	if _display:
		_display._end_dialogue()


func _create_display() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DialogueCanvas"
	canvas.layer = 30
	get_tree().root.add_child(canvas)

	_display = Control.new()
	_display.name = "DialogueDisplay"
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_display)

	var portrait := AnimatedSprite2D.new()
	portrait.name = "Portrait"
	portrait.z_index = 1
	portrait.centered = false
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.add_child(portrait)

	var box_texture := TextureRect.new()
	box_texture.name = "BoxTexture"
	box_texture.z_index = 2
	box_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box_texture.texture = LEFT_BOX
	box_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_display.add_child(box_texture)

	# Panel at bottom
	var panel := Panel.new()
	panel.name = "Panel"
	panel.z_index = 3
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.position = Vector2.ZERO
	panel.size = Vector2(640.0, 300.0)
	_display.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var speaker_margin := MarginContainer.new()
	speaker_margin.name = "SpeakerMargin"
	vbox.add_child(speaker_margin)

	var speaker_label := Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.add_theme_font_override("font", DETERMINATION_FONT)
	speaker_label.add_theme_font_size_override("font_size", 43)
	speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	speaker_margin.add_child(speaker_label)

	var text_margin := MarginContainer.new()
	text_margin.name = "TextMargin"
	text_margin.add_theme_constant_override("margin_left", 10)
	text_margin.add_theme_constant_override("margin_top", 20)
	vbox.add_child(text_margin)

	var text_label := Label.new()
	text_label.name = "TextLabel"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_override("font", DETERMINATION_FONT)
	text_label.add_theme_font_size_override("font_size", 37)
	text_margin.add_child(text_label)

	var choices_container := VBoxContainer.new()
	choices_container.name = "Choices"
	vbox.add_child(choices_container)

	var continue_hint := Label.new()
	continue_hint.name = "ContinueHint"
	continue_hint.text = "Press E to continue..."
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 22)
	continue_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	continue_hint.hide()
	vbox.add_child(continue_hint)

	# Attach the display script
	var script := load("res://scripts/dialogue_display.gd")
	_display.set_script(script)

	# The display node is scripted after its children are created, so its normal
	# onready lifecycle is not guaranteed. Initialize its references explicitly.
	if _display.has_method("_initialize_runtime"):
		_display.call("_initialize_runtime")
	_display.hide()
