extends Node2D
## Village decor spawner — adds buildings, NPCs, trees, props at runtime.

func _ready() -> void:
	_fix_exit()
	add_buildings()
	add_trees()
	add_bushes_flowers()
	add_props()
	add_npcs()
	add_shop_door()
	add_enemies()


func add_enemies() -> void:
	# Slime near the pond — harmless-looking but territorial
	var slime_scene: PackedScene = preload("res://scenes/Slime.tscn")
	var slime: Node2D = slime_scene.instantiate()
	slime.position = Vector2(480, 270)
	slime.name = "PondSlime"
	add_child(slime)

	# Spider lurking near bushes
	var spider_scene: PackedScene = preload("res://scenes/enemies/spider.tscn")
	var spider: Node2D = spider_scene.instantiate()
	spider.position = Vector2(420, 160)
	spider.name = "BushSpider"
	add_child(spider)


func _fix_exit() -> void:
	var exit_node: Area2D = get_node_or_null("Exit")
	if exit_node and exit_node.get_child_count() == 0:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32, 32)
		shape.shape = rect
		shape.position = Vector2(0, -8)
		exit_node.add_child(shape)


func add_buildings() -> void:
	var shop_tex := load("res://assets/generated/village_shop_frame_0.png")
	var house_tex := load("res://assets/generated/village_house_frame_0.png")

	var shop := Sprite2D.new()
	shop.name = "ShopBuilding"; shop.position = Vector2(272, 48)
	shop.texture = shop_tex; shop.z_index = 1; add_child(shop)

	var h1 := Sprite2D.new()
	h1.name = "House1"; h1.position = Vector2(96, 80)
	h1.texture = house_tex; h1.z_index = 1; add_child(h1)

	var h2 := Sprite2D.new()
	h2.name = "House2"; h2.position = Vector2(496, 80)
	h2.texture = house_tex; h2.z_index = 1; add_child(h2)


func add_trees() -> void:
	var tex := load("res://assets/generated/village_tree_frame_0.png")
	var positions := [Vector2(16,32), Vector2(16,128), Vector2(16,224), Vector2(16,304), Vector2(560,32), Vector2(560,128), Vector2(560,240), Vector2(400,304), Vector2(240,304)]
	for i: int in positions.size():
		var t := Sprite2D.new()
		t.name = "Tree" + str(i + 1); t.position = positions[i]
		t.texture = tex; t.z_index = 2; add_child(t)


func add_bushes_flowers() -> void:
	var bush_tex := load("res://assets/generated/village_bush_frame_0.png")
	for pos: Vector2 in [Vector2(80,130), Vector2(160,200), Vector2(450,130), Vector2(400,200)]:
		var b := Sprite2D.new()
		b.position = pos; b.texture = bush_tex; b.z_index = 1; add_child(b)

	var flower_tex := load("res://assets/generated/village_flowers_frame_0.png")
	for i: int in 2:
		var f := Sprite2D.new()
		f.name = "Flowers" + str(i + 1); f.position = Vector2(150 + i * 200, 165)
		f.texture = flower_tex; f.z_index = 1; add_child(f)


func add_props() -> void:
	# Signpost
	var sp := Sprite2D.new()
	sp.name = "Signpost"; sp.position = Vector2(120, 80)
	sp.texture = load("res://assets/generated/village_signpost_frame_0.png"); sp.z_index = 1
	var sl := Label.new()
	sl.name = "SignLabel"; sl.position = Vector2(-30, -20)
	sl.text = "Navaria"; sl.add_theme_font_size_override("font_size", 8)
	sl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4, 1))
	sp.add_child(sl); add_child(sp)

	# Barrels
	var barrel_tex := load("res://assets/generated/village_barrel_frame_0.png")
	for i: int in 2:
		var br := Sprite2D.new()
		br.name = "Barrel" + str(i + 1); br.position = Vector2(304 + i * 16, 75)
		br.texture = barrel_tex; br.z_index = 1; add_child(br)

	# Fences
	var fence_tex := load("res://assets/generated/village_fence_frame_0.png")
	for i: int in 4:
		var fn := Sprite2D.new()
		fn.name = "FenceL" + str(i + 1); fn.position = Vector2(64 + i * 16, 64)
		fn.texture = fence_tex; add_child(fn)
	for i: int in 4:
		var fn := Sprite2D.new()
		fn.name = "FenceR" + str(i + 1); fn.position = Vector2(480 + i * 16, 64)
		fn.texture = fence_tex; add_child(fn)


func add_npcs() -> void:
	var npc_script: Script = load("res://scripts/npc.gd")
	var textures := {
		"male": load("res://assets/generated/village_npc_male_frame_0.png"),
		"female": load("res://assets/generated/village_npc_female_frame_0.png"),
		"elder": load("res://assets/generated/village_npc_elder_frame_0.png"),
		"merchant": load("res://assets/generated/village_npc_merchant_frame_0.png"),
	}

	var npc_data: Array = [
		["Mira", Vector2(220, 180), "female"],
		["Old Thomas", Vector2(80, 180), "elder"],
		["Garrett", Vector2(400, 120), "male"],
		["Martha", Vector2(320, 200), "merchant"],
		["Pippa", Vector2(480, 160), "female"],
	]

	for data in npc_data:
		var nm: String = data[0]; var pos: Vector2 = data[1]; var tex: Texture2D = textures[data[2]]
		var npc := CharacterBody2D.new()
		npc.name = nm; npc.position = pos; npc.collision_layer = 0; npc.z_index = 1
		npc.set_script(npc_script); npc.set("npc_name", nm)

		var s := Sprite2D.new(); s.name = "Sprite2D"; s.texture = tex; s.z_index = 1; npc.add_child(s)

		var phys_shape := CollisionShape2D.new()
		var pc := CircleShape2D.new(); pc.radius = 8.0; phys_shape.shape = pc; npc.add_child(phys_shape)

		var ia := Area2D.new(); ia.name = "InteractionArea"; npc.add_child(ia)
		var ia_shape := CollisionShape2D.new()
		var ic := CircleShape2D.new(); ic.radius = 48.0; ia_shape.shape = ic; ia.add_child(ia_shape)

		var nl := Label.new()
		nl.name = "NameLabel"; nl.position = Vector2(-24, -20); nl.size = Vector2(48, 10)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.add_theme_font_size_override("font_size", 8)
		npc.add_child(nl)
		add_child(npc)


func add_shop_door() -> void:
	var sd := Area2D.new()
	sd.name = "ShopDoor"; sd.position = Vector2(272, 70); sd.z_index = 1
	sd.set_script(load("res://scripts/locked_door.gd"))

	var ds := CollisionShape2D.new()
	var dr := RectangleShape2D.new(); dr.size = Vector2(48, 64); ds.shape = dr
	sd.add_child(ds)

	var dp := Label.new()
	dp.name = "DoorPrompt"; dp.position = Vector2(-80, -50)
	dp.text = "The Adventurer's Emporium"; dp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dp.add_theme_font_size_override("font_size", 10)
	dp.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5, 1))
	sd.add_child(dp)

	add_child(sd)
