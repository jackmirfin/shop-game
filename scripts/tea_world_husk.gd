extends TeaWorldNode
## A silent watcher — black shadow blob with long eyes and mouth.
## Only visible in the Tea World. Does nothing but watch.

@export var float_amplitude: float = 4.0
@export var float_speed: float = 1.0

var _sprite: Sprite2D = null
var _original_y: float = 0.0
var _float_offset: float = 0.0


func _ready() -> void:
	# Create sprite at runtime
	_sprite = Sprite2D.new()
	_sprite.name = "HuskSprite"
	_sprite.centered = true
	_sprite.scale = Vector2(2.0, 2.0)
	_sprite.visible = false
	
	var tex: Texture2D = load("res://assets/generated/husk_entity.png")
	if tex:
		_sprite.texture = tex
	else:
		# Fallback: generate a simple colored sprite
		var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.3, 0.8, 0.5))
		_sprite.texture = ImageTexture.create_from_image(img)
	
	add_child(_sprite)
	
	_original_y = _sprite.position.y
	
	# Randomize float offset so husks don't bob in sync
	_float_offset = randf() * TAU
	
	super._ready()


func _process(delta: float) -> void:
	if not _sprite or not _sprite.visible:
		return
	
	# Subtle floating bob
	_float_offset += delta * float_speed
	_sprite.position.y = _original_y + sin(_float_offset) * float_amplitude
	
	# Slow idly blink variation — slightly scale pulse
	var pulse: float = 1.0 + sin(_float_offset * 0.7) * 0.03
	_sprite.scale = Vector2(2.0 * pulse, 2.0 * pulse)


func _on_world_state_changed(_entering_tea: bool) -> void:
	if _sprite:
		_sprite.visible = _entering_tea
		# Reset position when appearing
		if _entering_tea:
			_sprite.position.y = _original_y
			_sprite.modulate = Color(1, 1, 1, 0)
			var tween: Tween = create_tween()
			tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 0.85), 1.5)
	
