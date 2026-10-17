extends Node
## ShopSystem autoload — manages the player's shop, village hub, and counter view.
## Completely independent of main.gd — hooks into the scene tree via root lookup.

# Village state
var _village_built: bool = false
var _gave_starter_items: bool = false

# Shop state
var _shop_room: Node2D = null
var _shop_active: bool = false
var _shop_exit_position: Vector2 = Vector2.ZERO
var _player_in_tend_zone: bool = false

# Counter view state
var _counter_view: CanvasLayer = null
var _counter_active: bool = false


func _ready() -> void:
	# Hook into EventBus for save/load awareness
	var eb: Node = get_node("/root/EventBus")
	
	# Defer setup so the scene tree is ready
	call_deferred("_late_setup")


func _late_setup() -> void:
	# Give the game a moment to load, then set up the village
	await get_tree().process_frame
	await get_tree().process_frame
	_check_village_setup()


func _check_village_setup() -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	var level_root: Node = main.get_node_or_null("LevelRoot")
	if not level_root:
		return
	
	if not _village_built:
		_setup_village(level_root)
		_village_built = true
	
	if not _gave_starter_items:
		_give_starter_items(main)
		_gave_starter_items = true


func _setup_village(level_root: Node) -> void:
	# Shop entrance zone
	var entrance := _make_zone("ShopEntrance", Vector2(160, 120), Vector2(48, 32))
	entrance.body_entered.connect(_on_enter_shop_zone)
	level_root.add_child(entrance)
	
	# Shop sign
	var sign := Label.new()
	sign.name = "ShopSign"
	sign.position = Vector2(160, 96)
	sign.text = "~ Your Shop ~"
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_theme_font_size_override("font_size", 10)
	sign.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	level_root.add_child(sign)
	
	# Martha NPC
	var npc := CharacterBody2D.new()
	npc.name = "Martha"
	npc.position = Vector2(260, 140)
	npc.collision_layer = 0
	npc.collision_mask = 0
	npc.set_script(load("res://scripts/npc.gd"))
	var ns := Sprite2D.new()
	ns.scale = Vector2(2, 2)
	npc.add_child(ns)
	var nl := Label.new()
	nl.name = "NameLabel"
	nl.position = Vector2(-35, -30)
	nl.text = "Martha"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 10)
	npc.add_child(nl)
	level_root.add_child(npc)
	
	# Bakery sign
	var bs := Label.new()
	bs.position = Vector2(260, 108)
	bs.text = "~ Marthas Bakery ~"
	bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bs.add_theme_font_size_override("font_size", 10)
	bs.add_theme_color_override("font_color", Color(1, 0.7, 0.6))
	level_root.add_child(bs)
	
	print("[ShopSystem] Village setup complete")


func _find_player(main: Node) -> Node2D:
	return main.get_node_or_null("Player")


func _find_player_inventory(main: Node):
	var player: Node = _find_player(main)
	if not player:
		return null
	for child: Node in player.get_children():
		var sp: String = child.get_script().resource_path if child.get_script() else ""
		if sp == "res://scripts/inventory_component.gd":
			return child
	return null


func _give_starter_items(main: Node) -> void:
	var inv = _find_player_inventory(main)
	if not inv:
		return
	if inv.has_item("health_potion"):
		return  # Already given
	
	var ids: Array = [
		"health_potion", "health_potion", "health_potion",
		"bread", "bread",
		"tea_leaf", "tea_leaf",
		"slime_gel", "slime_gel", "slime_gel", "slime_gel", "slime_gel",
		"iron_sword",
	]
	for uid in ids:
		var item: Resource = load("res://resources/items/" + uid + ".tres")
		if item:
			inv.add_item(item, 1)
	print("[ShopSystem] Starter items given")


func _make_zone(name_str: String, pos: Vector2, size: Vector2) -> Area2D:
	var a := Area2D.new()
	a.name = name_str
	a.position = pos
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	a.add_child(cs)
	return a


#---------------------------------------------------------------------------------
# Shop room transitions
#---------------------------------------------------------------------------------

func _on_enter_shop_zone(body: Node2D) -> void:
	if _shop_active:
		return
	if not body.is_in_group("player"):
		return
	_enter_shop(body)


func _enter_shop(player: Node2D) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	_shop_active = true
	_shop_exit_position = player.global_position
	
	# Hide the level
	var level_root: Node = main.get_node_or_null("LevelRoot")
	if level_root:
		level_root.visible = false
	
	# Build shop room
	_shop_room = _build_shop_room()
	main.add_child(_shop_room)
	
	# Move player inside
	player.global_position = Vector2(96, 176)
	
	print("[ShopSystem] Entered shop")


func _exit_shop() -> void:
	_shop_active = false
	
	if _counter_active:
		_close_counter_view()
	
	if _shop_room:
		_shop_room.queue_free()
		_shop_room = null
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	var player: Node2D = _find_player(main) if main else null
	if player:
		player.global_position = _shop_exit_position
	
	if main:
		var level_root: Node = main.get_node_or_null("LevelRoot")
		if level_root:
			level_root.visible = true
	
	print("[ShopSystem] Exited shop")


func _build_shop_room() -> Node2D:
	var room := Node2D.new()
	room.name = "ShopRoom"
	var ts: int = 16
	var rw: int = 12
	var rh: int = 8
	
	# Floor — try to use generated texture, fall back to colored rects
	var floor_tex: Texture2D = load("res://assets/generated/shop_floor_tile.png")
	
	for x in range(rw):
		for y in range(rh):
			var fs := Sprite2D.new()
			fs.position = Vector2(x * ts, y * ts)
			if floor_tex:
				fs.texture = floor_tex
				fs.region_enabled = true
				fs.region_rect = Rect2(0, 0, ts, ts)
			else:
				var fi := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
				fi.fill(Color(0.35, 0.25, 0.15))
				fs.texture = ImageTexture.create_from_image(fi)
			room.add_child(fs)
	
	# Walls
	for x in range(rw + 2):
		room.add_child(_brick(Vector2((x - 1) * ts, -ts)))
		room.add_child(_brick(Vector2((x - 1) * ts, rh * ts)))
	for y in range(rh):
		room.add_child(_brick(Vector2(-ts, y * ts)))
		room.add_child(_brick(Vector2(rw * ts, y * ts)))
	
	# Doorway
	var dx: int = rw / 2
	var door := Sprite2D.new()
	door.position = Vector2(dx * ts, rh * ts)
	var di := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	di.fill(Color(0.5, 0.4, 0.2))
	door.texture = ImageTexture.create_from_image(di)
	room.add_child(door)
	
	# Counter with generated art
	var counter_tex: Texture2D = load("res://assets/generated/shop_counter_prop.png")
	var counter := Sprite2D.new()
	counter.name = "Counter"
	if counter_tex:
		counter.texture = counter_tex
		counter.scale = Vector2(1.5, 1.5)
	else:
		var ci := Image.create(96, 32, false, Image.FORMAT_RGBA8)
		ci.fill(Color(0.45, 0.28, 0.12))
		counter.texture = ImageTexture.create_from_image(ci)
		counter.scale = Vector2(1.5, 1.5)
	counter.position = Vector2(rw * ts / 2.0, rh * ts * 0.35)
	room.add_child(counter)
	
	# Tend zone
	var tz := Area2D.new()
	tz.name = "TendZone"
	tz.position = counter.position + Vector2(0, -24)
	var tcs := CollisionShape2D.new()
	var tr := RectangleShape2D.new()
	tr.size = Vector2(80, 40)
	tcs.shape = tr
	tz.add_child(tcs)
	tz.body_entered.connect(_on_tend_entered)
	tz.body_exited.connect(_on_tend_exited)
	room.add_child(tz)
	
	# Exit zone
	var ez := Area2D.new()
	ez.name = "ShopExitZone"
	ez.position = Vector2(dx * ts, rh * ts)
	var ecs := CollisionShape2D.new()
	var er := RectangleShape2D.new()
	er.size = Vector2(ts, ts)
	ecs.shape = er
	ez.add_child(ecs)
	ez.body_entered.connect(_on_shop_exit)
	room.add_child(ez)
	
	return room


func _brick(pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.position = pos
	var i := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	i.fill(Color(0.25, 0.2, 0.15))
	s.texture = ImageTexture.create_from_image(i)
	return s


#---------------------------------------------------------------------------------
# Tend zone callbacks
#---------------------------------------------------------------------------------

func _on_tend_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_tend_zone = true


func _on_tend_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_tend_zone = false


func _on_shop_exit(body: Node2D) -> void:
	if body.is_in_group("player") and _shop_active:
		_exit_shop()


#---------------------------------------------------------------------------------
# Counter view
#---------------------------------------------------------------------------------

func _open_counter_view() -> void:
	_counter_active = true
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	var inv = _find_player_inventory(main) if main else null
	
	var cv_script: Script = load("res://scripts/counter_view.gd")
	_counter_view = CanvasLayer.new()
	_counter_view.name = "CounterView"
	_counter_view.set_script(cv_script)
	get_tree().root.add_child(_counter_view)
	_counter_view.setup(inv)
	_counter_view.counter_closed.connect(_on_counter_closed)
	
	var player: Node = _find_player(main) if main else null
	if player:
		player.set_process(false)
		player.set_physics_process(false)
	
	print("[ShopSystem] Counter view opened")


func _close_counter_view() -> void:
	if _counter_view:
		_counter_view.queue_free()
		_counter_view = null
	_counter_active = false
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	var player: Node = _find_player(main) if main else null
	if player:
		player.set_process(true)
		player.set_physics_process(true)
	
	print("[ShopSystem] Counter view closed")


func _on_counter_closed() -> void:
	_close_counter_view()


#---------------------------------------------------------------------------------
# Input handling
#---------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _shop_active and _player_in_tend_zone and not _counter_active:
			_open_counter_view()
