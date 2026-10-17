extends Node

var _started: bool = false
var _gave_items: bool = false
var _shop_room: Node2D = null
var _shop_active: bool = false
var _shop_exit: Vector2 = Vector2.ZERO
var _in_tend: bool = false
var _cv: CanvasLayer = null
var _cv_active: bool = false

func _ready() -> void:
	call_deferred('_late_init')

func _late_init() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var m: Node = get_tree().root.get_node_or_null('Main')
	if not m:
		return
	var lr: Node = m.get_node_or_null('LevelRoot')
	if not lr or lr.get_child_count() == 0:
		await get_tree().process_frame
		lr = m.get_node_or_null('LevelRoot')
		if not lr:
			return
	_setup_village(lr, m)
	_started = true

func _setup_village(lr: Node, m: Node) -> void:
	var e := Area2D.new()
	e.name = 'ShopEntrance'
	e.position = Vector2(160, 120)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(48, 32)
	cs.shape = r
	e.add_child(cs)
	e.body_entered.connect(func(b): if b.is_in_group('player') and not _shop_active: _enter(b))
	lr.add_child(e)
	var s := Label.new()
	s.position = Vector2(160, 96)
	s.text = '~ Your Shop ~'
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override('font_size', 10)
	s.add_theme_color_override('font_color', Color(1, 0.9, 0.4))
	lr.add_child(s)
	# Tea World husks in the village
	var husk_script: Script = load("res://scripts/tea_world_husk.gd")
	var husk_positions: Array[Vector2] = [Vector2(220, 80), Vector2(300, 180), Vector2(100, 240)]
	for hp in husk_positions:
		var h := Node2D.new()
		h.name = "VillageHusk"
		h.set_script(husk_script)
		h.position = hp
		lr.add_child(h)

	if not _gave_items:
		var p: Node = m.get_node_or_null('Player')
		if p:
			var inv = null
			for c in p.get_children():
				if c.get_script() and c.get_script().resource_path == 'res://scripts/inventory_component.gd':
					inv = c
					break
			if inv and not inv.has_item('health_potion'):
				for uid in ['health_potion','health_potion','health_potion','bread','bread','tea_leaf','tea_leaf','slime_gel','slime_gel','slime_gel','slime_gel','slime_gel','iron_sword']:
					var it: Resource = load('res://resources/items/' + uid + '.tres')
					if it:
						inv.add_item(it, 1)
				_gave_items = true

func _enter(p: Node2D) -> void:
	_shop_active = true
	_shop_exit = p.global_position
	var m: Node = get_tree().root.get_node_or_null('Main')
	var lr: Node = m.get_node_or_null('LevelRoot') if m else null
	if lr:
		lr.visible = false
	_shop_room = _build_room()
	m.add_child(_shop_room)
	p.global_position = Vector2(96, 176)

func _exit_shop() -> void:
	_shop_active = false
	if _cv_active:
		_close_cv()
	if _shop_room:
		_shop_room.queue_free()
		_shop_room = null
	var m: Node = get_tree().root.get_node_or_null('Main')
	if m:
		var p: Node = m.get_node_or_null('Player')
		if p:
			p.global_position = _shop_exit
		var lr: Node = m.get_node_or_null('LevelRoot')
		if lr:
			lr.visible = true

func _build_room() -> Node2D:
	var room := Node2D.new()
	var ts: int = 16
	var rw: int = 12
	var rh: int = 8
	for x in range(rw):
		for y in range(rh):
			var fs := Sprite2D.new()
			fs.position = Vector2(x * ts, y * ts)
			var fi := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
			fi.fill(Color(0.35, 0.25, 0.15))
			fs.texture = ImageTexture.create_from_image(fi)
			room.add_child(fs)
	for x in range(rw + 2):
		room.add_child(_wall(Vector2((x - 1) * ts, -ts)))
		room.add_child(_wall(Vector2((x - 1) * ts, rh * ts)))
	for y in range(rh):
		room.add_child(_wall(Vector2(-ts, y * ts)))
		room.add_child(_wall(Vector2(rw * ts, y * ts)))
	@warning_ignore("integer_division")
	var dx: int = rw / 2
	var door_sprite := Sprite2D.new()
	door_sprite.position = Vector2(dx * ts, rh * ts)
	var di := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	di.fill(Color(0.5, 0.4, 0.2))
	door_sprite.texture = ImageTexture.create_from_image(di)
	room.add_child(door_sprite)
	var cnt := Sprite2D.new()
	cnt.name = 'Counter'
	var ci := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	ci.fill(Color(0.45, 0.28, 0.12))
	cnt.texture = ImageTexture.create_from_image(ci)
	cnt.scale = Vector2(1.5, 1.5)
	cnt.position = Vector2(rw * ts / 2.0, rh * ts * 0.35)
	room.add_child(cnt)
	var tz := Area2D.new()
	tz.position = cnt.position + Vector2(0, -24)
	var tzcs := CollisionShape2D.new()
	var tzr := RectangleShape2D.new()
	tzr.size = Vector2(80, 40)
	tzcs.shape = tzr
	tz.add_child(tzcs)
	tz.body_entered.connect(func(b): if b.is_in_group('player'): _in_tend = true)
	tz.body_exited.connect(func(b): if b.is_in_group('player'): _in_tend = false)
	room.add_child(tz)
	var ez := Area2D.new()
	ez.position = Vector2(dx * ts, rh * ts)
	var ezcs := CollisionShape2D.new()
	var ezr := RectangleShape2D.new()
	ezr.size = Vector2(ts, ts)
	ezcs.shape = ezr
	ez.add_child(ezcs)
	ez.body_entered.connect(func(b): if b.is_in_group('player') and _shop_active: _exit_shop())
	room.add_child(ez)
	
	# Hidden basement door — only visible in Tea World
	var bdoor_script: Script = load("res://scripts/tea_world_door.gd")
	var basement_door := Node.new()
	basement_door.name = "BasementDoor"
	basement_door.set_script(bdoor_script)
	basement_door.set("door_label", "???")
	basement_door.set("door_width", 32.0)
	basement_door.set("door_height", 48.0)
	basement_door.position = Vector2(16, rh * ts * 0.5)
	if basement_door.has_signal("door_entered"):
		basement_door.door_entered.connect(_on_basement_entered)
	room.add_child(basement_door)
	
	# Husk watcher in corner of shop
	var husk_script: Script = load("res://scripts/tea_world_husk.gd")
	var husk := Node.new()
	husk.name = "ShopHusk"
	husk.set_script(husk_script)
	husk.position = Vector2(rw * ts - 24, rh * ts * 0.7)
	room.add_child(husk)
	
	return room

func _wall(pos: Vector2) -> Sprite2D:
	var sw := Sprite2D.new()
	sw.position = pos
	var i := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	i.fill(Color(0.25, 0.2, 0.15))
	sw.texture = ImageTexture.create_from_image(i)
	return sw

func _on_basement_entered() -> void:
	if _cv_active:
		_close_cv()
	var p: Node = get_tree().root.get_node_or_null("Main/Player")
	if p:
		p.set_process(false)
		p.set_physics_process(false)
	
	var fade := ColorRect.new()
	fade.name = "BasementFade"
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	get_tree().root.add_child(fade)
	var tw1: Tween = create_tween()
	tw1.tween_property(fade, "modulate:a", 1.0, 1.5)
	await tw1.finished
	
	var tl := CanvasLayer.new()
	tl.name = "BasementTextLayer"
	tl.layer = 50
	get_tree().root.add_child(tl)
	var txt := Label.new()
	txt.name = "BasementText"
	txt.set_anchors_preset(Control.PRESET_CENTER)
	txt.text = "You descend into the basement...
the air is thick and cold.

In the darkness, shelves lined with forgotten
a journal, a rusted key, a sealed jar.

Something watches from the corner.
You do not turn to look."
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_size_override("font_size", 14)
	txt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.modulate.a = 0.0
	tl.add_child(txt)
	
	var tw2: Tween = create_tween()
	tw2.tween_property(txt, "modulate:a", 1.0, 1.0)
	await tw2.finished
	await get_tree().create_timer(3.5).timeout
	
	var tw3: Tween = create_tween()
	tw3.tween_property(txt, "modulate:a", 0.0, 0.5)
	tw3.parallel().tween_property(fade, "modulate:a", 0.0, 0.5)
	await tw3.finished
	
	tl.queue_free()
	fade.queue_free()
	
	if p:
		p.set_process(true)
		p.set_physics_process(true)
	var gs: Node = get_node("/root/GameState")
	gs.add_gold(50)

func _open_cv() -> void:
	_cv_active = true
	var m: Node = get_tree().root.get_node_or_null('Main')
	var inv = null
	if m:
		var p: Node = m.get_node_or_null('Player')
		if p:
			for c in p.get_children():
				if c.get_script() and c.get_script().resource_path == 'res://scripts/inventory_component.gd':
					inv = c
					break
			p.set_process(false)
			p.set_physics_process(false)
	_cv = CanvasLayer.new()
	_cv.name = 'CounterView'
	_cv.set_script(load('res://scripts/counter_view.gd'))
	get_tree().root.add_child(_cv)
	_cv.setup(inv)
	_cv.counter_closed.connect(func(): _close_cv())

func _close_cv() -> void:
	if _cv:
		_cv.queue_free()
		_cv = null
	_cv_active = false
	var m: Node = get_tree().root.get_node_or_null('Main')
	if m:
		var p: Node = m.get_node_or_null('Player')
		if p:
			p.set_process(true)
			p.set_physics_process(true)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed('interact') and _shop_active and _in_tend and not _cv_active:
		_open_cv()
