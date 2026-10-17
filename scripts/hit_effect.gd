class_name HitEffect
extends Node2D
## Reusable, visual-only three-frame combat impact. It never changes combat state.

enum ImpactType {
	STANDARD_HIT,
	BLOCKED_HIT,
	FRACTURE,
	BLEED,
	POISON,
	BURN,
	CHILL,
	SHOCK,
	DOOM,
	ENTANGLE,
	THORNS,
	MARK,
}

signal peak_started
signal finished

const DISPLAY_SCALE: int = 4
const FRAME_DURATIONS: Array[float] = [0.10, 0.18, 0.12]
const EFFECT_FRAMES: Dictionary = {
	ImpactType.STANDARD_HIT: [
		preload("res://assets/Combat/hit-animations/frames/standard_hit/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/standard_hit/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/standard_hit/frame_03.png"),
	],
	ImpactType.BLOCKED_HIT: [
		preload("res://assets/Combat/hit-animations/frames/blocked_hit/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/blocked_hit/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/blocked_hit/frame_03.png"),
	],
	ImpactType.FRACTURE: [
		preload("res://assets/Combat/hit-animations/frames/fracture/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/fracture/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/fracture/frame_03.png"),
	],
	ImpactType.BLEED: [
		preload("res://assets/Combat/hit-animations/frames/bleed/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/bleed/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/bleed/frame_03.png"),
	],
	ImpactType.POISON: [
		preload("res://assets/Combat/hit-animations/frames/poison/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/poison/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/poison/frame_03.png"),
	],
	ImpactType.BURN: [
		preload("res://assets/Combat/hit-animations/frames/burn/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/burn/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/burn/frame_03.png"),
	],
	ImpactType.CHILL: [
		preload("res://assets/Combat/hit-animations/frames/chill/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/chill/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/chill/frame_03.png"),
	],
	ImpactType.SHOCK: [
		preload("res://assets/Combat/hit-animations/frames/shock/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/shock/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/shock/frame_03.png"),
	],
	ImpactType.DOOM: [
		preload("res://assets/Combat/hit-animations/frames/doom/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/doom/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/doom/frame_03.png"),
	],
	ImpactType.ENTANGLE: [
		preload("res://assets/Combat/hit-animations/frames/entangle/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/entangle/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/entangle/frame_03.png"),
	],
	ImpactType.THORNS: [
		preload("res://assets/Combat/hit-animations/frames/thorns/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/thorns/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/thorns/frame_03.png"),
	],
	ImpactType.MARK: [
		preload("res://assets/Combat/hit-animations/frames/mark/frame_01.png"),
		preload("res://assets/Combat/hit-animations/frames/mark/frame_02.png"),
		preload("res://assets/Combat/hit-animations/frames/mark/frame_03.png"),
	],
}

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
var _impact_type: ImpactType = ImpactType.STANDARD_HIT
var _started: bool = false

func setup(impact_type: ImpactType, display_scale: int = DISPLAY_SCALE) -> void:
	_impact_type = impact_type
	var integer_scale: int = maxi(1, display_scale)
	scale = Vector2(float(integer_scale), float(integer_scale))
	var frames: Array = EFFECT_FRAMES.get(impact_type, EFFECT_FRAMES[ImpactType.STANDARD_HIT]) as Array
	var sprite_frames: SpriteFrames = SpriteFrames.new()
	sprite_frames.add_animation(&"impact")
	sprite_frames.set_animation_loop(&"impact", false)
	_sprite.sprite_frames = sprite_frames
	_sprite.animation = &"impact"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for texture: Texture2D in frames:
		sprite_frames.add_frame(&"impact", texture)
	_sprite.stop()
	_sprite.frame = 0
	position = position.round()

func play_effect() -> void:
	if _started:
		return
	_started = true
	if _sprite.sprite_frames == null or _sprite.sprite_frames.get_frame_count(&"impact") != 3:
		_finish()
		return
	for frame_index: int in 3:
		_sprite.frame = frame_index
		if frame_index == 1:
			peak_started.emit()
		await get_tree().create_timer(FRAME_DURATIONS[frame_index]).timeout
		if not is_inside_tree():
			return
	_finish()

func _finish() -> void:
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()
