extends CharacterBody2D


enum FacingDirection {
	DOWN,
	RIGHT,
	UP,
	LEFT
}


const SPEED: float = 35.0


@export_category("Enemy")
@export var enemy_type: String = "skeleton"


@export_category("Combat")
@export var attack_damage: int = 10
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 1.0


@export_category("Loot")
@export var loot_table: Array[Dictionary] = []
## Example:
## [{
##     "unique_id": "bone",
##     "drop_chance": 0.8,
##     "min_count": 1,
##     "max_count": 3
## }]


var is_alive: bool = true
var target: CharacterBody2D = null

var facing_direction: FacingDirection = FacingDirection.DOWN
var attack_cooldown_remaining: float = 0.0


@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var take_damage_sound: AudioStreamPlayer2D = $TakeDamage
@onready var health_bar: Node2D = %HealthBar
@onready var health_component: Node = $HealthComponent


func _ready() -> void:
	add_to_group("enemy")

	# Default skeleton loot when none is configured in the Inspector.
	if loot_table.is_empty():
		loot_table = [{
			"unique_id": "bone",
			"drop_chance": 0.8,
			"min_count": 1,
			"max_count": 3
		}]

	if health_component:
		health_component.died.connect(_on_died)
		health_component.health_changed.connect(_on_health_changed)

	_play_directional_animation("Idle")


func _physics_process(delta: float) -> void:
	_update_attack_cooldown(delta)

	if not is_alive:
		velocity = Vector2.ZERO
		return

	if not is_instance_valid(target):
		target = null
		velocity = Vector2.ZERO
		_play_directional_animation("Idle")
		return

	var direction_to_target := global_position.direction_to(
		target.global_position
	)

	_update_facing_direction(direction_to_target)

	var distance_to_target := global_position.distance_to(
		target.global_position
	)

	if distance_to_target <= attack_range:
		velocity = Vector2.ZERO
		_try_attack()
	else:
		_chase_target(direction_to_target)

	move_and_slide()


func _update_attack_cooldown(delta: float) -> void:
	if attack_cooldown_remaining <= 0.0:
		return

	attack_cooldown_remaining = maxf(
		attack_cooldown_remaining - delta,
		0.0
	)


func _chase_target(direction: Vector2) -> void:
	velocity = direction * SPEED
	_play_directional_animation("Walk")


func _try_attack() -> void:
	# Continue showing the attack animation while in attack range.
	_play_directional_animation("Attack")

	if attack_cooldown_remaining > 0.0:
		return

	if not is_instance_valid(target):
		return

	if not target.has_method("take_damage"):
		push_warning(
			"Skeleton target does not have a take_damage() method."
		)
		return

	# Confirm the player is still within range.
	var distance_to_target := global_position.distance_to(
		target.global_position
	)

	if distance_to_target > attack_range:
		return

	# The player's script must support:
	# take_damage(damage: int, attacker_position: Vector2)
	target.take_damage(
		attack_damage,
		global_position
	)

	attack_cooldown_remaining = attack_cooldown


func _update_facing_direction(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return

	# Choose the dominant movement axis.
	if absf(direction.x) > absf(direction.y):
		if direction.x > 0.0:
			facing_direction = FacingDirection.RIGHT
		else:
			facing_direction = FacingDirection.LEFT
	else:
		if direction.y < 0.0:
			facing_direction = FacingDirection.UP
		else:
			facing_direction = FacingDirection.DOWN


func _play_directional_animation(action: StringName) -> void:
	var animation_name: StringName

	match facing_direction:
		FacingDirection.DOWN:
			animation_name = action
			animated_sprite_2d.flip_h = false

		FacingDirection.RIGHT:
			animation_name = StringName("%s_right" % action)
			animated_sprite_2d.flip_h = false

		FacingDirection.LEFT:
			animation_name = StringName("%s_right" % action)
			animated_sprite_2d.flip_h = true

		FacingDirection.UP:
			animation_name = StringName("%s_up" % action)
			animated_sprite_2d.flip_h = false

	if animated_sprite_2d.animation != animation_name:
		animated_sprite_2d.play(animation_name)


func take_damage(
	damage: int,
	attacker_position: Vector2
) -> void:
	if not is_alive:
		return

	if not health_component:
		return

	var knockback_direction := attacker_position.direction_to(
		global_position
	)

	health_component.take_damage(
		damage,
		knockback_direction
	)


func _on_died() -> void:
	if not is_alive:
		return

	is_alive = false
	target = null
	velocity = Vector2.ZERO

	# Death has no directional variants.
	animated_sprite_2d.flip_h = false
	animated_sprite_2d.play("Death")

	take_damage_sound.pitch_scale = 0.5
	take_damage_sound.play()

	var body_collision := get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	if body_collision:
		body_collision.set_deferred("disabled", true)

	var sight_collision := get_node_or_null(
		"Sight/CollisionShape2D"
	) as CollisionShape2D

	if sight_collision:
		sight_collision.set_deferred("disabled", true)

	if health_bar:
		health_bar.hide()

	EventBus.enemy_killed.emit(self, enemy_type)
	GameState.record_kill(enemy_type)

	call_deferred("_drop_loot")


func _drop_loot() -> void:
	for loot_entry: Dictionary in loot_table:
		var drop_chance: float = clampf(
			loot_entry.get("drop_chance", 0.0),
			0.0,
			1.0
		)

		if randf() > drop_chance:
			continue

		var unique_id: String = loot_entry.get(
			"unique_id",
			""
		)

		if unique_id.is_empty():
			continue

		var item_path := (
			"res://resources/items/%s.tres" % unique_id
		)

		if not ResourceLoader.exists(item_path):
			push_warning(
				"Loot resource does not exist: %s" % item_path
			)
			continue

		var item := load(item_path) as ItemData

		if not item:
			push_warning(
				"Resource is not valid ItemData: %s" % item_path
			)
			continue

		var min_count: int = maxi(
			loot_entry.get("min_count", 1),
			1
		)

		var max_count: int = maxi(
			loot_entry.get("max_count", 1),
			min_count
		)

		var count := randi_range(
			min_count,
			max_count
		)

		_spawn_pickup(item, count)


func _spawn_pickup(item: ItemData, count: int) -> void:
	var parent := get_parent()

	if not parent:
		return

	var spawn_position := global_position
	var pickup := Area2D.new()

	pickup.name = "Pickup_" + item.unique_id
	pickup.set_script(
		load("res://scripts/pickup.gd")
	)

	pickup.set("item_data", item)
	pickup.set("count", count)
	pickup.set("despawn_time", 30.0)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = item.icon_texture
	pickup.add_child(sprite)

	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"

	var circle := CircleShape2D.new()
	circle.radius = 12.0

	collision_shape.shape = circle
	pickup.add_child(collision_shape)

	parent.add_child(pickup)
	pickup.global_position = spawn_position


func _on_health_changed(
	current: int,
	max_hp: int
) -> void:
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current, max_hp)

	if is_alive and current > 0:
		take_damage_sound.pitch_scale = 1.0
		take_damage_sound.play()


func _on_sight_body_entered(body: Node2D) -> void:
	if not is_alive:
		return

	if not body.is_in_group("player"):
		return

	var player := body as CharacterBody2D

	if player:
		target = player
		print("Player detected by skeleton")


func _on_sight_body_exited(body: Node2D) -> void:
	if body != target:
		return

	target = null
	velocity = Vector2.ZERO

	if is_alive:
		_play_directional_animation("Idle")
