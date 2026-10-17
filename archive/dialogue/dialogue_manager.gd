extends Node
## Autoload for dialogue display (registered as "DialogueManager" in project.godot).
## The actual UI is created and managed programmatically.
## Use DialogueManager.start(npc_dialogue_lines) to trigger conversation.

var _display: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(lines: Array[DialogueLineData], start_id: String = "0") -> void:
	if _display == null:
		_create_display()
	_display.start_dialogue(lines, start_id)


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

	# Panel at bottom
	var panel := Panel.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.position = Vector2(10, -130)
	panel.size = Vector2(0, 120)
	# Fix anchor-based sizing
	panel.anchor_left = 0.02
	panel.anchor_right = 0.98
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = -130.0
	panel.offset_right = 0.0
	panel.offset_bottom = -10.0
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

	var speaker_label := Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.add_theme_font_size_override("font_size", 16)
	speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(speaker_label)

	var text_label := Label.new()
	text_label.name = "TextLabel"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(text_label)

	var choices_container := VBoxContainer.new()
	choices_container.name = "Choices"
	vbox.add_child(choices_container)

	var continue_hint := Label.new()
	continue_hint.name = "ContinueHint"
	continue_hint.text = "Press Space to continue..."
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 12)
	continue_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	continue_hint.hide()
	vbox.add_child(continue_hint)

	# Attach the display script
	var script := load("res://scripts/dialogue_display.gd")
	_display.set_script(script)

	# Wait a frame for script to initialize
	await get_tree().process_frame
	_display.hide()
