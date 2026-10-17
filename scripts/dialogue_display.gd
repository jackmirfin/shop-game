extends Control
## Manages dialogue display and progression.
## Created at runtime by the DialogueManager autoload (or added to game.tscn).

@onready var panel: Panel = $Panel
@onready var speaker_label: Label = $Panel/Margin/VBox/SpeakerMargin/SpeakerLabel
@onready var text_label: Label = $Panel/Margin/VBox/TextMargin/TextLabel
@onready var choices_container: VBoxContainer = $Panel/Margin/VBox/Choices
@onready var continue_hint: Label = $Panel/Margin/VBox/ContinueHint


var _current_line: DialogueLineData = null
var _dialogue_map: Dictionary = {}  ## id -> DialogueLineData
var is_active: bool = false
var _awaiting_choice: bool = false
var _initialized: bool = false
var _continue_hint_shown: bool = false
var _line_transitioning: bool = false
var _current_side: String = "left"
const SPEAKER_PRESENTATIONS: Dictionary = {
	"ERDEN": {"display_name": "ERDEN", "side": "left", "portrait_dir": "res://assets/Dialogue/NPCs/Erden_dialogue"},
	"ERDON": {"display_name": "ERDON", "side": "left", "portrait_dir": "res://assets/Dialogue/NPCs/Erden_dialogue"},
	"HOLT": {"display_name": "HOLT", "side": "right", "portrait_dir": "res://assets/Dialogue/NPCs/Holt_dialogue"},
	"BLACKSMITH": {"display_name": "BLACKSMITH", "side": "left", "portrait_dir": ""},
}


func _ready() -> void:
	_initialize_runtime()


func _initialize_runtime() -> void:
	if _initialized:
		return
	panel = get_node("Panel") as Panel
	speaker_label = get_node("Panel/Margin/VBox/SpeakerMargin/SpeakerLabel") as Label
	text_label = get_node("Panel/Margin/VBox/TextMargin/TextLabel") as Label
	choices_container = get_node("Panel/Margin/VBox/Choices") as VBoxContainer
	continue_hint = get_node("Panel/Margin/VBox/ContinueHint") as Label
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_dialogue_mouse_entered)
	panel.mouse_exited.connect(_on_dialogue_mouse_exited)
	hide()
	if not EventBus.dialogue_started.is_connected(_on_dialogue_started):
		EventBus.dialogue_started.connect(_on_dialogue_started)
	if not EventBus.dialogue_ended.is_connected(_on_dialogue_ended):
		EventBus.dialogue_ended.connect(_on_dialogue_ended)
	set_process_input(true)
	set_process_unhandled_key_input(true)
	_initialized = true


func _on_dialogue_mouse_entered() -> void:
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor != null:
		cursor.set_click_uses_active(false)
		cursor.set_idle()

func _on_dialogue_mouse_exited() -> void:
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor != null:
		cursor.set_click_uses_active(true)
		cursor.set_idle()


func _input(event: InputEvent) -> void:
	if not is_active or _line_transitioning:
		return
	var proceed: bool = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	if event is InputEventKey and event.pressed and not event.echo:
		proceed = proceed or event.physical_keycode == KEY_E or event.keycode == KEY_E
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and panel != null and panel.get_global_rect().has_point(event.position):
		proceed = true
	if proceed and not _awaiting_choice:
		get_viewport().set_input_as_handled()
		_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_active or _awaiting_choice or _line_transitioning:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_E or event.keycode == KEY_E):
		get_viewport().set_input_as_handled()
		_advance()


func start_dialogue(lines: Array[DialogueLineData], start_id: String = "0") -> void:
	is_active = true
	_line_transitioning = false
	_awaiting_choice = false
	_continue_hint_shown = false
	_dialogue_map.clear()

	for line: DialogueLineData in lines:
		_dialogue_map[line.resource_path.get_file().get_basename()] = line

	show()
	EventBus.dialogue_started.emit("")

	if _dialogue_map.has(start_id):
		_show_line(_dialogue_map[start_id])
	else:
		_show_line(lines[0])


func _apply_presentation(speaker_name: String) -> void:
	var key: String = speaker_name.strip_edges().to_upper()
	var presentation: Dictionary = SPEAKER_PRESENTATIONS.get(key, {
		"display_name": speaker_name,
		"side": "left",
		"portrait_dir": "",
	}) as Dictionary
	_current_side = str(presentation["side"])
	var viewport_size: Vector2 = get_viewport_rect().size
	const BOX_CANVAS_SIZE: Vector2 = Vector2(1200.0, 768.0)
	const BOX_VISIBLE_SIZE: Vector2 = Vector2(888.0, 294.0)
	var visible_position: Vector2 = Vector2(24.0,
		viewport_size.y - BOX_VISIBLE_SIZE.y - 10.0)
	var visible_offset: Vector2 = Vector2(186.0, 228.0)
	if _current_side == "right":
		visible_position.x = viewport_size.x - BOX_VISIBLE_SIZE.x - 10.0
		visible_offset = Vector2(138.0, 234.0)
	var box_position: Vector2 = visible_position - visible_offset
	var box: TextureRect = get_node("BoxTexture") as TextureRect
	box.show()
	panel.show()
	box.texture = load("res://assets/Dialogue/UI/dialoguebox-right.png" if _current_side == "right" else "res://assets/Dialogue/UI/dialoguebox-left.png") as Texture2D
	box.position = box_position
	box.size = BOX_CANVAS_SIZE
	panel.position = visible_position
	panel.size = BOX_VISIBLE_SIZE
	var margin: MarginContainer = get_node("Panel/Margin") as MarginContainer
	var speaker_margin: MarginContainer = get_node("Panel/Margin/VBox/SpeakerMargin") as MarginContainer
	var text_margin: MarginContainer = get_node("Panel/Margin/VBox/TextMargin") as MarginContainer
	speaker_margin.add_theme_constant_override("margin_left", 80 if _current_side == "right" else 12)
	speaker_margin.add_theme_constant_override("margin_top", 8)
	text_margin.add_theme_constant_override("margin_left", 70 if _current_side == "right" else 10)
	text_margin.add_theme_constant_override("margin_top", 17 if _current_side == "right" else 32)
	margin.add_theme_constant_override("margin_left", 88 if _current_side == "right" else 60)
	margin.add_theme_constant_override("margin_right", 150)
	margin.add_theme_constant_override("margin_top", 85 if _current_side == "right" else 70)
	margin.add_theme_constant_override("margin_bottom", 24)
	var portrait: AnimatedSprite2D = get_node("Portrait") as AnimatedSprite2D
	var portrait_dir: String = str(presentation["portrait_dir"])
	var blacksmith_portrait: bool = key == "BLACKSMITH"
	if portrait_dir.is_empty() and not blacksmith_portrait:
		portrait.hide()
		return
	portrait.show()
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 3.0)
	frames.set_animation_loop(&"idle", true)
	var portrait_scale: float = 8.0
	var portrait_union: Rect2 = Rect2(1.0, 1.0, 25.0, 28.0)
	if blacksmith_portrait:
		var sheet: Texture2D = preload("res://assets/Dialogue/NPCs/blacksmithdialogue.png")
		var frame_width: float = sheet.get_width() / 4.0
		for index: int in range(4):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(frame_width * float(index), 0.0, frame_width, sheet.get_height())
			frames.add_frame(&"idle", atlas)
		portrait_scale = 0.4
		# The sheet has transparent headroom below the portrait. Use its visible
		# bounds so the beard rests on the dialogue box edge like Holt's portrait.
		portrait_union = Rect2(0.0, 204.0, frame_width, 395.0)
	else:
		for index: int in range(4):
			var path: String = "%s/tile%03d.png" % [portrait_dir, index]
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				frames.add_frame(&"idle", texture)
		if key == "ERDEN" or key == "ERDON":
			portrait_union = Rect2(1.0, 1.0, 25.0, 27.0)
	portrait.sprite_frames = frames
	portrait.animation = &"idle"
	portrait.scale = Vector2(portrait_scale, portrait_scale)
	var portrait_visible_left: float = visible_position.x + (72.0 if _current_side == "left" else BOX_VISIBLE_SIZE.x - 72.0 - portrait_union.size.x * portrait_scale)
	portrait.position = Vector2(
		portrait_visible_left - portrait_union.position.x * portrait_scale,
		visible_position.y + 48.0 - (portrait_union.position.y + portrait_union.size.y) * portrait_scale)
	portrait.flip_h = false
	portrait.play(&"idle")


func _show_line(line: DialogueLineData) -> void:
	_current_line = line
	# A pause node is intentionally silent: it hides the dialogue chrome and advances
	# automatically, so pacing never appears as text inside the dialogue box.
	if line.pause_seconds > 0.0 and line.text.strip_edges().is_empty():
		_line_transitioning = true
		(get_node("BoxTexture") as TextureRect).hide()
		panel.hide()
		(get_node("Portrait") as AnimatedSprite2D).hide()
		await get_tree().create_timer(line.pause_seconds).timeout
		_line_transitioning = false
		if _current_line != line or not is_active:
			return
		var pause_next: String = line.get_next()
		if not pause_next.is_empty() and _dialogue_map.has(pause_next):
			_show_line(_dialogue_map[pause_next])
		else:
			_end_dialogue()
		return
	_apply_presentation(line.speaker_name)
	_awaiting_choice = false

	# Clear previous choices
	for child: Node in choices_container.get_children():
		child.queue_free()

	var presentation: Dictionary = SPEAKER_PRESENTATIONS.get(line.speaker_name.strip_edges().to_upper(), {}) as Dictionary
	speaker_label.text = str(presentation.get("display_name", line.speaker_name))
	var speaker_key: String = line.speaker_name.strip_edges().to_upper()
	# The blacksmith portrait occupies more of the box's vertical budget; keep his
	# longer lines comfortably inside the visible dialogue panel.
	text_label.add_theme_font_size_override("font_size", 30 if speaker_key == "BLACKSMITH" else 37)
	text_label.text = line.text

	# Check condition
	if line.condition_flag and not line.condition_flag.is_empty():
		if not _check_flag(line.condition_flag):
			_advance()
			return

	# Set flag
	if line.set_flag and not line.set_flag.is_empty():
		_set_flag(line.set_flag)

	if line.has_choices():
		_awaiting_choice = true
		continue_hint.hide()
		for i: int in line.choices.size():
			var btn := Button.new()
			btn.text = line.choices[i]
			btn.size_flags_horizontal = Control.SIZE_FILL
			var choice_idx: int = i
			btn.pressed.connect(func(): _on_choice(choice_idx))
			choices_container.add_child(btn)
	else:
		continue_hint.hide()


func _advance() -> void:
	if not _current_line:
		return

	var next_id: String = _current_line.get_next()
	if next_id and not next_id.is_empty() and _dialogue_map.has(next_id):
		if next_id == "erdon_rescue_31":
			var encounter: Node = get_node_or_null("/root/EncounterManager")
			if encounter != null and encounter.has_method("play_holt_afterthought"):
				await encounter.play_holt_afterthought()
		_show_line(_dialogue_map[next_id])
	else:
		_end_dialogue()


func _on_choice(choice_idx: int) -> void:
	if not _current_line:
		return

	var next_id: String = _current_line.get_next(choice_idx)
	if next_id and not next_id.is_empty() and _dialogue_map.has(next_id):
		_show_line(_dialogue_map[next_id])
	else:
		_end_dialogue()


func _end_dialogue() -> void:
	is_active = false
	_current_line = null
	hide()
	EventBus.dialogue_ended.emit("")


func _on_dialogue_started(_npc_name: String) -> void:
	pass  # Dialogue started externally


func _on_dialogue_ended(_npc_name: String) -> void:
	# This signal is emitted by _end_dialogue itself; calling it again would recurse.
	pass


func _check_flag(flag: String) -> bool:
	return flag in GameState  # Simple existence check on GameState properties


func _set_flag(flag: String) -> void:
	GameState.set(flag, true)
