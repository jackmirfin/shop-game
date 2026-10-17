extends CharacterBody2D
## Intro enemy: a skeleton carrying an adventurer's bag.
## Guards the path to the village. Drops the bag on death.
## Simple enemy — stands guard and attacks when player approaches.

const SPEED: float = 40.0
const KNOCKBACK_FORCE: float = 120.0

var is_alive: bool = true
var target: CharacterBody2D = null

@export var enemy_type: String = "skeleton_bag"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_component: Node = $HealthComponent
@onready var sight_area: Area2D = $Sight


func _ready() -> void:
	add_to_group("enemy")

	if health_component:
		health_component.died.connect(_on_died)
		health_component.health_changed.connect(_on_health_changed)

	if sight_area:
		sight_area.body_entered.connect(_on_sight_body_entered)
		sight_area.body_exited.connect(_on_sight_body_exited)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if target:
		_chase(delta)
	else:
		_idle_float(delta)


func _chase(_delta: float) -> void:
	var direction: Vector2 = (target.position - position).normalized()
	velocity = direction * SPEED
	sprite.flip_h = direction.x < 0
	_play_anim("walk")
	move_and_slide()


func _idle_float(_delta: float) -> void:
	velocity = Vector2.ZERO
	_play_anim("idle")
	# Subtle floating bob
	var bob_offset: float = sin(Time.get_ticks_msec() * 0.002) * 3.0
	sprite.position.y = bob_offset


func _play_anim(prefix: String) -> void:
	if not sprite.sprite_frames:
		return
	if sprite.sprite_frames.has_animation(prefix):
		sprite.play(prefix)


func take_damage(damage: int, attacker_position: Vector2) -> void:
	if health_component:
		var knockback_dir: Vector2 = (position - attacker_position).normalized()
		health_component.take_damage(damage, knockback_dir)

	# Visual feedback — flash red
	if sprite:
		var tween: Tween = create_tween()
		tween.tween_property(sprite, "modulate", Color.RED, 0.1)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)


func _on_died() -> void:
	is_alive = false
	velocity = Vector2.ZERO

	# Disable collision
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if sight_area and sight_area.has_node("CollisionShape2D"):
		sight_area.get_node("CollisionShape2D").set_deferred("disabled", true)

	# Death visual — fade out
	if sprite:
		var tween: Tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tween.tween_callback(_drop_bag)

	# Notify systems
	EventBus.enemy_killed.emit(self, enemy_type)
	GameState.record_kill(enemy_type)


func _drop_bag() -> void:
	# Spawn the bag item pickup
	var item_path: String = "res://resources/items/adventurers_bag.tres"
	if not ResourceLoader.exists(item_path):
		push_error("Bag item not found: " + item_path)
		queue_free()
		return

	var item: ItemData = load(item_path) as ItemData
	if not item:
		queue_free()
		return

	var pickup: Area2D = Area2D.new()
	pickup.name = "Pickup_AdventurersBag"
	pickup.set_script(load("res://scripts/pickup.gd"))
	pickup.set("item_data", item)
	pickup.set("count", 1)
	pickup.set("despawn_time", 0.0)  # Never despawns — critical item

	# Add sprite for the pickup
	var pickup_sprite := Sprite2D.new()
	pickup_sprite.name = "Sprite2D"
	if item.icon_texture:
		pickup_sprite.texture = item.icon_texture
	else:
		# Fallback: create a small colored square
		var fallback := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(0.6, 0.4, 0.2, 1.0))
		pickup_sprite.texture = ImageTexture.create_from_image(fallback)
	pickup_sprite.scale = Vector2(1.0, 1.0)
	pickup.add_child(pickup_sprite)

	# Add collision shape
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	pickup.add_child(shape)

	# Position at enemy's location
	pickup.global_position = global_position

	# Add to the world
	get_parent().add_child(pickup)

	queue_free()


func _on_health_changed(_current: int, _max_hp: int) -> void:
	pass  # No health bar for intro enemy — kept simple


func _on_sight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and is_alive:
		target = body


func _on_sight_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = null
