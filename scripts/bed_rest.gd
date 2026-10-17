class_name BedRest
extends Interactable
## Rest interaction for the shop basement bed.

const BLINK_DURATION: float = 0.42
const BLINK_COLOR: Color = Color(1.0, 0.96, 0.84, 1.0)

func _ready() -> void:
	interaction_type = InteractionType.TEXT
	super._ready()

func interact() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inventory: Node = get_node_or_null("/root/Inventory")
	if inventory != null and inventory.has_method("restore_full_health"):
		inventory.restore_full_health()
	if player.has_method("set_control_enabled"):
		player.set_control_enabled(false)
	_play_blink(player)

func _play_blink(player: Node) -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "BedRestBlink"
	canvas.layer = 100
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(canvas)
	var overlay: ColorRect = ColorRect.new()
	overlay.color = BLINK_COLOR
	overlay.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(overlay, "modulate:a", 1.0, BLINK_DURATION * 0.5)
	tween.tween_property(overlay, "modulate:a", 0.0, BLINK_DURATION * 0.5)
	await tween.finished
	if is_instance_valid(player) and player.has_method("set_control_enabled"):
		player.set_control_enabled(true)
	canvas.queue_free()
