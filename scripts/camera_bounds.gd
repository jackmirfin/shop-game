class_name CameraBounds
extends Node2D
## Defines camera boundary limits for a level.
## Player Camera2D reads these values on enter.

@export var limit_left: int = -10000000
@export var limit_right: int = 10000000
@export var limit_top: int = -10000000
@export var limit_bottom: int = 10000000
