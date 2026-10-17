extends CharacterBody2D
## Generic enemy script for dungeon enemies (skeleton, spider, etc.)
## Reusable — configure via @export vars in the scene.

const KNOCKBACK_FORCE: float = 120.0

var is_alive: bool = true
var target: CharacterBody2D = null

@export var enemy_type: String = "skeleton"
@export var speed: float = 40.0
@export var max_health: int = 80
@export var damage: int = 10
@export var loot_table: Array[Dictionary] = []

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_component: Node = $HealthComponent
@onready var health_bar: Node2D = %HealthBar
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
		animated_sprite.play("idle")


func _chase(delta: float) -> void:
	var direction: Vector2 = (target.position - position).normalized()
	velocity = direction * speed
	animated_sprite.flip_h = direction.x < 0
	animated_sprite.play("walk")
	move_and_slide()


func take_damage(damage_amount: int, attacker_position: Vector2) -> void:
	if health_component:
		var knockback_dir: Vector2 = (position - attacker_position).normalized()
		health_component.take_damage(damage_amount, knockback_dir)

	# Flash red
	if animated_sprite:
		var tween: Tween = create_tween()
		tween.tween_property(animated_sprite, "modulate", Color.RED, 0.1)
		tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.15)


func _on_died() -> void:
	is_alive = false
	velocity = Vector2.ZERO

	# Disable collision
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if sight_area and sight_area.has_node("CollisionShape2D"):
		sight_area.get_node("CollisionShape2D").set_deferred("disabled", true)

	# Hide health bar
	if health_bar:
		health_bar.hide()

	# Death animation
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("die"):
		animated_sprite.play("die")
	else:
		# Fade out if no die animation
		if animated_sprite:
			var tween: Tween = create_tween()
			tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.4)
			tween.tween_callback(_drop_loot)
		return

	# Wait for die animation, then drop loot
	await get_tree().create_timer(0.6).timeout
	_drop_loot()


func _drop_loot() -> void:
	for loot_entry: Dictionary in loot_table:
		if randf() > loot_entry.get("drop_chance", 0.0):
			continue
		var unique_id: String = loot_entry.get("unique_id", "")
		if unique_id.is_empty():
			continue
		var item_path: String = "res://resources/items/%s.tres" % unique_id
		if not ResourceLoader.exists(item_path):
			continue
		var item: ItemData = load(item_path) as ItemData
		if not item:
			continue
		var min_count: int = loot_entry.get("min_count", 1)
		var max_count: int = loot_entry.get("max_count", 1)
		var count: int = randi_range(min_count, max_count)
		_spawn_pickup(item, count)

	queue_free()


func _spawn_pickup(item: ItemData, count: int) -> void:
	var pickup: Area2D = Area2D.new()
	pickup.name = "Pickup_" + item.unique_id
	pickup.set_script(load("res://scripts/pickup.gd"))
	pickup.set("item_data", item)
	pickup.set("count", count)
	pickup.set("despawn_time", 30.0)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	if item.icon_texture:
		sprite.texture = item.icon_texture
	pickup.add_child(sprite)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	pickup.add_child(shape)

	pickup.global_position = global_position
	get_parent().add_child(pickup)

	# Notify
	EventBus.enemy_killed.emit(self, enemy_type)
	GameState.record_kill(enemy_type)


func _on_health_changed(current: int, max_hp: int) -> void:
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current, max_hp)


func _on_sight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and is_alive:
		target = body


func _on_sight_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = null
