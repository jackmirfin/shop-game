extends Node
## Reusable health component. Attach as a child to any node that needs health.
## Emits signals so parent scripts / UI can react without tight coupling.

signal health_changed(current: int, max_hp: int)
signal damage_taken(amount: int, knockback_direction: Vector2)
signal died()
signal healed(amount: int)

@export var max_health: int = 100
@export var current_health: int = 100

var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func take_damage(amount: int, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	current_health = max(0, current_health - amount)
	damage_taken.emit(amount, knockback_direction)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead:
		return

	var old_health := current_health
	current_health = min(max_health, current_health + amount)
	var actual_heal := current_health - old_health

	if actual_heal > 0:
		healed.emit(actual_heal)
		health_changed.emit(current_health, max_health)


func set_max_health(new_max: int) -> void:
	max_health = max(1, new_max)
	if current_health > max_health:
		current_health = max_health
	health_changed.emit(current_health, max_health)


func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)
