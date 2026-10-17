class_name CustomCursorManager
extends Node
## Central native pixel-art cursor configuration.

const CURSOR_SCALE: float = 1.25
const IDLE_PATH: String = "res://assets/Inventory/mouseUI/mouse_idle.png"
const READY_PATH: String = "res://assets/Inventory/mouseUI/mouse_ready.png"
const ACTIVE_PATH: String = "res://assets/Inventory/mouseUI/mouse_active.png"

const IDLE_HOTSPOT := Vector2(5, 1)
const READY_HOTSPOT := Vector2(8, 1)
const ACTIVE_HOTSPOT := Vector2(15, 15)

var _idle: ImageTexture
var _ready_cursor: ImageTexture
var _active: ImageTexture
var _active_state: bool = false
var _click_uses_active: bool = true

func _ready() -> void:
	var idle_source: Texture2D = load(IDLE_PATH) as Texture2D
	var ready_source: Texture2D = load(READY_PATH) as Texture2D
	var active_source: Texture2D = load(ACTIVE_PATH) as Texture2D
	_idle = _scaled_texture(idle_source)
	_ready_cursor = _scaled_texture(ready_source)
	_active = _scaled_texture(active_source)
	_apply_normal_cursors()
	Input.set_custom_mouse_cursor(_active, Input.CURSOR_DRAG, ACTIVE_HOTSPOT)
	Input.set_custom_mouse_cursor(_active, Input.CURSOR_CAN_DROP, ACTIVE_HOTSPOT)
	Input.set_custom_mouse_cursor(_active, Input.CURSOR_FORBIDDEN, ACTIVE_HOTSPOT)
	set_process_input(true)
	get_tree().scene_changed.connect(reset)

func _scaled_texture(source: Texture2D) -> ImageTexture:
	var image: Image = source.get_image()
	var width: int = maxi(1, roundi(float(image.get_width()) * CURSOR_SCALE))
	var height: int = maxi(1, roundi(float(image.get_height()) * CURSOR_SCALE))
	image.resize(width, height, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)

func _apply_normal_cursors() -> void:
	Input.set_custom_mouse_cursor(_idle, Input.CURSOR_ARROW, IDLE_HOTSPOT)
	Input.set_custom_mouse_cursor(_ready_cursor, Input.CURSOR_POINTING_HAND, READY_HOTSPOT)

func set_idle() -> void:
	if _active_state:
		return
	Input.set_custom_mouse_cursor(_idle, Input.CURSOR_ARROW, IDLE_HOTSPOT)
	Input.set_custom_mouse_cursor(_idle, Input.CURSOR_POINTING_HAND, IDLE_HOTSPOT)

func set_ready() -> void:
	if _active_state:
		return
	_apply_normal_cursors()

func set_click_uses_active(allowed: bool) -> void:
	_click_uses_active = allowed
	if not allowed:
		set_active(false)

func set_active(active: bool) -> void:
	if _active_state == active:
		return
	_active_state = active
	if active:
		# Override both common native shapes so hover cannot replace ACTIVE.
		Input.set_custom_mouse_cursor(_active, Input.CURSOR_ARROW, ACTIVE_HOTSPOT)
		Input.set_custom_mouse_cursor(_active, Input.CURSOR_POINTING_HAND, ACTIVE_HOTSPOT)
		Input.set_custom_mouse_cursor(_active, Input.CURSOR_DRAG, ACTIVE_HOTSPOT)
		Input.set_custom_mouse_cursor(_active, Input.CURSOR_CAN_DROP, ACTIVE_HOTSPOT)
		Input.set_custom_mouse_cursor(_active, Input.CURSOR_FORBIDDEN, ACTIVE_HOTSPOT)
	else:
		_apply_normal_cursors()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pressed: bool = (event as InputEventMouseButton).pressed
		set_active(pressed and _click_uses_active)
		if pressed and not _click_uses_active:
			set_ready()

func reset() -> void:
	set_active(false)
	_apply_normal_cursors()
