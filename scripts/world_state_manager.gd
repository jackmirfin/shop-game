extends Node
## Manages the Normal World / Tea World state.

enum WorldState { NORMAL, TEA }

var current_state: WorldState = WorldState.NORMAL
var tea_active: bool = false
var tea_time_remaining: float = 0.0
var tea_max_duration: float = 60.0

var _tea_nodes: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not InputMap.has_action("drink_tea"):
		InputMap.add_action("drink_tea")
		var key_event := InputEventKey.new()
		key_event.keycode = KEY_T
		InputMap.action_add_event("drink_tea", key_event)
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var e_key := InputEventKey.new()
		e_key.keycode = KEY_E
		InputMap.action_add_event("interact", e_key)

	call_deferred("_setup_tea_ui")
	call_deferred("_setup_gold_hud")
	call_deferred("_spawn_shop")


# --- Tea UI ---

var _tea_overlay: ColorRect = null
var _tea_hud_panel: Panel = null
var _tea_hud_label: Label = null
var _tea_hud_timer: ProgressBar = null
var _tea_hud_hint: Label = null


func _setup_tea_ui() -> void:
	var overlay_canvas := CanvasLayer.new()
	overlay_canvas.name = "TeaOverlayCanvas"
	overlay_canvas.layer = 10
	get_tree().root.add_child(overlay_canvas)

	_tea_overlay = ColorRect.new()
	_tea_overlay.name = "TeaWorldOverlay"
	_tea_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tea_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tea_overlay.modulate.a = 0.0

	var shader: Shader = load("res://assets/shaders/tea_world.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", 0.0)
	_tea_overlay.material = mat
	overlay_canvas.add_child(_tea_overlay)

	var hud_canvas := CanvasLayer.new()
	hud_canvas.name = "TeaHUDCanvas"
	hud_canvas.layer = 20
	get_tree().root.add_child(hud_canvas)

	var hud_control := Control.new()
	hud_control.name = "TeaHUD"
	hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.add_child(hud_control)

	_tea_hud_panel = Panel.new()
	_tea_hud_panel.name = "Panel"
	_tea_hud_panel.position = Vector2(0, 10)
	_tea_hud_panel.size = Vector2(210, 120)
	_tea_hud_panel.visible = false
	_tea_hud_panel.anchor_left = 1.0
	_tea_hud_panel.anchor_right = 1.0
	_tea_hud_panel.offset_left = -220.0
	_tea_hud_panel.offset_right = -10.0
	_tea_hud_panel.offset_top = 10.0
	_tea_hud_panel.offset_bottom = 130.0
	hud_control.add_child(_tea_hud_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_tea_hud_panel.add_child(vbox)

	_tea_hud_label = Label.new()
	_tea_hud_label.name = "Label"
	_tea_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tea_hud_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_tea_hud_label)

	_tea_hud_timer = ProgressBar.new()
	_tea_hud_timer.name = "TimerBar"
	_tea_hud_timer.min_value = 0.0
	_tea_hud_timer.max_value = tea_max_duration
	_tea_hud_timer.value = tea_max_duration
	_tea_hud_timer.size_flags_horizontal = Control.SIZE_FILL
	vbox.add_child(_tea_hud_timer)

	_tea_hud_hint = Label.new()
	_tea_hud_hint.name = "HintLabel"
	_tea_hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tea_hud_hint.add_theme_font_size_override("font_size", 12)
	_tea_hud_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_tea_hud_hint)

	var eb: Node = get_node("/root/EventBus")
	eb.tea_activated.connect(_on_tea_ui_activated)
	eb.tea_expired.connect(_on_tea_ui_expired)


func _on_tea_ui_activated() -> void:
	if _tea_overlay:
		_tea_overlay.modulate.a = 1.0
	if _tea_hud_panel:
		_tea_hud_panel.show()
		_tea_hud_label.text = "TEA WORLD"


func _on_tea_ui_expired() -> void:
	if _tea_overlay:
		_tea_overlay.modulate.a = 0.0
		if _tea_overlay.material and _tea_overlay.material is ShaderMaterial:
			var sm: ShaderMaterial = _tea_overlay.material as ShaderMaterial
			sm.set_shader_parameter("intensity", 0.0)
	if _tea_hud_panel:
		_tea_hud_panel.hide()
		_tea_hud_label.text = ""
		var gs: Node = get_node("/root/GameState")
		_tea_hud_hint.text = "Press T to brew tea" if (gs and gs.tea_unlocked) else ""


# --- Gold HUD ---

var _gold_label: Label = null


func _setup_gold_hud() -> void:
	# Don't show gold HUD on the main menu
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn":
		return

	var canvas := CanvasLayer.new()
	canvas.name = "GoldHUDCanvas"
	canvas.layer = 25
	get_tree().root.add_child(canvas)

	var panel := Panel.new()
	panel.name = "GoldPanel"
	panel.position = Vector2(10, 10)
	panel.size = Vector2(120, 30)
	canvas.add_child(panel)

	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gold_label.text = "Gold: %d" % get_node("/root/GameState").player_gold
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_gold_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_gold_label)


func _update_gold_hud() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % get_node("/root/GameState").player_gold


# --- Core ---

func _spawn_shop() -> void:
	var shop_node := Node.new()
	shop_node.name = "ShopSystemNode"
	shop_node.set_script(load("res://scripts/shop_system_node.gd"))
	add_child(shop_node)


func _process(delta: float) -> void:
	_update_gold_hud()

	if not tea_active:
		if Input.is_action_just_pressed("drink_tea"):
			activate_tea()
		return

	tea_time_remaining -= delta
	if tea_time_remaining <= 0.0:
		tea_time_remaining = 0.0
		deactivate_tea()
		return

	if _tea_overlay and _tea_overlay.material and _tea_overlay.material is ShaderMaterial:
		var sm: ShaderMaterial = _tea_overlay.material as ShaderMaterial
		sm.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
		var current: float = sm.get_shader_parameter("intensity")
		sm.set_shader_parameter("intensity", move_toward(current, 1.0, delta * 2.0))

	if _tea_hud_timer:
		_tea_hud_timer.value = tea_time_remaining
		if tea_time_remaining < 10.0:
			var flash: bool = fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0
			_tea_hud_label.modulate = Color.RED if flash else Color.WHITE
		else:
			_tea_hud_label.modulate = Color.WHITE


# --- Public API ---

func activate_tea(duration: float = -1.0) -> void:
	if tea_active:
		tea_time_remaining = duration if duration > 0.0 else tea_max_duration
		return

	tea_active = true
	tea_time_remaining = duration if duration > 0.0 else tea_max_duration
	current_state = WorldState.TEA
	_notify_all_tea_nodes(true)
	get_node("/root/EventBus").tea_activated.emit()
	get_node("/root/EventBus").world_state_changed.emit(WorldState.TEA)


func deactivate_tea() -> void:
	if not tea_active:
		return

	tea_active = false
	tea_time_remaining = 0.0
	current_state = WorldState.NORMAL
	_notify_all_tea_nodes(false)
	get_node("/root/EventBus").tea_expired.emit()
	get_node("/root/EventBus").world_state_changed.emit(WorldState.NORMAL)


func toggle_tea() -> void:
	if tea_active:
		deactivate_tea()
	else:
		activate_tea()


func is_tea_world() -> bool:
	return current_state == WorldState.TEA


func register_tea_node(node: Node) -> void:
	if node not in _tea_nodes:
		_tea_nodes.append(node)


func unregister_tea_node(node: Node) -> void:
	var idx := _tea_nodes.find(node)
	if idx != -1:
		_tea_nodes.remove_at(idx)


func _notify_all_tea_nodes(entering_tea: bool) -> void:
	for node: Node in _tea_nodes:
		if is_instance_valid(node) and node.has_method("_on_world_state_changed"):
			node._on_world_state_changed(entering_tea)
