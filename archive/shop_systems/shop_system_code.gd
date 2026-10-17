# ShopSystemCode — invoked by WorldStateManager at runtime.
# All shop logic lives here, called from an existing autoload context.

static var _village_built: bool = false
static var _gave_starter_items: bool = false
static var _shop_room: Node2D = null
static var _shop_active: bool = false
static var _shop_exit_position: Vector2 = Vector2.ZERO
static var _player_in_tend_zone: bool = false
static var _counter_view: CanvasLayer = null
static var _counter_active: bool = false


static func setup(main: Node, level_root: Node) -> void:
	if not _village_built:
		_build_village(level_root)
		_village_built = true
	if not _gave_starter_items:
		_give_starter_items(main)
		_gave_starter_items = true


static func _build_village(level_root: Node) -> void:
	var entrance := _make_zone("ShopEntrance", Vector2(160, 120), Vector2(48, 32))
	entrance.body_entered.connect(_on_enter_shop_zone)
	level_root.add_child(entrance)
	
	var sign := Label.new()
	sign.name = "ShopSign"
	sign.position = Vector2(160, 96)
	sign.text = "~ Your Shop ~"
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_theme_font_size_override("font_size", 10)
	sign.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	level_root.add_child(sign)
	
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
	
	var bs := Label.new()
	bs.position = Vector2(260, 108)
	bs.text = "~ Marthas Bakery ~"
	bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bs.add_theme_font_size_override("font_size", 10)
	bs.add_theme_color_override("font_color", Color(1, 0.7, 0.6))
	level_root.add_child(bs)


static func _give_starter_items(main: Node) -> void:
	var player: Node = main.get_node_or_null("Player")
	if not player:
		return
	var inv = null
	for child: Node in player.get_children():
		var sp: String = child.get_script().resource_path if child.get_script() else ""
		if sp == "res://scripts/inventory_component.gd":
			inv = child
			break
	if not inv or inv.has_item("health_potion"):
		return
	var ids: Array = ["health_potion","health_potion","health_potion","bread","bread","tea_leaf","tea_leaf","slime_gel","slime_gel","slime_gel","slime_gel","slime_gel","iron_sword"]
	for uid in ids:
		var item: Resource = load("res://resources/items/" + uid + ".tres")
		if item:
			inv.add_item(item, 1)


static func _make_zone(nm: String, pos: Vector2, size: Vector2) -> Area2D:
	var a := Area2D.new()
	a.name = nm
	a.position = pos
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	a.add_child(cs)
	return a


static func _on_enter_shop_zone(body: Node2D) -> void:
	if _shop_active:
		return
	if not body.is_in_group("player"):
		return
	_enter_shop(body)


static func _enter_shop(player: Node2D) -> void:
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return
	_shop_active = true
	_shop_exit_position = player.global_position
	var level_root: Node = main.get_node_or_null("LevelRoot")
	if level_root:
		level_root.visible = false
	_shop_room = _build_shop_room()
	main.add_child(_shop_room)
	player.global_position = Vector2(96, 176)


static func _exit_shop() -> void:
	_shop_active = false
	if _counter_active:
		_close_counter_view()
	if _shop_room:
		_shop_room.queue_free()
		_shop_room = null
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if main:
		var player: Node = main.get_node_or_null("Player")
		if player:
			player.global_position = _shop_exit_position
		var level_root: Node = main.get_node_or_null("LevelRoot")
		if level_root:
			level_root.visible = true


static func _build_shop_room() -> Node2D:
	var room := Node2D.new()
	room.name = "ShopRoom"
	var ts: int = 16
	var rw: int = 12
	var rh: int = 8
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
	for x in range(rw + 2):
		room.add_child(_brick(Vector2((x - 1) * ts, -ts)))
		room.add_child(_brick(Vector2((x - 1) * ts, rh * ts)))
	for y in range(rh):
		room.add_child(_brick(Vector2(-ts, y * ts)))
		room.add_child(_brick(Vector2(rw * ts, y * ts)))
	var dx: int = rw / 2
	var door := Sprite2D.new()
	door.position = Vector2(dx * ts, rh * ts)
	var di := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	di.fill(Color(0.5, 0.4, 0.2))
	door.texture = ImageTexture.create_from_image(di)
	room.add_child(door)
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


static func _brick(pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.position = pos
	var i := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	i.fill(Color(0.25, 0.2, 0.15))
	s.texture = ImageTexture.create_from_image(i)
	return s


static func _on_tend_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_tend_zone = true


static func _on_tend_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_tend_zone = false


static func _on_shop_exit(body: Node2D) -> void:
	if body.is_in_group("player") and _shop_active:
		_exit_shop()


static func _open_counter_view() -> void:
	_counter_active = true
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	var inv = null
	if main:
		var player: Node = main.get_node_or_null("Player")
		if player:
			for child: Node in player.get_children():
				var sp: String = child.get_script().resource_path if child.get_script() else ""
				if sp == "res://scripts/inventory_component.gd":
					inv = child
					break
	var cv := load("res://scripts/counter_view.gd").new()
	_counter_view = cv
	Engine.get_main_loop().root.add_child(_counter_view)
	_counter_view.setup(inv)
	_counter_view.counter_closed.connect(_on_counter_closed)
	if main:
		var player: Node = main.get_node_or_null("Player")
		if player:
			player.set_process(false)
			player.set_physics_process(false)


static func _close_counter_view() -> void:
	if _counter_view:
		_counter_view.queue_free()
		_counter_view = null
	_counter_active = false
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if main:
		var player: Node = main.get_node_or_null("Player")
		if player:
			player.set_process(true)
			player.set_physics_process(true)


static func _on_counter_closed() -> void:
	_close_counter_view()


static func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _shop_active and _player_in_tend_zone and not _counter_active:
			_open_counter_view()
