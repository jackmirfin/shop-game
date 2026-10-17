extends TeaWorldNode
## A hidden passage that only exists in the Tea World.
## Creates a door with interaction zone. Walking into it triggers the door.

signal door_entered()  # Emitted when player walks through the door

@export var door_label: String = "???"
@export var door_width: float = 32.0
@export var door_height: float = 48.0
@export var one_shot: bool = false  # If true, door disappears after first use

var _sprite: Sprite2D = null
var _area: Area2D = null
var _label: Label = null
var _used: bool = false
var _player_inside: bool = false


func _ready() -> void:
	_create_door_visual()
	_create_interaction_area()
	super._ready()


func _create_door_visual() -> void:
	# Door sprite — dark rectangular portal/doorway
	_sprite = Sprite2D.new()
	_sprite.name = "DoorSprite"
	_sprite.centered = true
	_sprite.visible = false
	
	# Create a simple dark doorway texture
	var img := Image.create(int(door_width), int(door_height), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.0, 0.02, 0.9))  # Dark purple-black
	# Add a faint border
	for x in range(img.get_width()):
		for y in range(img.get_height()):
			if x < 2 or x > img.get_width() - 3 or y < 2 or y > img.get_height() - 3:
				img.set_pixel(x, y, Color(0.15, 0.05, 0.1, 0.7))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.scale = Vector2(1.5, 1.5)
	
	add_child(_sprite)
	
	# Optional label above the door
	_label = Label.new()
	_label.name = "DoorLabel"
	_label.text = door_label
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-40, -door_height - 20)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	_label.visible = false
	_label.size = Vector2(80, 20)
	add_child(_label)


func _create_interaction_area() -> void:
	_area = Area2D.new()
	_area.name = "DoorArea"
	
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(door_width, door_height)
	cs.shape = rect
	
	_area.add_child(cs)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_area.monitoring = false  # Off until tea world activates
	
	add_child(_area)


func _on_body_entered(body: Node2D) -> void:
	if _used and one_shot:
		return
	if body.is_in_group("player"):
		_player_inside = true
		_use_door()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _use_door() -> void:
	if _used and one_shot:
		return
	_used = true
	door_entered.emit()
	
	if one_shot:
		# Fade out and disable
		var tween: Tween = create_tween()
		tween.tween_property(_sprite, "modulate:a", 0.0, 1.0)
		await tween.finished
		_area.monitoring = false
		_sprite.visible = false
		_label.visible = false


func _on_world_state_changed(entering_tea: bool) -> void:
	if _used and one_shot:
		return
	
	if _sprite:
		_sprite.visible = entering_tea
		if entering_tea:
			_sprite.modulate = Color(1, 1, 1, 0)
			var tween: Tween = create_tween()
			tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), 1.0)
	if _area:
		_area.monitoring = entering_tea
	if _label:
		_label.visible = entering_tea
