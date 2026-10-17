extends CharacterBody2D


const SPEED: int = 35
const KNOCKBACK_FORCE: int = 16

var is_alive: bool = true
var target: CharacterBody2D = null

@export var enemy_type: String = "slime"
@export var loot_table: Array[Dictionary] = []  ## [{unique_id: "slime_gel", drop_chance: 0.5, min_count: 1, max_count: 3}]


@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var take_damage_sound: AudioStreamPlayer2D = $TakeDamage
@onready var health_bar: Node2D = %HealthBar
@onready var health_component: Node = $HealthComponent


func _ready() -> void:
	add_to_group("enemy")

	# Default loot table if none set in editor
	if loot_table.is_empty():
		loot_table = [{
			"unique_id": "slime_gel",
			"drop_chance": 0.8,
			"min_count": 1,
			"max_count": 3
		}]

	if health_component:
		health_component.died.connect(_on_died)
		health_component.health_changed.connect(_on_health_changed)


func _physics_process(delta: float) -> void:
	if is_alive and target:
		_attack(delta)
	



func _attack(delta: float) -> void:
	var direction := (target.position - position).normalized()
	position += direction * SPEED * delta
	animated_sprite_2d.play("attack")


func take_damage(damage: int, attacker_position: Vector2) -> void:
	if health_component:
		health_component.take_damage(damage, (position - attacker_position).normalized())


func _on_died() -> void:
	is_alive = false
	animated_sprite_2d.play("die")

	take_damage_sound.pitch_scale = 0.5
	take_damage_sound.play()

	# Disable collision
	$CollisionShape2D.set_deferred("disabled", true)
	$Sight/CollisionShape2D.set_deferred("disabled", true)

	# Remove health bar
	if health_bar:
		health_bar.hide()

	# Notify systems
	EventBus.enemy_killed.emit(self, enemy_type)
	GameState.record_kill(enemy_type)

	# Drop loot
	call_deferred("_drop_loot")


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


func _spawn_pickup(item: ItemData, count: int) -> void:
	var pickup: Area2D = Area2D.new()
	pickup.name = "Pickup_" + item.unique_id
	pickup.set_script(load("res://scripts/pickup.gd"))
	pickup.set("item_data", item)
	pickup.set("count", count)
	pickup.set("despawn_time", 30.0)

	# Add sprite
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	if item.icon_texture:
		sprite.texture = item.icon_texture
	else:
		sprite.texture = null
	pickup.add_child(sprite)

	# Add collision shape
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	pickup.add_child(shape)

	# Position at enemy's location
	pickup.global_position = global_position

	# Add to the world
	get_parent().add_child(pickup)


func _on_health_changed(current: int, max_hp: int) -> void:
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current, max_hp)

	# Play hurt sound if still alive
	if is_alive and current > 0:
		take_damage_sound.play()


func _on_sight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body
		print("Player detected")


func _on_sight_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and is_alive:
		target = null
		animated_sprite_2d.play("idle")
