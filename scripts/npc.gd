extends CharacterBody2D
## Base NPC that can be interacted with.

@export var npc_name: String = "NPC"
@export var dialogue_lines: Array[DialogueLineData] = []
@export var start_dialogue_id: String = "0"

@onready var interaction_area: Area2D = $InteractionArea
@onready var name_label: Label = $NameLabel
@onready var sprite: Sprite2D = $Sprite2D

var _player_in_range: bool = false


func _ready() -> void:
	add_to_group("npc")
	name_label.text = npc_name
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	get_node("/root/EventBus").interact_pressed.connect(_on_interact_pressed)
	
	# Ensure sprite is visible even without texture
	if not sprite.texture:
		sprite.texture = _create_placeholder_sprite()


func _create_placeholder_sprite() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.8, 1.0))  # Blue-ish NPC
	var tex := ImageTexture.create_from_image(img)
	return tex


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _on_interact_pressed() -> void:
	if not _player_in_range:
		return
	call_deferred("_start_dialogue")


func _start_dialogue() -> void:
	var dm: Node = get_node("/root/DialogueManager")
	if dm and dm.has_method("start"):
		if dialogue_lines.is_empty():
			var fallback := DialogueLineData.new()
			fallback.speaker_name = npc_name
			fallback.text = "Hello there! I am " + npc_name + "."
			dm.start([fallback], "0")
		else:
			dm.start(dialogue_lines, start_dialogue_id)
