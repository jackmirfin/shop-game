extends CharacterBody2D


const SPEED: float = 80.0

var last_direction: Vector2 = Vector2.RIGHT
var is_attacking: bool = false

var hitbox_offset: Vector2

var strength: int = 35


@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animated_sprite_bag: AnimatedSprite2D = $AnimatedSprite2D_Bag
@onready var swing_sword: AudioStreamPlayer2D = $SwingSword
@onready var hitbox: Area2D = $Hitbox
var health_component: Node

var inventory_locked: bool = true


func _ready() -> void:
	# Initialize hitbox offset
	hitbox_offset = hitbox.position

	# Ensure HealthComponent exists (create programmatically if missing from scene)
	if not has_node("HealthComponent"):
		_create_health_component()

	health_component = $HealthComponent

	# Connect HealthComponent signals
	health_component.died.connect(_on_player_died)
	health_component.health_changed.connect(_on_health_changed)

	# Inventory starts LOCKED — unlocked when bag is acquired
	inventory_locked = GameState.bag_equipped == false

	# If already equipped (saved game), restore bag state
	if GameState.bag_equipped:
		_apply_bag_visuals()

	# Register with the "player" group
	add_to_group("player")


func _create_health_component() -> void:
	var hc := Node.new()
	hc.name = "HealthComponent"
	hc.set_script(load("res://scripts/health_component.gd"))
	hc.set("max_health", 100)
	hc.set("current_health", 100)
	add_child(hc)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack") and not is_attacking:
		attack()

	# Skip movement if attacking
	if is_attacking:
		velocity = Vector2.ZERO
		# Keep hitbox active for the duration of the attack animation
		if not hitbox.monitoring:
			hitbox.monitoring = true
		return
	else:
		# Disable hitbox outside of attacks
		hitbox.monitoring = false

	process_movement()
	process_animation()
	move_and_slide()
	z_index = int(global_position.y)




#-------------------------------------------------------------------------------
#          Movement & Animation
#-------------------------------------------------------------------------------


func process_movement() -> void:
	var direction := Input.get_vector("left", "right", "up", "down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		last_direction = direction
		update_hitbox_offset()
	else:
		velocity = Vector2.ZERO


func process_animation() -> void:
	if is_attacking:
		return

	if velocity != Vector2.ZERO:
		play_animation("run", last_direction)
	else:
		play_animation("idle", last_direction)


func play_animation(prefix: String, dir: Vector2) -> void:
	var active_sprite: AnimatedSprite2D = _get_active_sprite()

	if dir.x != 0:
		active_sprite.flip_h = dir.x < 0
		if active_sprite.sprite_frames and active_sprite.sprite_frames.has_animation(prefix + "_right"):
			active_sprite.play(prefix + "_right")
		else:
			active_sprite.play("walk" if prefix == "run" else "idle")
	elif dir.y < 0:
		if active_sprite.sprite_frames and active_sprite.sprite_frames.has_animation(prefix + "_up"):
			active_sprite.play(prefix + "_up")
		else:
			active_sprite.play("walk" if prefix == "run" else "idle")
	elif dir.y > 0:
		if active_sprite.sprite_frames and active_sprite.sprite_frames.has_animation(prefix + "_down"):
			active_sprite.play(prefix + "_down")
		else:
			active_sprite.play("walk" if prefix == "run" else "idle")


func _get_active_sprite() -> AnimatedSprite2D:
	if GameState.bag_equipped and animated_sprite_bag:
		return animated_sprite_bag
	return animated_sprite_2d



#-------------------------------------------------------------------------------
#          Attacking
#-------------------------------------------------------------------------------


func attack() -> void:
	is_attacking = true
	hitbox.monitoring = true
	swing_sword.play()
	play_animation("attack", last_direction)
	GameState.player_current_attack = true


func _on_animated_sprite_2d_animation_finished() -> void:
	if is_attacking:
		is_attacking = false
		GameState.player_current_attack = false


#-------------------------------------------------------------------------------
#          Bag Equipment (Inventory Unlock + Sprite Swap)
#-------------------------------------------------------------------------------


func equip_bag() -> void:
	"""Called when the player picks up the Adventurer's Bag.
	Unlocks inventory and swaps to the bag-equipped sprite."""
	if GameState.bag_equipped:
		return

	GameState.bag_equipped = true
	GameState.inventory_unlocked = true
	inventory_locked = false

	# Create inventory now that it's unlocked
	_setup_inventory()

	# Give shop keys if the player has them from the letter
	if GameState.has_shop_keys:
		var keys_item: ItemData = load("res://resources/items/shop_keys.tres") as ItemData
		if keys_item and has_node("Inventory"):
			var inv: InventoryComponent = $Inventory as InventoryComponent
			inv.add_item(keys_item, 1)

	# Swap visuals
	_apply_bag_visuals()

	# Emit event
	EventBus.bag_acquired.emit()

	print("Bag equipped! Inventory unlocked. New horizons await.")


func _apply_bag_visuals() -> void:
	"""Swap to the bag-equipped sprite."""
	if animated_sprite_2d:
		animated_sprite_2d.visible = false
	if animated_sprite_bag:
		animated_sprite_bag.visible = true


#-------------------------------------------------------------------------------
#          Hitbox
#-------------------------------------------------------------------------------

func update_hitbox_offset() -> void:
	var x := hitbox_offset.x
	var y := hitbox_offset.y

	match last_direction:
		Vector2.LEFT:
			hitbox.position = Vector2(-x, y)
		Vector2.RIGHT:
			hitbox.position = Vector2(x, y)
		Vector2.UP:
			hitbox.position = Vector2(y + 3.5, -x - 2)
		Vector2.DOWN:
			hitbox.position = Vector2(-y - 2, x - 8)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if not is_attacking:
		return
	# Check if the body is in the "enemy" group
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(strength, position)
		EventBus.player_attacked.emit(body)


#-------------------------------------------------------------------------------
#          Interaction & Input
#-------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_node("/root/EventBus").interact_pressed.emit()
	if event.is_action_pressed("drink_tea") and GameState.tea_unlocked:
		WorldStateManager.toggle_tea()


#-------------------------------------------------------------------------------
#          Inventory
#-------------------------------------------------------------------------------

func _setup_inventory() -> void:
	if has_node("Inventory"):
		return
	var inv := Node.new()
	inv.name = "Inventory"
	inv.set_script(load("res://scripts/inventory_component.gd"))
	inv.set("max_slots", 20)
	inv.set("owner_id", "player")
	add_child(inv)


#-------------------------------------------------------------------------------
#          Health
#-------------------------------------------------------------------------------

func take_damage(amount: int, attacker_position: Vector2 = Vector2.ZERO) -> void:
	if health_component:
		health_component.take_damage(amount, attacker_position)


func _on_player_died() -> void:
	EventBus.player_died.emit()
	# TODO: death screen / respawn
	print("Player died!")


func _on_health_changed(current: int, max_hp: int) -> void:
	EventBus.player_damaged.emit(max_hp - current, current, max_hp)
