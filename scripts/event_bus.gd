extends Node
## Global signal bus autoload.
## Systems communicate through these signals without direct references.

# --- World State ---
@warning_ignore("unused_signal")
signal world_state_changed(new_state: int)  # 0 = NORMAL, 1 = TEA

# --- Tea Mechanic ---
@warning_ignore("unused_signal")
signal tea_activated()
@warning_ignore("unused_signal")
signal tea_expired()

# --- Combat ---
@warning_ignore("unused_signal")
signal enemy_killed(enemy_node: Node, enemy_type: String)
@warning_ignore("unused_signal")
signal player_damaged(amount: int, current_health: int, max_health: int)
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal player_attacked(target: Node)

# --- Items ---
@warning_ignore("unused_signal")
signal item_picked_up(item_data: Resource)
@warning_ignore("unused_signal")
signal item_dropped(item_data: Resource, position: Vector2)

# --- Day Cycle ---
@warning_ignore("unused_signal")
signal day_changed(new_day: int)
@warning_ignore("unused_signal")
signal time_of_day_changed(new_time: float)

# --- Shop ---
@warning_ignore("unused_signal")
signal shop_opened()
@warning_ignore("unused_signal")
signal shop_closed()
@warning_ignore("unused_signal")
signal sale_completed(item_data: Resource, price: int, customer_name: String)

# --- Dialogue ---
@warning_ignore("unused_signal")
signal dialogue_started(npc_name: String)
@warning_ignore("unused_signal")
signal dialogue_ended(npc_name: String)

# --- Interaction ---
@warning_ignore("unused_signal")
signal interact_pressed()
@warning_ignore("unused_signal")
signal inventory_full()

# --- Inventory ---
@warning_ignore("unused_signal")
signal bag_acquired()

# --- Echoes ---
@warning_ignore("unused_signal")
signal echo_spawned(echo_node: Node, source_entity_type: String)
