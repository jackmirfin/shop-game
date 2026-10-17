class_name CombatTutorial
extends Control

const DIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.42)
const OUTLINE_COLOR: Color = Color(1.0, 0.86, 0.3, 0.95)
const OUTLINE_WIDTH: float = 3.0
const TUTORIAL_FONT: Font = preload("res://assets/Fonts/cardfont.ttf")

var _dimmer: Array[ColorRect] = []
var _outline: Array[ColorRect] = []
var _message: SystemMessageDisplay = null
var _targets: Array[Array] = []
var _messages: Array[String] = []
var _step: int = 0
var _finished_callback: Callable = Callable()
var _tutorial_font: Font = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_dimmer()
	_message = SystemMessageDisplay.new()
	_message.name = "TutorialMessage"
	_message.process_mode = Node.PROCESS_MODE_ALWAYS
	_message.input_enabled = false
	_message.presentation_scale = 3.0
	_message.message_font_size = 26
	var font_variation: FontVariation = FontVariation.new()
	font_variation.base_font = TUTORIAL_FONT
	font_variation.set_spacing(TextServer.SPACING_SPACE, 2)
	_tutorial_font = font_variation
	add_child(_message)
	_message.set_message_alignment_center()
	hide()

func start(steps: Array[Array], messages: Array[String], finished_callback: Callable) -> void:
	_targets = steps
	_messages = messages
	_finished_callback = finished_callback
	_step = 0
	show()
	_show_step()

func _create_dimmer() -> void:
	for index: int in 4:
		var dim: ColorRect = ColorRect.new()
		dim.color = DIM_COLOR
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		_dimmer.append(dim)
	for index: int in 4:
		var edge: ColorRect = ColorRect.new()
		edge.color = OUTLINE_COLOR
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(edge)
		_outline.append(edge)

func _show_step() -> void:
	if _step >= _messages.size() or _step >= _targets.size():
		_finish()
		return
	_update_target_rect()
	_message.show_system_message(_messages[_step], 20.0)
	_message.set_message_font(_tutorial_font)
	_message.center_message_in_box()

func _update_target_rect() -> void:
	var target_rect: Rect2 = Rect2()
	var first: bool = true
	for target_variant: Variant in _targets[_step]:
		var target: Control = target_variant as Control
		if target == null or not is_instance_valid(target):
			continue
		var source_rect: Rect2 = target.get_global_rect()
		var rect: Rect2 = Rect2(source_rect.position - Vector2(10.0, 14.0),
			source_rect.size + Vector2(20.0, 28.0))
		if first:
			target_rect = rect
			first = false
		else:
			target_rect = target_rect.merge(rect)
	if first:
		target_rect = Rect2(0.0, 0.0, get_viewport_rect().size.x, get_viewport_rect().size.y)
	var viewport_size: Vector2 = get_viewport_rect().size
	_dimmer[0].position = Vector2(0.0, 0.0)
	_dimmer[0].size = Vector2(viewport_size.x, target_rect.position.y)
	_dimmer[1].position = Vector2(0.0, target_rect.end.y)
	_dimmer[1].size = Vector2(viewport_size.x, viewport_size.y - target_rect.end.y)
	_dimmer[2].position = Vector2(0.0, target_rect.position.y)
	_dimmer[2].size = Vector2(target_rect.position.x, target_rect.size.y)
	_dimmer[3].position = Vector2(target_rect.end.x, target_rect.position.y)
	_dimmer[3].size = Vector2(viewport_size.x - target_rect.end.x, target_rect.size.y)
	_outline[0].position = target_rect.position
	_outline[0].size = Vector2(target_rect.size.x, OUTLINE_WIDTH)
	_outline[1].position = Vector2(target_rect.position.x, target_rect.end.y - OUTLINE_WIDTH)
	_outline[1].size = Vector2(target_rect.size.x, OUTLINE_WIDTH)
	_outline[2].position = target_rect.position
	_outline[2].size = Vector2(OUTLINE_WIDTH, target_rect.size.y)
	_outline[3].position = Vector2(target_rect.end.x - OUTLINE_WIDTH, target_rect.position.y)
	_outline[3].size = Vector2(OUTLINE_WIDTH, target_rect.size.y)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var proceed: bool = event.is_action_pressed("interact")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and _message != null and _message.visible:
		var message_box: Control = _message.get_node_or_null("SystemMessageBox") as Control
		proceed = message_box != null and message_box.get_global_rect().has_point(event.position)
	if not proceed:
		return
	get_viewport().set_input_as_handled()
	_step += 1
	_show_step()

func _finish() -> void:
	_message.hide_system_message()
	hide()
	var callback: Callable = _finished_callback
	_finished_callback = Callable()
	if callback.is_valid():
		callback.call()
