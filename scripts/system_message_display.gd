class_name SystemMessageDisplay
extends Control

const BOX_TEXTURE: Texture2D = preload("res://assets/Dialogue/UI/systemmessagebox.png")
const FONT: Font = preload("res://assets/Fonts/cardfont.ttf")
const LETTER_BACKDROP_SIZE := Vector2(267.0, 320.0)
const SOURCE_CANVAS_SIZE: Vector2 = Vector2(320.0, 107.0)
const SOURCE_VISIBLE_OFFSET: Vector2 = Vector2(9.0, 22.0)
const SOURCE_VISIBLE_SIZE: Vector2 = Vector2(302.0, 85.0)
var presentation_scale: float = 4.0
var message_font_size: int = 36

var _box: TextureRect = null
var _label: Label = null
var _advance_callback: Callable = Callable()
var _visible_top: float = 360.0
var input_enabled: bool = true
var _custom_backdrop: Texture2D = null
var _custom_backdrop_size: Vector2 = Vector2.ZERO
var _custom_text_inset: Vector2 = Vector2.ZERO
var _center_message: bool = false
var _cursor_over_visible_box: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func _process(_delta: float) -> void:
	_update_cursor_hover()
	if not _center_message or not visible or _box == null or _label == null:
		return
	var visible_offset: Vector2 = SOURCE_VISIBLE_OFFSET * presentation_scale
	var visible_size: Vector2 = SOURCE_VISIBLE_SIZE * presentation_scale
	var top_inset: Vector2 = Vector2(20.0, 25.0) * presentation_scale
	var bottom_inset: Vector2 = Vector2(20.0, 4.0) * presentation_scale
	_label.position = _box.position + visible_offset + top_inset
	_label.size = visible_size - top_inset - bottom_inset
	_label.clip_text = true


func _build() -> void:
	_box = TextureRect.new()
	_box.name = "SystemMessageBox"
	_box.texture = BOX_TEXTURE
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_box.stretch_mode = TextureRect.STRETCH_SCALE
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.z_index = 0
	add_child(_box)
	_label = Label.new()
	_label.name = "SystemMessage"
	_label.z_index = 100
	_label.visible = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 36)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

func show_system_message(text: String, visible_top: float = 360.0,
		advance_callback: Callable = Callable(), font: Font = null,
		backdrop: Texture2D = null, backdrop_size: Vector2 = Vector2.ZERO,
		text_inset: Vector2 = Vector2.ZERO, font_color: Color = Color(1.0, 0.95, 0.82, 1.0)) -> void:
	if _box == null:
		_build()
	var display_font: Font = FONT if font == null else font
	if font_color == Color.BLACK and font != null:
		var letter_font: FontVariation = FontVariation.new()
		letter_font.base_font = font
		letter_font.set_spacing(TextServer.SPACING_SPACE, -1)
		display_font = letter_font
	_label.add_theme_font_override("font", display_font)
	_label.add_theme_color_override("font_color", font_color)
	if font_color == Color.BLACK:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.0))
		_label.add_theme_constant_override("outline_size", 0)
		_label.add_theme_constant_override("line_spacing", -1)
	else:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_label.add_theme_constant_override("line_spacing", 0)
	_visible_top = visible_top
	_advance_callback = advance_callback
	_label.text = text
	_label.add_theme_font_size_override("font_size", message_font_size)
	_custom_backdrop = backdrop
	_custom_backdrop_size = backdrop_size
	_custom_text_inset = text_inset
	var viewport_size: Vector2 = get_viewport_rect().size
	var canvas_source_size: Vector2 = SOURCE_CANVAS_SIZE if backdrop == null else (LETTER_BACKDROP_SIZE if backdrop_size == Vector2.ZERO else backdrop_size)
	var canvas_size: Vector2 = canvas_source_size * presentation_scale
	var box_position: Vector2 = Vector2((viewport_size.x - canvas_size.x) * 0.5, _visible_top)
	_box.texture = BOX_TEXTURE if backdrop == null else backdrop
	_box.position = box_position
	_box.size = canvas_size
	if _center_message:
		var centered_inset: Vector2 = Vector2(35.0, 25.0) * presentation_scale
		_label.position = box_position + centered_inset
		_label.size = canvas_size - centered_inset * 2.0
	elif backdrop == null:
		var visible_offset: Vector2 = SOURCE_VISIBLE_OFFSET * presentation_scale
		var visible_size: Vector2 = SOURCE_VISIBLE_SIZE * presentation_scale
		_label.position = box_position + visible_offset + Vector2(23.0, 25.0) * presentation_scale
		_label.size = visible_size - Vector2(46.0, 37.0) * presentation_scale
	else:
		var inset: Vector2 = text_inset if text_inset != Vector2.ZERO else Vector2(20.0, 20.0)
		_label.position = box_position + inset * presentation_scale
		_label.size = canvas_size - inset * presentation_scale * 2.0
	if font_color == Color.BLACK:
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	show()

func set_message_alignment_center() -> void:
	if _label == null:
		return
	_center_message = true
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func center_message_in_box() -> void:
	if _label == null or _box == null:
		return
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var visible_offset: Vector2 = SOURCE_VISIBLE_OFFSET * presentation_scale
	var visible_size: Vector2 = SOURCE_VISIBLE_SIZE * presentation_scale
	var inset: Vector2 = Vector2(20.0, 10.0) * presentation_scale
	_label.position = _box.position + visible_offset + inset
	_label.size = visible_size - inset * 2.0
	_label.clip_text = true


func set_message_font(font: Font) -> void:
	if font == null or _label == null:
		return
	_label.add_theme_font_override("font", font)


func hide_system_message() -> void:
	_advance_callback = Callable()
	hide()

func _update_cursor_hover() -> void:
	var over_box: bool = false
	if visible and _box != null:
		var visible_offset: Vector2 = SOURCE_VISIBLE_OFFSET * presentation_scale
		var visible_size: Vector2 = SOURCE_VISIBLE_SIZE * presentation_scale
		var visible_rect: Rect2 = Rect2(_box.position + visible_offset, visible_size)
		over_box = visible_rect.has_point(get_viewport().get_mouse_position())
	if over_box == _cursor_over_visible_box:
		return
	_cursor_over_visible_box = over_box
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor != null:
		cursor.set_click_uses_active(not over_box)
		if over_box:
			cursor.set_idle()
		else:
			cursor.set_idle()

func _input(event: InputEvent) -> void:
	if not input_enabled or not visible:
		return
	var proceed: bool = event.is_action_pressed("interact")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and _box != null and _box.get_global_rect().has_point(event.position):
		proceed = true
	if not proceed: 
		return
	get_viewport().set_input_as_handled()
	var callback: Callable = _advance_callback
	if callback.is_valid():
		_advance_callback = Callable()
		hide_system_message()
		callback.call()
	else:
		hide_system_message()
