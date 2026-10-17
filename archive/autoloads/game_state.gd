extends Node
## Persistent game state autoload.
## Stores global data that survives across scene/level transitions.

# --- Day & Time ---
var current_day: int = 1
var time_of_day: float = 0.0  # 0.0 = dawn, 0.5 = dusk, 1.0 = midnight (continuous)

# --- Player Economy ---
var player_gold: int = 200
var shop_reputation: int = 0

# --- Tea Mechanic ---
var tea_recipe_found: bool = false
var tea_unlocked: bool = true

# --- Player Combat (migrated from old global.gd) ---
var player_current_attack: bool = false

# --- Inventory ---
var inventory_unlocked: bool = false
var bag_equipped: bool = false

# --- Story Progression ---
var letter_read: bool = false
var has_shop_keys: bool = false

# --- World Flags ---
var flag_shop_cleaned: bool = false
var flag_first_sale: bool = false
var flag_watcher_seen: bool = false

# --- Killed Entities (for Echo system) ---
var killed_entities: Array[String] = []  # list of entity_type strings


func add_gold(amount: int) -> void:
	player_gold = max(0, player_gold + amount)


func spend_gold(amount: int) -> bool:
	if player_gold >= amount:
		player_gold -= amount
		return true
	return false


func advance_day() -> void:
	current_day += 1
	time_of_day = 0.0


func record_kill(entity_type: String) -> void:
	if entity_type not in killed_entities:
		killed_entities.append(entity_type)


func reset_run() -> void:
	"""Full reset for a new game."""
	current_day = 1
	time_of_day = 0.0
	player_gold = 0
	shop_reputation = 0
	tea_recipe_found = false
	tea_unlocked = false
	player_current_attack = false
	inventory_unlocked = false
	bag_equipped = false
	letter_read = false
	has_shop_keys = false
	flag_shop_cleaned = false
	flag_first_sale = false
	flag_watcher_seen = false
	killed_entities.clear()
