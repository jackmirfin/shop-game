extends Control
## Manages dialogue display and progression.
## Created at runtime by the DialogueManager autoload (or added to game.tscn).

@onready var panel: Panel = $Panel
@onready var speaker_label: Label = $Panel/Margin/SpeakerLabel
@onready var text_label: Label = $Panel/Margin/TextLabel
@onready var choices_container: VBoxContainer = $Panel/Margin/Choices
@onready var continue_hint: Label = $Panel/Margin/ContinueHint


var _current_line: DialogueLineData = null
var _dialogue_map: Dictionary = {}  ## id -> DialogueData
var is_active: bool = false
var _awaiting_choice: bool = false


func _ready() -> void:
	hide()
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _awaiting_choice:
			return  # Choices are handled by buttons
		_advance()


func start_dialogue(lines: Array[DialogueLineData], start_id: String = "0") -> void:
	is_active = true
	_awaiting_choice = false
	_dialogue_map.clear()

	for line: DialogueLineData in lines:
		_dialogue_map[line.resource_path.get_file().get_basename()] = line

	show()
	EventBus.dialogue_started.emit("")

	if _dialogue_map.has(start_id):
		_show_line(_dialogue_map[start_id])
	else:
		_show_line(lines[0])


func _show_line(line: DialogueLineData) -> void:
	_current_line = line
	_awaiting_choice = false

	# Clear previous choices
	for child: Node in choices_container.get_children():
		child.queue_free()

	speaker_label.text = line.speaker_name
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
		continue_hint.show()


func _advance() -> void:
	if not _current_line:
		return

	var next_id: String = _current_line.get_next()
	if next_id and not next_id.is_empty() and _dialogue_map.has(next_id):
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
	_end_dialogue()


func _check_flag(flag: String) -> bool:
	return flag in GameState  # Simple existence check on GameState properties


func _set_flag(flag: String) -> void:
	GameState.set(flag, true)
