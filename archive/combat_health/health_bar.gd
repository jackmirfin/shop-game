extends Node2D


@onready var health_bar: Sprite2D = $Health
@onready var default_width: float = health_bar.region_rect.size.x
@onready var default_height: float = health_bar.region_rect.size.y


func update_health(current_health: int, max_health: int = 100) -> void:
	var new_width: float = (float(current_health) / float(max_health)) * default_width
	health_bar.region_rect = Rect2(0, 0, new_width, default_height)
