extends Node2D
## Manages level loading and the persistent Player.
## The Player is a sibling of LevelRoot and survives level transitions.

var level: int = 0
var current_level_root: Node = null

@onready var player: CharacterBody2D = $Player


func _ready() -> void:
	current_level_root = $LevelRoot
	_setup_level(current_level_root)


#-------------------------------------------------------------------------------
#          Level Management
#-------------------------------------------------------------------------------

func _load_level(level_number: int) -> void:
	if current_level_root:
		# Reparent player back to Main before freeing the level
		if player.get_parent() == current_level_root:
			player.reparent(self)
		current_level_root.queue_free()

	var level_name: String = "level_%s" % level_number
	if level_number == 2:
		level_name = "level_2_village"
	var level_path: String = "res://scenes/Levels/%s.tscn" % level_name
	var new_level: Node = load(level_path).instantiate()
	add_child(new_level)
	move_child(new_level, 0)
	current_level_root = new_level
	current_level_root.name = "LevelRoot"

	_setup_level(current_level_root)


func _setup_level(level_root: Node) -> void:
	# Reposition PlayerSpawn and Exit from base_level per-level
	_configure_level_positions(level_root)

	var exit: Area2D = level_root.get_node_or_null("Exit")
	if exit:
		exit.body_entered.connect(_on_exit_body_entered)

	_move_player_to_spawn(level_root)
	_spawn_level_content(level_root)


func _configure_level_positions(level_root: Node) -> void:
 
	var spawn: Marker2D = level_root.get_node_or_null("PlayerSpawn")
	var exit: Area2D = level_root.get_node_or_null("Exit")

	match level:
		0:
			# Navaria village — use PlayerSpawn marker already in scene
			# (position set by the marker, don't override)
			if exit:
				exit.position = Vector2(32, 16)
				_ensure_exit_label(exit, "Leave Village")
		1:
			if spawn:
				spawn.position = Vector2(48, 108)
			if exit:
				exit.position = Vector2(640, 200)
				_ensure_exit_label(exit, "To Navaria Village")
		2:
			if spawn:
				spawn.position = Vector2(32, 160)
			if exit:
				exit.position = Vector2(32, 16)
				_ensure_exit_label(exit, "Leave Village")


func _ensure_exit_label(exit: Area2D, label_text: String) -> void:
	var label: Label = exit.get_node_or_null("ExitLabel")
	if not label:
		label = Label.new()
		label.name = "ExitLabel"
		exit.add_child(label)
	label.position = Vector2(-50, -30)
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)


func _move_player_to_spawn(level_root: Node) -> void:
	# Reparent player into the level root so y-sorting works correctly
	if player.get_parent() != level_root:
		player.reparent(level_root)
	
	var spawn: Marker2D = level_root.get_node_or_null("PlayerSpawn")
	if spawn:
		player.global_position = spawn.global_position
	else:
		push_warning("No PlayerSpawn found in level.")


#-------------------------------------------------------------------------------
#          Level Content
#-------------------------------------------------------------------------------

func _spawn_level_content(_level_root: Node) -> void:
	# Level content is now in scene files directly — no programmatic spawning needed.
	pass


#-------------------------------------------------------------------------------
#          Village Content (Level 1) — Cosy Navaria
#-------------------------------------------------------------------------------

func _spawn_village_content(level_root: Node) -> void:
	_spawn_decor_props(level_root)
	_spawn_greeter_mira(level_root)
	_spawn_elder_thomas(level_root)
	_spawn_adventurer_garrett(level_root)
	_spawn_noble_eleanor(level_root)
	_spawn_villager_baker(level_root)
	_spawn_villager_farmer(level_root)
	_spawn_shopkeeper_martha(level_root)


func _spawn_decor_props(level_root: Node) -> void:
	var lantern_tex: Texture2D = load("res://assets/generated/prop_lantern_frame_0.png")
	var flower_tex: Texture2D = load("res://assets/generated/prop_flower_box_frame_0.png")

	# Lanterns along the village path
	var lantern_positions: Array = [
		Vector2(80, 85), Vector2(160, 90), Vector2(280, 95),
		Vector2(380, 100), Vector2(500, 100), Vector2(600, 105)
	]
	for pos in lantern_positions:
		var lantern := Sprite2D.new()
		lantern.name = "Lantern"
		lantern.position = pos
		lantern.scale = Vector2(0.5, 0.5)
		if lantern_tex:
			lantern.texture = lantern_tex
		lantern.z_index = 1
		level_root.add_child(lantern)

	# Flower boxes flanking the shop door
	if flower_tex:
		for x_offset in [-60.0, 60.0]:
			var box := Sprite2D.new()
			box.name = "FlowerBox"
			box.position = Vector2(420 + x_offset, 145)
			box.scale = Vector2(0.45, 0.45)
			box.texture = flower_tex
			box.z_index = 1
			level_root.add_child(box)


## Helper to spawn and configure an NPC
func _spawn_npc(level_root: Node, npc_name: String, pos: Vector2, tex_path: String, dialogue_ids: Array) -> void:
	var npc_scene: PackedScene = load("res://scenes/npc.tscn")
	var npc: CharacterBody2D = npc_scene.instantiate()
	npc.name = npc_name
	npc.position = pos
	npc.set("npc_name", npc_name)
	npc.collision_layer = 0

	var sprite: Sprite2D = npc.get_node("Sprite2D")
	sprite.z_index = 1
	var tex: Texture2D = load(tex_path)
	if tex and sprite:
		sprite.texture = tex

	var dialogue_lines: Array = []
	for id in dialogue_ids:
		var dpath: String = "res://resources/dialogue/" + id + ".tres"
		if ResourceLoader.exists(dpath):
			dialogue_lines.append(load(dpath))

	if not dialogue_lines.is_empty():
		npc.set("dialogue_lines", dialogue_lines)
		npc.set("start_dialogue_id", dialogue_ids[0])

	level_root.add_child(npc)


func _spawn_greeter_mira(level_root: Node) -> void:
	_spawn_npc(level_root, "Mira", Vector2(100, 100),
		"res://assets/generated/npc_villager_woman_frame_0.png",
		["greeter_1", "greeter_2", "greeter_3", "greeter_4"])


func _spawn_elder_thomas(level_root: Node) -> void:
	_spawn_npc(level_root, "Old Thomas", Vector2(200, 160),
		"res://assets/generated/npc_elder_man_frame_0.png",
		["elder_1", "elder_2"])


func _spawn_adventurer_garrett(level_root: Node) -> void:
	_spawn_npc(level_root, "Garrett", Vector2(380, 140),
		"res://assets/generated/npc_adventurer_frame_0.png",
		["adventurer_1", "adventurer_2"])


func _spawn_noble_eleanor(level_root: Node) -> void:
	_spawn_npc(level_root, "Lady Eleanor", Vector2(520, 120),
		"res://assets/generated/npc_noble_frame_0.png", [])


func _spawn_villager_baker(level_root: Node) -> void:
	_spawn_npc(level_root, "Pippa", Vector2(300, 180),
		"res://assets/generated/npc_villager_woman_frame_0.png", [])


func _spawn_villager_farmer(level_root: Node) -> void:
	_spawn_npc(level_root, "Hugo", Vector2(580, 170),
		"res://assets/generated/npc_elder_man_frame_0.png", [])


func _spawn_shopkeeper_martha(level_root: Node) -> void:
	var sk_script: Script = load("res://scripts/shopkeeper.gd")
	var shop_data_res: Resource = load("res://resources/shops/general_store.tres")

	var sk := CharacterBody2D.new()
	sk.name = "Martha"
	sk.set_script(sk_script)
	sk.set("shop_data", shop_data_res)
	sk.collision_layer = 0
	sk.collision_mask = 0

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.scale = Vector2(2, 2)
	sk.add_child(sprite)

	var label := Label.new()
	label.name = "NameLabel"
	label.position = Vector2(-40, -35)
	label.size = Vector2(80, 15)
	label.text = "Martha"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	sk.add_child(label)

	sk.position = Vector2(440, 140)
	level_root.add_child(sk)


#-------------------------------------------------------------------------------
#          Level Exit
#-------------------------------------------------------------------------------

func _on_exit_body_entered(body: Node2D) -> void:
	if body == player:
		level += 1
		call_deferred("_load_level", level)
