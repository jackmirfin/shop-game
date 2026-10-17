extends Node
## EncounterManager (autoload) — connects the overworld level to the combat prototype.
##
## The level is NEVER reloaded. Combat is instantiated into a CanvasLayer that sits
## above the running level, so the overworld stays loaded with its camera, object
## state and player position intact; it is merely frozen for the duration.
##
## Freeze strategy: get_tree().paused is deliberately NOT used. The combat scene
## drives its animations with SceneTreeTimers and Tweens, which would have to opt
## out of pause one by one (and editing them is out of scope, so pausing could
## break them). Instead the LEVEL node is set to PROCESS_MODE_DISABLED — which also
## silences its _unhandled_input, so no overworld input leaks through — while this
## manager and the encounter overlay run with PROCESS_MODE_ALWAYS.
##
## Encounter flow:
##   overworld spider attacks and lands its strike
##   -> request_encounter()     suspend level, raise combat overlay
##   -> combat plays out        (unchanged prototype)
##   -> combat_finished(VICTORY) run the overworld finisher on the same level
##   -> remove that spider, restore player control
##
## Defeat also plays out in the overworld: the combat screen closes, the winning
## enemy strikes the player, and the player falls with its 'dying' animation. When
## the active level contains Erdon, he rescues the player and the encounter ends
## safely; levels without Erdon retain the terminal defeated fallback.

enum State { IDLE, IN_COMBAT, RESOLVING_VICTORY, RESOLVING_DEFEAT, PLAYER_DEFEATED }

## Mirrors CombatResult in scripts/combat_test.gd (VICTORY = 0, DEFEAT = 1).
const RESULT_VICTORY: int = 0
const RESULT_DEFEAT: int = 1
const RESULT_RESCUED: int = 2

const COMBAT_SCENE: String = "res://combat_test.tscn"
## Above InteractionUI (layer 40), so combat covers the whole screen.
const OVERLAY_LAYER: int = 50
## Short global cooldown after an encounter resolves, so a second nearby enemy
## cannot immediately trigger another battle.
const COOLDOWN_AFTER_ENCOUNTER: float = 0.75
const FADE_OUT_TIME: float = 0.18
## Frame at which the player's attack visually connects. Measured from
## player.png: all three attack directions peak (furthest reach and most opaque
## pixels) on frame 1. The spider's death starts on this frame.
const PLAYER_ATTACK_IMPACT_FRAME: int = 1
## How long the spider's final death frame is held before it is removed.
const DEATH_HOLD: float = 0.22
## Grace time added to an animation's own length before a wait gives up, so a
## missing or interrupted animation can never leave player input locked.
const SIGNAL_GRACE: float = 0.6
## Erdon is present in forest.tscn as the named rescue NPC. A defeat against the
## bear is recoverable when that NPC is available in the active level.
const ERDON_RESCUE_TIME: float = 0.55
const CUTSCENE_NPC_SPEED: float = 65.0
const CUTSCENE_PLAYER_SPEED: float = 100.0
const ERDON_RECOVERY_HP: int = 1
## Minimum whole-pixel gap the finisher keeps between player and spider.
const MIN_FINISHER_SEPARATION: float = 14.0

var _state: State = State.IDLE
var _cooldown: float = 0.0
## The exact overworld spider that started the current encounter.
var _spider: Node2D = null
## All enemies participating in the current room encounter, including the initiator.
var _encounter_group: Array[Node2D] = []
var _player: Node2D = null
var _combat: Node = null
var _overlay: CanvasLayer = null
var _layer_root: Control = null
var _dialogue_locked_player: Node2D = null
var _rescue_dialogue_stage: int = 0
var _namura_exit: Area2D = null
var _blacksmith_intro_active: bool = false
var _blacksmith: Node2D = null
var _reward_overlay: CardRewardOverlay = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	if not EventBus.dialogue_ended.is_connected(_on_rescue_dialogue_ended):
		EventBus.dialogue_ended.connect(_on_rescue_dialogue_ended)


func _on_rescue_dialogue_ended(_npc_name: String) -> void:
	if _blacksmith_intro_active:
		_blacksmith_intro_active = false
		await _blacksmith_leaves()
		_start_inventory_tutorial()
		return
	if _rescue_dialogue_stage == 0 and is_instance_valid(_dialogue_locked_player):
		_rescue_dialogue_stage = 1
		await _escort_to_namura_entrance()
		_start_namura_arrival_dialogue()
		return
	if _rescue_dialogue_stage == 1 and is_instance_valid(_dialogue_locked_player):
		_rescue_dialogue_stage = 2
		_start_village_entrance_dialogue()
		return
	if _rescue_dialogue_stage == 2 and is_instance_valid(_dialogue_locked_player):
		_rescue_dialogue_stage = 3
		await _walk_forest_exit_to_namura()
		await _take_player_to_namura_shop()
		_start_holt_shop_dialogue()
		return
	if _rescue_dialogue_stage == 3 and is_instance_valid(_dialogue_locked_player):
		_rescue_dialogue_stage = 4
		await _holt_leaves_namura()
	if is_instance_valid(_dialogue_locked_player):
		if _dialogue_locked_player.has_method("set_control_enabled"):
			_dialogue_locked_player.set_control_enabled(true)
		_dialogue_locked_player.set_physics_process(true)
	if is_instance_valid(_namura_exit):
		_namura_exit.set_deferred("monitoring", true)
	_namura_exit = null
	_dialogue_locked_player = null
	_rescue_dialogue_stage = 0


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


# --- Shop departure blacksmith sequence -----------------------------------------

## Starts once when the player leaves the shop interior for Namura.
func start_blacksmith_intro(player: Node2D) -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or bool(state.get("blacksmith_intro_done")):
		return
	if player == null or not get_tree().current_scene.scene_file_path.contains("namura"):
		return
	state.set("blacksmith_intro_done", true)
	_blacksmith_intro_active = true
	_dialogue_locked_player = player
	_player = player
	_set_player_control(false)
	var authored_blacksmith: Node2D = get_tree().current_scene.find_child("Blacksmith", true, false) as Node2D
	if authored_blacksmith == null:
		push_warning("EncounterManager: Blacksmith NPC is missing from Namura.")
		_blacksmith_intro_active = false
		_set_player_control(true)
		return
	var blacksmith_parent: Node = authored_blacksmith.get_parent()
	var blacksmith_spawn: Vector2 = authored_blacksmith.global_position
	authored_blacksmith.free()
	var blacksmith_scene: PackedScene = load("res://scenes/NPCs/Blacksmith_NPC.tscn") as PackedScene
	_blacksmith = blacksmith_scene.instantiate() as Node2D if blacksmith_scene != null else null
	if _blacksmith == null:
		push_warning("EncounterManager: Blacksmith_NPC.tscn could not be loaded.")
		_blacksmith_intro_active = false
		_set_player_control(true)
		return
	_blacksmith.name = "Blacksmith"
	blacksmith_parent.add_child(_blacksmith)
	_blacksmith.global_position = blacksmith_spawn
	_blacksmith.visible = true
	_blacksmith.set_physics_process(false)
	var sprite: AnimatedSprite2D = _blacksmith.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var target: Vector2 = player.global_position + Vector2(0.0, 32.0)
	var delta: Vector2 = target - _blacksmith.global_position
	_play_cutscene_walk(sprite, delta, false)
	var approach: Tween = create_tween()
	approach.tween_property(_blacksmith, "global_position", target,
		maxf(0.25, delta.length() / CUTSCENE_NPC_SPEED))
	await approach.finished
	if not is_instance_valid(_blacksmith) or not is_instance_valid(player):
		return
	if _blacksmith.has_method("_face"):
		_blacksmith.call("_face", "up")
	else:
		_blacksmith.look_at(player.global_position)
	_start_blacksmith_dialogue()


func _start_blacksmith_dialogue() -> void:
	var lines: Array[DialogueLineData] = []
	for id: int in range(1, 13):
		var line: DialogueLineData = load("res://resources/dialogue/blacksmith_%d.tres" % id) as DialogueLineData
		if line == null:
			push_warning("EncounterManager: missing blacksmith dialogue line %d." % id)
			return
		lines.append(line)
	DialogueManager.start(lines, "blacksmith_1")
	_grant_blacksmith_rewards()


func _grant_blacksmith_rewards() -> void:
	var sword: InventoryItem = InventoryItem.make_sword("aquamarine", 4)
	var shield: InventoryItem = InventoryItem.make("Reinforced Wooden Shield",
		"res://assets/Inventory/Items/reinforcedwoodenshield.png", InventoryItem.Kind.SHIELD, 1,
		false, "A reinforced wooden shield. Its cards grant 5 Block.")
	Inventory.add_item(sword)
	Inventory.add_item(shield)


func _blacksmith_leaves() -> void:
	if not is_instance_valid(_blacksmith):
		return
	_blacksmith.set_physics_process(false)
	var sprite: AnimatedSprite2D = _blacksmith.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var target: Vector2 = Vector2(456.0, 627.0)
	var delta: Vector2 = target - _blacksmith.global_position
	_play_cutscene_walk(sprite, delta, false)
	var leave: Tween = create_tween()
	leave.tween_property(_blacksmith, "global_position", target,
		maxf(0.35, delta.length() / CUTSCENE_NPC_SPEED))
	await leave.finished
	_blacksmith.visible = false
	_blacksmith = null


func _start_inventory_tutorial() -> void:
	DialogueManager.show_system_message(
		"Press I to open your inventory, then press E to continue.", 430.0,
		Callable(self, "_tutorial_open_deck_prompt"), 2.5)


func _tutorial_open_deck_prompt() -> void:
	var inventory_ui: Node = get_node_or_null("/root/InventoryUI")
	if inventory_ui != null and inventory_ui.has_method("toggle") and \
			not bool(inventory_ui.get("visible")):
		inventory_ui.call("toggle")
	DialogueManager.show_system_message(
		"Press E to open the Deck Manager.", 430.0,
		Callable(self, "_tutorial_show_deck_help"), 2.5)


func _tutorial_show_deck_help() -> void:
	var inventory_ui: Node = get_node_or_null("/root/InventoryUI")
	if inventory_ui != null and inventory_ui.has_method("set_deck_mode"):
		inventory_ui.call("set_deck_mode", true)
	DialogueManager.show_system_message(
		"Hover over an item to see its cards. Drag the new sword and shield cards into or out of your deck. Press I when you are finished.",
		330.0, Callable(self, "_finish_inventory_tutorial"), 2.5)


func _finish_inventory_tutorial() -> void:
	if is_instance_valid(_dialogue_locked_player):
		_set_player_control(true)
	_dialogue_locked_player = null
	_player = null


# --- Public API (used by WorldSpider) ---

## True when a brand new encounter may begin: nothing running, no cooldown.
func can_start_encounter() -> bool:
	return _state == State.IDLE and _cooldown <= 0.0


func is_busy() -> bool:
	return not can_start_encounter()


## Starts combat against the given overworld enemy. Returns false when refused,
## so the caller (the spider) knows to go back to roaming.
func request_encounter(spider: Node2D) -> bool:
	if not can_start_encounter():
		return false
	if not is_instance_valid(spider) or spider.is_queued_for_deletion():
		return false
	var player: Node2D = _find_player()
	if player == null:
		push_warning("EncounterManager: no node in group 'player'; encounter refused.")
		return false
	if not ResourceLoader.exists(COMBAT_SCENE):
		push_error("EncounterManager: combat scene %s is missing; encounter refused." % COMBAT_SCENE)
		return false

	_spider = spider
	_player = player
	_encounter_group.clear()
	_encounter_group.append(spider)
	# Dungeon rooms keep their encounter enemies under one room wrapper. Collect the
	# matching family before disabling the level so one contact starts the whole fight.
	var room: Node = spider.get_parent()
	var room_id: Variant = spider.get("dungeon_room_id")
	if room != null and room_id != null:
		for child: Node in room.get_children():
			var candidate: Node2D = child as Node2D
			if candidate == null or candidate == spider or not candidate.has_method("combat_config"):
				continue
			if candidate.get("dungeon_room_id") == room_id \
					and candidate.get_script() == spider.get_script():
				_encounter_group.append(candidate)
	_state = State.IN_COMBAT

	# Lock the encounter so it cannot trigger twice, and stop both bodies.
	_set_player_control(false)
	_set_level_processing(false)

	if not _build_overlay():
		# Could not raise combat: release everything and let the spider roam on.
		_release_after_failure()
		return false
	return true


# --- Combat result ---

func _on_combat_finished(result: int) -> void:
	if result == RESULT_RESCUED:
		_resolve_rescue()
	elif result == RESULT_VICTORY:
		_resolve_victory()
	else:
		_resolve_defeat()


## The overworld finisher. Runs entirely on the live level after combat closes:
## the player faces the spider, strikes, the strike connects, the spider dies,
## and only then is control given back.
func _resolve_victory() -> void:
	_state = State.RESOLVING_VICTORY
	var spider: Node2D = _spider if is_instance_valid(_spider) else null
	var player: Node2D = _player if is_instance_valid(_player) else null
	var is_cave_dungeon: bool = spider != null and spider.get("dungeon_room_id") != null
	if spider == null or player == null:
		push_warning("EncounterManager: encounter participants are gone; skipping the finisher.")
		await _close_combat()
		_finish_encounter()
		return
	if _is_bear_encounter(spider):
		await _resolve_bear_victory(spider, player)
		return

	# Stop both bodies and disable the spider's body + encounter collision BEFORE
	# the overworld becomes visible, so it cannot be walked into or re-trigger.
	for member: Node2D in _encounter_group:
		if is_instance_valid(member) and member.has_method("freeze_for_finisher"):
			member.freeze_for_finisher()

	# Let the level process again so the player's sprites can animate, but keep
	# player control off — input returns only at the very end of the sequence.
	_set_level_processing(true)
	_set_player_control(false)
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO

	# Fade the combat screen away to reveal the unchanged overworld.
	await _close_combat()
	if not is_instance_valid(spider) or not is_instance_valid(player):
		push_warning("EncounterManager: participants left during the finisher; cleaning up.")
		if is_instance_valid(spider):
			_retire_spider(spider)
		_finish_encounter()
		return

	# Face the spider and make sure the two sprites are readable side by side.
	if player.has_method("face_towards"):
		player.face_towards(spider.global_position)
	_separate_whole_pixels(player, spider)

	# Play the player's attack toward the spider. The spider's death starts on the
	# player's actual impact frame, detected via AnimatedSprite2D.frame_changed.
	var attack_anim: String = "attack_down"
	if player.has_method("play_attack_towards"):
		attack_anim = String(player.play_attack_towards(spider.global_position))
	else:
		push_warning("EncounterManager: player has no attack API; skipping the strike.")
	var attack_len: float = _animation_length(player.animated_sprite, StringName(attack_anim))

	var impact: bool = await _await_frame(player.animated_sprite, PLAYER_ATTACK_IMPACT_FRAME, attack_len + SIGNAL_GRACE)
	if not impact:
		push_warning("EncounterManager: player impact frame was never reached ('%s'); using the safe cleanup path." % attack_anim)

	var death_started: bool = false
	if is_instance_valid(spider):
		var death_anim: StringName = &""
		if spider.has_method("play_death"):
			death_anim = spider.play_death()
		else:
			push_warning("EncounterManager: spider has no death animation API.")
		if death_anim != StringName():
			death_started = true
			var death_len: float = _animation_length(spider.animation_sprite() if spider.has_method("animation_sprite") else null, death_anim)
			# Let the player's own attack finish (step 9 of the sequence).
			await _await_animation_end(player.animated_sprite, attack_len + SIGNAL_GRACE)
			# Then let the spider's complete death animation finish.
			if is_instance_valid(spider):
				await _await_animation_end(spider.animation_sprite(), death_len + SIGNAL_GRACE)
				await _wait(DEATH_HOLD)

	if not death_started and is_instance_valid(player):
		# No death animation: still let the strike finish before cleanup.
		await _await_animation_end(player.animated_sprite, attack_len + SIGNAL_GRACE)
	elif not death_started:
		push_warning("EncounterManager: spider death animation unavailable; removing it directly.")

	# Remove the spider that started this encounter. Victory leaves it in the world
	# as a corpse on its final death frame rather than deleting it.
	_retire_spider(spider)
	for member: Node2D in _encounter_group:
		if is_instance_valid(member) and member != spider:
			_retire_spider(member)
	# Restore the player's normal idle facing and hand control back.
	if is_instance_valid(player):
		if player.has_method("restore_idle"):
			player.restore_idle()
	_finish_encounter()
	if is_cave_dungeon:
		_show_card_reward()


func _is_bear_encounter(enemy: Node2D) -> bool:
	if enemy == null or not enemy.has_method("combat_config"):
		return false
	var config: Dictionary = enemy.combat_config()
	return str(config.get("enemy_type", "")) == "bear"


func _resolve_bear_victory(bear: Node2D, player: Node2D) -> void:
	if bear.has_method("freeze_for_finisher"):
		bear.freeze_for_finisher()
	_set_level_processing(true)
	_set_player_control(false)
	player.velocity = Vector2.ZERO
	await _close_combat()
	if not is_instance_valid(bear) or not is_instance_valid(player):
		_finish_encounter()
		return
	var death_name: StringName = bear.play_death() if bear.has_method("play_death") else &""
	if death_name != StringName() and bear.has_method("animation_sprite"):
		var bear_sprite: AnimatedSprite2D = bear.animation_sprite()
		await _await_animation_end(bear_sprite, _animation_length(bear_sprite, death_name) + SIGNAL_GRACE)
		await _wait(DEATH_HOLD)
	var bear_position: Vector2 = bear.global_position
	_retire_spider(bear)
	var erdon: Node2D = _find_erdon()
	if erdon == null:
		_finish_encounter()
		return
	await _erdon_appears_after_bear(erdon, bear_position, player)
	_dialogue_locked_player = player
	_rescue_dialogue_stage = 0
	_finish_encounter()
	if is_instance_valid(_dialogue_locked_player) and _dialogue_locked_player.has_method("set_control_enabled"):
		_dialogue_locked_player.set_control_enabled(false)
	_start_erdon_rescue_dialogue()


func _erdon_appears_after_bear(erdon: Node2D, bear_position: Vector2, player: Node2D) -> void:
	if erdon.has_method("set_collision_enabled"):
		erdon.set_collision_enabled(false)
	erdon.set_physics_process(false)
	var target_position: Vector2 = (bear_position + Vector2(42.0, 0.0)).round()
	var erdon_sprite: AnimatedSprite2D = erdon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if erdon_sprite == null or erdon_sprite.sprite_frames == null:
		return
	var delta: Vector2 = target_position - erdon.global_position
	_play_cutscene_walk(erdon_sprite, delta, false)
	var run_time: float = maxf(0.1, delta.length() / CUTSCENE_NPC_SPEED)
	var run_tween: Tween = create_tween()
	run_tween.tween_property(erdon, "global_position", target_position, run_time)
	await run_tween.finished
	if not is_instance_valid(erdon):
		return
	if erdon_sprite.sprite_frames.has_animation(&"idle_right"):
		erdon_sprite.flip_h = player.global_position.x < erdon.global_position.x
		erdon_sprite.play(&"idle_right")
	elif erdon_sprite.sprite_frames.has_animation(&"idle"):
		erdon_sprite.flip_h = false
		erdon_sprite.play(&"idle")


## Defeat intervention. The combat scene has already shown the bear's standard hit
## and its death. The overworld now only shows Erdon finishing the real bear.
func _resolve_rescue() -> void:
	_state = State.RESOLVING_DEFEAT
	var spider: Node2D = _spider if is_instance_valid(_spider) else null
	var player: Node2D = _player if is_instance_valid(_player) else null
	var erdon: Node2D = _find_erdon()
	if spider == null or player == null or erdon == null:
		_enter_player_defeated()
		return
	if spider.has_method("freeze_for_finisher"):
		spider.freeze_for_finisher()
	_set_level_processing(true)
	_set_player_control(false)
	player.velocity = Vector2.ZERO
	await _close_combat()
	if not is_instance_valid(spider) or not is_instance_valid(erdon):
		_enter_player_defeated()
		return
	await _erdon_defeats_enemy(erdon, spider, player)
	Inventory.set_health(ERDON_RECOVERY_HP)
	if player.has_method("restore_idle"):
		player.restore_idle()
	_dialogue_locked_player = player
	_rescue_dialogue_stage = 0
	_finish_encounter()
	if is_instance_valid(_dialogue_locked_player) and _dialogue_locked_player.has_method("set_control_enabled"):
		_dialogue_locked_player.set_control_enabled(false)
	_start_erdon_rescue_dialogue()


## Fallback for levels without Erdon: preserve the terminal defeat behavior.
func _resolve_defeat() -> void:
	_state = State.RESOLVING_DEFEAT
	var player: Node2D = _player if is_instance_valid(_player) else null
	await _close_combat()
	if player != null and is_instance_valid(player) and player.has_method("play_dying"):
		var dying_anim: StringName = player.play_dying()
		await _await_animation_end(player.animated_sprite, _animation_length(player.animated_sprite, dying_anim) + SIGNAL_GRACE)
	_enter_player_defeated()


func _find_erdon() -> Node2D:
	var level: Node = get_tree().current_scene
	if level == null:
		return null
	return level.find_child("Erdon", true, false) as Node2D


func _erdon_defeats_enemy(erdon: Node2D, enemy: Node2D, player: Node2D) -> void:
	if erdon.has_method("set_collision_enabled"):
		erdon.set_collision_enabled(false)
	erdon.set_physics_process(false)
	# Place Erdon beside the bear instead of tweening him across the map.
	erdon.global_position = (enemy.global_position + Vector2(42.0, 0.0)).round()
	var erdon_sprite: AnimatedSprite2D = erdon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if erdon_sprite == null or erdon_sprite.sprite_frames == null:
		return
	var attack_name: StringName = &"attack_right"
	# attack_right faces right by default; Erdon stands to the bear's right.
	erdon_sprite.flip_h = true
	if not erdon_sprite.sprite_frames.has_animation(attack_name):
		attack_name = &"attack"
	if not erdon_sprite.sprite_frames.has_animation(attack_name):
		return
	erdon_sprite.frame = 0
	erdon_sprite.play(attack_name)
	var attack_length: float = _animation_length(erdon_sprite, attack_name)
	var erdon_impact: bool = await _await_frame(erdon_sprite, 1, attack_length + SIGNAL_GRACE)
	if not erdon_impact:
		push_warning("EncounterManager: Erdon attack did not reach its impact frame.")
	var death_name: StringName = enemy.play_death() if enemy.has_method("play_death") else &""
	var death_length: float = _animation_length(enemy.animation_sprite(), death_name) \
		if enemy.has_method("animation_sprite") else 0.0
	await _await_animation_end(enemy.animation_sprite(), death_length + SIGNAL_GRACE)
	if enemy.has_method("become_corpse"):
		enemy.become_corpse()
	await _await_animation_end(erdon_sprite, attack_length + SIGNAL_GRACE)
	if is_instance_valid(erdon):
		if erdon.has_method("set_collision_enabled"):
			erdon.set_collision_enabled(true)
		erdon.set_physics_process(true)
		if erdon_sprite.sprite_frames.has_animation(&"idle"):
			erdon_sprite.flip_h = player.global_position.x < erdon.global_position.x
			erdon_sprite.play(&"idle")


func _cutscene_markers(parent_name: String, prefix: String) -> Array[Marker2D]:
	var root: Node = get_tree().current_scene.find_child(parent_name, true, false)
	var markers: Array[Marker2D] = []
	if root == null:
		return markers
	for child: Node in root.get_children():
		if child is Marker2D and String(child.name).begins_with(prefix):
			markers.append(child as Marker2D)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return int(String(a.name).get_slice("_", 2)) < int(String(b.name).get_slice("_", 2)))
	return markers


func _play_cutscene_walk(sprite: AnimatedSprite2D, delta: Vector2, player: bool) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var horizontal: bool = absf(delta.x) >= absf(delta.y)
	var animation: StringName = &"run_right" if player else &"walk_right"
	if not horizontal and delta.y < 0.0:
		animation = &"run_up" if player else &"walk_up"
	elif not horizontal:
		animation = &"run_down" if player else &"walk"
	if not sprite.sprite_frames.has_animation(animation):
		return
	if horizontal:
		sprite.flip_h = delta.x < 0.0
	else:
		sprite.flip_h = false
	sprite.play(animation)


func _walk_cutscene_pair(leader: Node2D, follower: Node2D, markers: Array[Marker2D],
		follower_offset: Vector2) -> void:
	if markers.is_empty() or not is_instance_valid(leader) or not is_instance_valid(follower):
		return
	leader.set_physics_process(false)
	follower.set_physics_process(false)
	var leader_sprite: AnimatedSprite2D = leader.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var follower_sprite: AnimatedSprite2D = follower.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var previous_leader: Vector2 = leader.global_position
	for marker: Marker2D in markers:
		if not is_instance_valid(marker) or not is_instance_valid(leader) or not is_instance_valid(follower):
			return
		var leader_target: Vector2 = marker.global_position.round()
		var follower_target: Vector2 = (leader_target + follower_offset).round()
		var leader_delta: Vector2 = leader_target - previous_leader
		var follower_delta: Vector2 = follower_target - follower.global_position
		_play_cutscene_walk(leader_sprite, leader_delta, false)
		_play_cutscene_walk(follower_sprite, follower_delta, true)
		var duration: float = maxf(leader_delta.length() / CUTSCENE_NPC_SPEED,
			follower_delta.length() / CUTSCENE_PLAYER_SPEED)
		var step: Tween = create_tween().set_parallel()
		step.tween_property(leader, "global_position", leader_target, duration)
		step.tween_property(follower, "global_position", follower_target, duration)
		await step.finished
		if not is_instance_valid(leader) or not is_instance_valid(follower):
			return
		previous_leader = leader_target


func _escort_to_namura_entrance() -> void:
	var player: Node2D = _dialogue_locked_player
	var erdon: Node2D = _find_erdon()
	if player == null or erdon == null:
		return
	var markers: Array[Marker2D] = _cutscene_markers("Erden_cutscene_pathing", "Erden_cutscene_")
	await _walk_cutscene_pair(erdon, player, markers, Vector2(-16.0, -7.0))
	var player_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var erdon_sprite: AnimatedSprite2D = erdon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if player_sprite != null:
		player_sprite.play(&"idle_right")
	if erdon_sprite != null and erdon_sprite.sprite_frames.has_animation(&"idle_up"):
		erdon_sprite.flip_h = false
		erdon_sprite.play(&"idle_up")


func play_holt_afterthought() -> void:
	var holt: Node2D = get_tree().current_scene.find_child("Holt", true, false) as Node2D
	if holt == null:
		return
	if DialogueManager.has_method("set_dialogue_visible"):
		DialogueManager.set_dialogue_visible(false)
	if not is_instance_valid(holt):
		if DialogueManager.has_method("set_dialogue_visible"):
			DialogueManager.set_dialogue_visible(true)
		return
	holt.set_physics_process(false)
	var sprite: AnimatedSprite2D = holt.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var start: Vector2 = holt.global_position.round()
	var away: Vector2 = start + Vector2(48.0, 0.0)
	var away_delta: Vector2 = away - start
	_play_cutscene_walk(sprite, away_delta, false)
	var leave_tween: Tween = create_tween()
	leave_tween.tween_property(holt, "global_position", away, maxf(0.25, away_delta.length() / CUTSCENE_NPC_SPEED))
	await leave_tween.finished
	await get_tree().create_timer(0.25).timeout
	var return_delta: Vector2 = start - away
	_play_cutscene_walk(sprite, return_delta, false)
	var return_tween: Tween = create_tween()
	return_tween.tween_property(holt, "global_position", start, maxf(0.25, return_delta.length() / CUTSCENE_NPC_SPEED))
	await return_tween.finished
	if is_instance_valid(holt):
		holt.global_position = start
		if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"idle"):
			sprite.play(&"idle")
		holt.set_physics_process(true)
	if DialogueManager.has_method("set_dialogue_visible"):
		DialogueManager.set_dialogue_visible(true)


func _start_erdon_rescue_dialogue() -> void:
	var lines: Array[DialogueLineData] = _load_dialogue_lines(1, 6)
	if lines.is_empty():
		push_warning("EncounterManager: Erdon rescue dialogue resources are missing.")
		return
	DialogueManager.start(lines, "erdon_rescue_1")


func _walk_forest_exit_to_namura() -> void:
	var player: Node2D = _dialogue_locked_player
	var holt: Node2D = get_tree().current_scene.find_child("Holt", true, false) as Node2D
	if player == null or holt == null:
		return
	var entrance: Area2D = get_tree().current_scene.find_child("Namura_entrance", true, false) as Area2D
	if is_instance_valid(entrance):
		entrance.set_deferred("monitoring", false)
	player.set_physics_process(false)
	holt.set_physics_process(false)
	var player_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var holt_sprite: AnimatedSprite2D = holt.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var exit_target: Vector2 = Vector2(1290.0, 356.0)
	var player_delta: Vector2 = exit_target - player.global_position
	var holt_delta: Vector2 = exit_target - holt.global_position
	_play_cutscene_walk(player_sprite, player_delta, true)
	_play_cutscene_walk(holt_sprite, holt_delta, false)
	var erdon: Node2D = _find_erdon()
	if erdon != null:
		var erdon_sprite: AnimatedSprite2D = erdon.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		erdon.set_physics_process(false)
		var erdon_target: Vector2 = Vector2(985.0, 545.0)
		var erdon_delta: Vector2 = erdon_target - erdon.global_position
		_play_cutscene_walk(erdon_sprite, erdon_delta, false)
		var erdon_tween: Tween = create_tween()
		erdon_tween.tween_property(erdon, "global_position", erdon_target,
			maxf(0.1, erdon_delta.length() / CUTSCENE_NPC_SPEED))
	var duration: float = maxf(player_delta.length() / CUTSCENE_PLAYER_SPEED,
		holt_delta.length() / CUTSCENE_NPC_SPEED)
	var exit_tween: Tween = create_tween().set_parallel()
	exit_tween.tween_property(player, "global_position", exit_target, duration)
	exit_tween.tween_property(holt, "global_position", exit_target, duration)
	await exit_tween.finished


func _take_player_to_namura_shop() -> void:
	var root: Window = get_tree().root
	root.set_meta("target_position", Vector2(14.0, 207.0))
	get_tree().change_scene_to_file("res://namura.tscn")
	await get_tree().scene_changed
	await get_tree().process_frame
	var player: Node2D = _find_player()
	var holt: Node2D = get_tree().current_scene.find_child("Holt", true, false) as Node2D
	_namura_exit = get_tree().current_scene.find_child("Namura_exit", true, false) as Area2D
	if is_instance_valid(_namura_exit):
		_namura_exit.set_deferred("monitoring", false)
	if player == null or holt == null:
		return
	_dialogue_locked_player = player
	_player = player
	_set_player_control(false)
	# Holt begins at the first authored marker, then leads through every marker.
	holt.global_position = (get_tree().current_scene.find_child("Holt_cutscene_1", true, false) as Marker2D).global_position
	var markers: Array[Marker2D] = _cutscene_markers("Holt_cutscene_pathing", "Holt_cutscene_")
	await _walk_cutscene_pair(holt, player, markers, Vector2(-14.0, -10.0))
	if not is_instance_valid(player) or not is_instance_valid(holt):
		return
	var player_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var holt_sprite: AnimatedSprite2D = holt.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	player.velocity = Vector2.ZERO
	if player_sprite != null:
		player_sprite.play(&"idle_right")
	if holt_sprite != null and holt_sprite.sprite_frames.has_animation(&"idle_right"):
		holt_sprite.flip_h = player.global_position.x < holt.global_position.x
		holt_sprite.play(&"idle_right")


func _start_village_entrance_dialogue() -> void:
	var lines: Array[DialogueLineData] = _load_dialogue_lines(12, 23)
	if lines.is_empty():
		push_warning("EncounterManager: village entrance dialogue resources are missing.")
		return
	DialogueManager.start(lines, "erdon_rescue_12")


func _holt_leaves_namura() -> void:
	var holt: Node2D = get_tree().current_scene.find_child("Holt", true, false) as Node2D
	if holt == null:
		return
	holt.set_physics_process(false)
	var holt_sprite: AnimatedSprite2D = holt.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var target: Vector2 = Vector2(44.0, 32.0) * 16.0
	var delta: Vector2 = target - holt.global_position
	_play_cutscene_walk(holt_sprite, delta, false)
	var leave: Tween = create_tween()
	leave.tween_property(holt, "global_position", target,
		delta.length() / CUTSCENE_NPC_SPEED)
	await leave.finished
	if is_instance_valid(holt):
		holt.set_physics_process(false)
		holt.visible = false


func _start_holt_shop_dialogue() -> void:
	var lines: Array[DialogueLineData] = _load_dialogue_lines(24, 36)
	if lines.is_empty():
		push_warning("EncounterManager: Holt shop dialogue resources are missing.")
		return
	DialogueManager.start(lines, "erdon_rescue_24")


func _start_namura_arrival_dialogue() -> void:
	var lines: Array[DialogueLineData] = _load_dialogue_lines(7, 11)
	if lines.is_empty():
		push_warning("EncounterManager: Namura arrival dialogue resources are missing.")
		return
	DialogueManager.start(lines, "erdon_rescue_7")


func _load_dialogue_lines(first_id: int, last_id: int) -> Array[DialogueLineData]:
	var lines: Array[DialogueLineData] = []
	for id: int in range(first_id, last_id + 1):
		var path: String = "res://resources/dialogue/erdon_rescue_%d.tres" % id
		var line: DialogueLineData = load(path) as DialogueLineData
		if line == null:
			return []
		lines.append(line)
	return lines


## Terminal state after a defeat without a rescue NPC. The surviving enemy remains
## in the world and the player stays down, matching the fallback behavior.
func _enter_player_defeated() -> void:
	_spider = null
	_player = null
	_combat = null
	_state = State.PLAYER_DEFEATED


func _show_card_reward() -> void:
	if is_instance_valid(_reward_overlay):
		return
	var candidates: Array[String] = StandaloneCardFactory.all_ids()
	var selected: Array[CardData] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	while selected.size() < 3 and not candidates.is_empty():
		var total_weight: float = 0.0
		for candidate: String in candidates:
			var rarity: String = StandaloneCardFactory.rarity(candidate)
			total_weight += 0.65 if rarity == "common" else (0.30 if rarity == "uncommon" else 0.05)
		var roll: float = rng.randf() * total_weight
		var chosen_index: int = 0
		for candidate_index: int in range(candidates.size()):
			var candidate_rarity: String = StandaloneCardFactory.rarity(candidates[candidate_index])
			roll -= 0.65 if candidate_rarity == "common" else (0.30 if candidate_rarity == "uncommon" else 0.05)
			if roll <= 0.0:
				chosen_index = candidate_index
				break
		var chosen_id: String = candidates[chosen_index]
		selected.append(StandaloneCardFactory.card_from_id(chosen_id))
		candidates.remove_at(chosen_index)
	_reward_overlay = CardRewardOverlay.new()
	add_child(_reward_overlay)
	_reward_overlay.setup(selected)
	_reward_overlay.closed.connect(_on_reward_closed)

func _on_reward_closed() -> void:
	_reward_overlay = null


# --- Overlay / combat lifetime ---

func _build_overlay() -> bool:
	var packed: PackedScene = load(COMBAT_SCENE) as PackedScene
	if packed == null:
		push_error("EncounterManager: could not load %s." % COMBAT_SCENE)
		return false
	var combat: Node = packed.instantiate()
	if combat == null:
		push_error("EncounterManager: could not instantiate %s." % COMBAT_SCENE)
		return false

	_overlay = CanvasLayer.new()
	_overlay.name = "EncounterOverlay"
	_overlay.layer = OVERLAY_LAYER
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	# Everything lives under one Control so the whole encounter can be faded as a
	# unit, and so the level underneath is completely covered while it runs.
	_layer_root = Control.new()
	_layer_root.name = "EncounterLayerRoot"
	_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.add_child(_layer_root)

	# Opaque backing: guarantees the overworld cannot show through on unusual
	# aspect ratios, and swallows stray clicks so the level gets no input.
	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.color = Color.BLACK
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer_root.add_child(backing)

	_combat = combat
	_combat.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer_root.add_child(_combat)
	if _combat.has_signal("combat_finished"):
		_combat.connect("combat_finished", Callable(self, "_on_combat_finished"))
	else:
		push_warning("EncounterManager: combat scene has no 'combat_finished' signal.")

	# Hand the battle over through the combat scene's public interface only. The
	# initiating enemy supplies its own combat configuration — capabilities, artwork,
	# moveset — so each enemy fights as it should; an enemy with none (the spider) gets
	# an ordinary ground battle.
	if _combat.has_method("begin_encounter"):
		var encounter_config: Dictionary = {"source": "overworld", "erden_rescue": _find_erdon() != null}
		if _encounter_group.size() > 1:
			encounter_config["enemy_count"] = _encounter_group.size()
			encounter_config["dungeon_encounter"] = true
		if is_instance_valid(_spider) and _spider.get("encounter_id") == "tutorial_spider":
			encounter_config["tutorial_spider"] = true
		if is_instance_valid(_spider) and _spider.has_method("combat_config"):
			encounter_config.merge(_spider.combat_config(), true)
		_combat.begin_encounter(encounter_config)
	else:
		push_warning("EncounterManager: combat scene has no begin_encounter(); using its default setup.")
	return true


func _close_combat() -> void:
	if _layer_root != null and is_instance_valid(_layer_root):
		var tween: Tween = create_tween()
		tween.tween_property(_layer_root, "modulate:a", 0.0, FADE_OUT_TIME)
		await tween.finished
		await get_tree().process_frame
	if is_instance_valid(_combat):
		_combat.queue_free()
	_combat = null
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_layer_root = null


## Releases the suspension after a failed start, so the game is never left frozen.
func _release_after_failure() -> void:
	_close_combat_sync()
	_set_level_processing(true)
	_set_player_control(true)
	_spider = null
	_encounter_group.clear()
	_player = null
	_state = State.IDLE


func _close_combat_sync() -> void:
	if is_instance_valid(_combat):
		_combat.queue_free()
	_combat = null
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_layer_root = null


## Clears every encounter reference and starts the post-encounter cooldown.
func _finish_encounter() -> void:
	if is_instance_valid(_player) and _player.has_method("set_control_enabled"):
		_player.set_control_enabled(true)
	_spider = null
	_encounter_group.clear()
	_player = null
	_combat = null
	_state = State.IDLE
	_cooldown = COOLDOWN_AFTER_ENCOUNTER


## Victory cleanup for the overworld enemy. The spider is left in the world as a
## corpse on the final death frame, so only a spider that cannot hold a corpse is
## freed outright.
func _retire_spider(spider: Node2D) -> void:
	if not is_instance_valid(spider):
		return
	if spider.has_method("become_corpse"):
		spider.become_corpse()
	else:
		spider.queue_free()


# --- Overworld suspension ---

func _set_level_processing(active: bool) -> void:
	var level: Node = get_tree().current_scene
	if level == null:
		return
	level.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _set_player_control(active: bool) -> void:
	var player: Node2D = _player if is_instance_valid(_player) else _find_player()
	if player and player.has_method("set_control_enabled"):
		player.set_control_enabled(active)


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


# --- Finisher helpers ---

## Keeps the two sprites from occupying the same pixels: moves the PLAYER only,
## by the minimum whole-pixel distance, and never slides the spider away.
func _separate_whole_pixels(player: Node2D, spider: Node2D) -> void:
	var separation: Vector2 = player.global_position - spider.global_position
	if separation.length() >= MIN_FINISHER_SEPARATION:
		return
	var axis: Vector2 = Vector2.LEFT
	if absf(separation.x) >= absf(separation.y) and not is_zero_approx(separation.x):
		axis = Vector2(signf(separation.x), 0.0)
	elif not is_zero_approx(separation.y):
		axis = Vector2(0.0, signf(separation.y))
	var push: float = ceilf(maxf(MIN_FINISHER_SEPARATION - separation.length(), 1.0))
	var origin: Vector2 = player.global_position
	for candidate: Vector2 in [origin + axis * push, origin - axis * push]:
		var snapped_pos := Vector2(roundf(candidate.x), roundf(candidate.y))
		if snapped_pos == origin or _position_is_clear(snapped_pos):
			player.global_position = snapped_pos
			return


func _position_is_clear(pos: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _player_space()
	if space == null:
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 5.0
	query.shape = shape
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()


func _player_space() -> PhysicsDirectSpaceState2D:
	var node: Node2D = _player if is_instance_valid(_player) else null
	if node == null or node.get_world_2d() == null:
		return null
	return node.get_world_2d().direct_space_state


## Length of an animation, derived from its real frame count and speed.
func _animation_length(sprite: AnimatedSprite2D, anim_name: StringName) -> float:
	if sprite == null or sprite.sprite_frames == null:
		return 0.0
	if not sprite.sprite_frames.has_animation(anim_name):
		return 0.0
	var frames: int = sprite.sprite_frames.get_frame_count(anim_name)
	var speed: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return 0.0
	return float(frames) / speed


## Waits until the sprite reaches (or passes) a frame, using the real
## AnimatedSprite2D.frame_changed signal, with a timeout so a missing animation
## can never wedge the sequence.
func _await_frame(sprite: AnimatedSprite2D, frame: int, timeout: float) -> bool:
	if sprite == null:
		return false
	if sprite.frame >= frame:
		return true
	var reached: Array[bool] = [false]
	var callback := func() -> void:
		if sprite.frame >= frame:
			reached[0] = true
	sprite.frame_changed.connect(callback)
	var elapsed: float = 0.0
	while not reached[0] and elapsed < timeout:
		if not is_instance_valid(sprite):
			break
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	if is_instance_valid(sprite) and sprite.frame_changed.is_connected(callback):
		sprite.frame_changed.disconnect(callback)
	return reached[0]


## Waits for a non-looping animation to finish, again with a timeout fallback.
func _await_animation_end(sprite: AnimatedSprite2D, timeout: float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if not sprite.is_playing():
		return
	var finished: Array[bool] = [false]
	var callback := func() -> void:
		finished[0] = true
	sprite.animation_finished.connect(callback)
	var elapsed: float = 0.0
	while not finished[0] and elapsed < timeout:
		if not is_instance_valid(sprite):
			break
		elapsed += get_process_delta_time()
		await get_tree().process_frame
	if is_instance_valid(sprite) and sprite.animation_finished.is_connected(callback):
		sprite.animation_finished.disconnect(callback)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
