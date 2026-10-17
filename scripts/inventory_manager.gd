extends Node
## The player's inventory and purse, carried across every scene.
##
## This is an autoload because the things it owns have to outlive a scene change: health
## has to survive the trip back out of a fight, and a consumable is spent from INSIDE one.
## Combat reads and writes this directly rather than reaching through a scene transition
## to find the player node.
##
## One configurable inventory array. A new game starts at nine slots; the later bag upgrade
## grows this same array to eighteen without copying or reordering its existing items.
## Stacking is per item, and keys, weapons and shields are capped at one.

signal changed

const STARTING_SLOT_COUNT: int = 9
const UPGRADED_SLOT_COUNT: int = 18
## The player's maximum health. Matches PLAYER_MAX_HP in the combat script; when health
## is raised by other means this becomes the base rather than the whole story.
const PLAYER_MAX_HP: int = 8
const STARTING_COIN: int = 15
const MAX_DECK_SIZE: int = 20

## The live slots, left to right, top to bottom. An empty slot is null.
## This is the single source of truth for both the 9-slot and 18-slot states.
var slots: Array[InventoryItem] = []
## Persistent upgrade state: save this value with the inventory when saving is added later.
var inventory_capacity: int = STARTING_SLOT_COUNT
var coin: int = STARTING_COIN
## Health is carried between fights: combat starts the player from this, not from full.
var player_hp: int = PLAYER_MAX_HP


func _ready() -> void:
	# Whenever the bag changes, any card whose item is no longer carried leaves the deck
	# with it. prune_deck() emits deck_changed rather than changed, so this cannot loop.
	changed.connect(prune_deck)
	reset_to_starters()
	# A new game starts with every card its starting items can offer.
	fill_deck_from_items()


## The state a new game begins in: a long stick, a bark shield and a stone.
func restore_full_health() -> void:
	set_health(PLAYER_MAX_HP)


func reset_to_starters() -> void:
	# A fresh game always begins with the base bag, regardless of a prior session's upgrade.
	inventory_capacity = STARTING_SLOT_COUNT
	slots.clear()
	for i in inventory_capacity:
		slots.append(null)
	coin = STARTING_COIN
	player_hp = PLAYER_MAX_HP
	slots[0] = InventoryItem.make("Long Stick", "res://assets/Inventory/Items/longstick_item.png",
		InventoryItem.Kind.WEAPON, 1, false, "A sturdy length of wood.")
	slots[1] = InventoryItem.make("Bark Shield", "res://assets/Inventory/Items/barkshield_item.png",
		InventoryItem.Kind.SHIELD, 1, false, "Rough bark, surprisingly tough.")
	slots[2] = InventoryItem.make("Stone", "res://assets/Inventory/Items/stone_item.png",
		InventoryItem.Kind.CONSUMABLE, 3, true, "Good for throwing. Gone once it is.")
	changed.emit()


# --- Slots ----------------------------------------------------------------------

## Changes the bag capacity while preserving every existing slot and item reference.
## Only the authored base and upgraded capacities are accepted for now.
func set_inventory_capacity(new_capacity: int) -> bool:
	if new_capacity != STARTING_SLOT_COUNT and new_capacity != UPGRADED_SLOT_COUNT:
		return false
	if new_capacity == inventory_capacity:
		return true
	if new_capacity < inventory_capacity:
		for i in range(new_capacity, slots.size()):
			if slots[i] != null:
				return false
		while slots.size() > new_capacity:
			slots.remove_at(slots.size() - 1)
	else:
		while slots.size() < new_capacity:
			slots.append(null)
	inventory_capacity = new_capacity
	changed.emit()
	return true


## API for the future bag-upgrade reward. It is not called automatically.
func upgrade_inventory() -> bool:
	return set_inventory_capacity(UPGRADED_SLOT_COUNT)


func item_at(index: int) -> InventoryItem:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func is_empty(index: int) -> bool:
	return item_at(index) == null


## Total number of a given item name across every slot.
func count_of(item_name: String) -> int:
	var total: int = 0
	for item: InventoryItem in slots:
		if item != null and item.item_name == item_name:
			total += 1
	return total


## Puts an item in the first slot that will take it. Returns the slot used, or -1.
func add_item(item: InventoryItem) -> int:
	if item == null:
		return -1
	# A stackable item joins an existing stack before taking a fresh slot.
	if item.is_stackable():
		for i in slots.size():
			var existing: InventoryItem = slots[i]
			if existing != null and existing.item_name == item.item_name:
				slots[i] = item
				changed.emit()
				return i
	for i in slots.size():
		if slots[i] == null:
			slots[i] = item
			changed.emit()
			return i
	return -1


## Empties a slot. Returns what was in it.
func clear_slot(index: int) -> InventoryItem:
	var taken: InventoryItem = item_at(index)
	if taken != null:
		slots[index] = null
		changed.emit()
	return taken


## Swaps two slots, which is all a drag between squares needs to do.
func move_item(from_index: int, to_index: int) -> bool:
	if from_index == to_index:
		return false
	if from_index < 0 or to_index < 0:
		return false
	if from_index >= slots.size() or to_index >= slots.size():
		return false
	var held: InventoryItem = slots[from_index]
	slots[from_index] = slots[to_index]
	slots[to_index] = held
	changed.emit()
	return true


## Spends one of a consumable, wherever it is. Returns true if one was actually removed.
## This is what playing the stone in combat calls.
func spend_consumable(item_name: String) -> bool:
	for i in slots.size():
		var item: InventoryItem = slots[i]
		if item != null and item.item_name == item_name and item.consumed_on_use:
			slots[i] = null
			changed.emit()
			return true
	return false


# --- Health and purse -----------------------------------------------------------

## Clamps and stores health, so a fight can hand back whatever it ended on.
func set_health(value: int) -> void:
	var clamped: int = clampi(value, 0, PLAYER_MAX_HP)
	if clamped != player_hp:
		player_hp = clamped
		changed.emit()


func heal(amount: int) -> void:
	set_health(player_hp + amount)


func is_player_down() -> bool:
	return player_hp <= 0


func add_coin(amount: int) -> void:
	coin = maxi(0, coin + amount)
	changed.emit()


func spend_coin(amount: int) -> bool:
	if amount <= 0 or coin < amount:
		return false
	coin -= amount
	changed.emit()
	return true


# --- Deck management ------------------------------------------------------------
#
# The deck is an EXTENSION of the inventory, not a separate equipment system. Every card
# the player can bring into a fight is contributed by an item they are carrying, and the
# player chooses which of those cards to include. Take the item out of the bag and its
# cards leave the deck with it, so the two can never disagree.
#
# Nothing here adds cards on its own: picking an item up only makes its cards AVAILABLE.

signal deck_changed

## Which cards each item contributes, keyed by item name. Every copy is listed separately
## — the deck is a list of cards, not a count — so an item offering two Blocks offers two
## entries, and the player may take either, both or neither.
const ITEM_CARDS: Dictionary = {
	"Long Stick": [
		"res://resources/cards/long_stick.tres",
		"res://resources/cards/long_stick.tres",
		"res://resources/cards/long_stick.tres",
		"res://resources/cards/heavy_swing.tres",
	],
	"Bark Shield": [
		"res://resources/cards/bark_shield.tres",
		"res://resources/cards/bark_shield.tres",
		"res://resources/cards/bark_shield.tres",
		"res://resources/cards/bark_shield.tres",
	],
	"Reinforced Wooden Shield": [
		"res://resources/cards/reinforced_wooden_shield.tres",
		"res://resources/cards/reinforced_wooden_shield.tres",
		"res://resources/cards/reinforced_wooden_shield.tres",
		"res://resources/cards/reinforced_wooden_shield.tres",
	],
	"Stone": [
		"res://resources/cards/throw_stone.tres",
	],
	"Minor Healing Potion": [
		"res://resources/cards/minor_healing_potion.tres",
	],
}

## Cards the player brings to a fight by being who they are, rather than by carrying
## something. An innate source is ALWAYS available: Focus can be taken out of the deck,
## but it never leaves the list of things that can contribute — it drops off that list
## only while it is already in the deck, which is the state the player put it in.
const INNATE_CARDS: Dictionary = {
	"Focus": [
		"res://resources/cards/focus.tres",
	],
}

## The cards the player has chosen. Each entry is { "item": String, "path": String }, so a
## card always knows which item it came from and can be dropped when that item goes.
var active_deck: Array[Dictionary] = []
## Independently collected card IDs, including duplicate copies.
var owned_standalone_cards: Array[String] = []


## Resolves either a saved CardData resource or a runtime-generated sword card ID.
func card_data_for_path(path: String) -> CardData:
	if SwordCardFactory.is_card_id(path):
		return SwordCardFactory.card_from_id(path)
	if StandaloneCardFactory.is_card_id(path):
		return StandaloneCardFactory.card_from_id(path)
	if KnifeCardFactory.is_card_id(path):
		return KnifeCardFactory.card_from_id(path)
	return load(path) as CardData


## Every card a source could contribute, in order. Empty for things that offer nothing —
## a key, or a plain material. Sword variants are generated from their item data.
func cards_offered_by(source: String) -> Array[String]:
	if StandaloneCardFactory.is_card_id(source):
		var standalone_offers: Array[String] = []
		for owned: String in owned_standalone_cards:
			if owned == source:
				standalone_offers.append(owned)
		return standalone_offers
	for item: InventoryItem in slots:
		if item != null and item.item_name == source and item.sword_upgrade_level >= 0:
			return SwordCardFactory.cards_for(item.sword_material, item.sword_upgrade_level)
		if item != null and item.item_name == source and not item.knife_material.is_empty():
			return [KnifeCardFactory.main_id(item.knife_material), KnifeCardFactory.main_id(item.knife_material)]
	var out: Array[String] = []
	for table: Dictionary in [ITEM_CARDS, INNATE_CARDS]:
		for path: Variant in table.get(source, []):
			out.append(str(path))
	return out


## The carried items that offer cards at all, in slot order.
func card_items() -> Array[String]:
	var out: Array[String] = []
	for item: InventoryItem in slots:
		if item != null and (ITEM_CARDS.has(item.item_name) or item.sword_upgrade_level >= 0 or not item.knife_material.is_empty()) \
				and not out.has(item.item_name):
			out.append(item.item_name)
	return out


## True when the player is carrying at least one of this item — or it is innate, in which
## case they always have it.
func has_relic(item_name: String) -> bool:
	for item: InventoryItem in slots:
		if item != null and item.kind == InventoryItem.Kind.RELIC and item.item_name == item_name:
			return true
	return false


func carries(item_name: String) -> bool:
	if StandaloneCardFactory.is_card_id(item_name):
		return owned_standalone_cards.has(item_name)
	if INNATE_CARDS.has(item_name):
		return true
	for item: InventoryItem in slots:
		if item != null and item.item_name == item_name:
			return true
	return false


## Everything that can contribute cards right now, in the order the deck manager should
## list it: the carried items, then any innate source that still has cards to give. An
## innate source with all of its cards already in the deck is deliberately absent — it is
## not "somewhere else" as well as being in the deck.
func card_sources() -> Array[String]:
	var out: Array[String] = card_items()
	for standalone_id: String in owned_standalone_cards:
		if not out.has(standalone_id):
			out.append(standalone_id)
	for source: String in INNATE_CARDS:
		if out.has(source):
			continue
		if _cards_taken(source) < cards_offered_by(source).size():
			out.append(source)
	return out


## How many of a source's cards are in the deck, across all its card paths.
func _cards_taken(source: String) -> int:
	var n: int = 0
	for path: String in cards_offered_by(source):
		n += deck_count(source, path)
	return n


## How many copies of one of an item's cards are already in the deck.
func deck_count(item_name: String, path: String) -> int:
	var n: int = 0
	for entry: Dictionary in active_deck:
		if entry["item"] == item_name and entry["path"] == path:
			n += 1
	return n


## Adds one more copy of an item's card, if the player carries the item and has not
## already taken every copy it offers. Returns whether anything was added.
func add_card(item_name: String, path: String) -> bool:
	if active_deck.size() >= MAX_DECK_SIZE:
		return false
	if not carries(item_name):
		return false
	if deck_count(item_name, path) >= cards_offered_by(item_name).count(path):
		return false
	active_deck.append({"item": item_name, "path": path})
	deck_changed.emit()
	return true


## Removes one copy of a card. Returns whether one was actually there.
func remove_card(item_name: String, path: String) -> bool:
	for i in active_deck.size():
		if active_deck[i]["item"] == item_name and active_deck[i]["path"] == path:
			active_deck.remove_at(i)
			deck_changed.emit()
			return true
	return false


func add_standalone_card(card_id: String) -> bool:
	if not StandaloneCardFactory.is_card_id(card_id):
		return false
	owned_standalone_cards.append(card_id)
	deck_changed.emit()
	return true


func owned_standalone_card_ids() -> Array[String]:
	return owned_standalone_cards.duplicate()


## Drops every card whose item has left the bag. Connected to `changed`, so it runs after
## any alteration to the inventory and the deck can never hold a card the player has no
## way of bringing.
func prune_deck() -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in active_deck:
		if carries(str(entry["item"])):
			kept.append(entry)
	if kept.size() != active_deck.size():
		active_deck = kept
		deck_changed.emit()


## Takes every card the available sources offer, so a new game starts with a full deck.
func fill_deck_from_items() -> void:
	active_deck.clear()
	for source: String in card_sources():
		for path: String in cards_offered_by(source):
			active_deck.append({"item": source, "path": path})
	deck_changed.emit()


## The deck as card resources, in order, for combat to draw from.
func deck_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for entry: Dictionary in active_deck:
		var card: CardData = card_data_for_path(str(entry["path"]))
		if card != null:
			out.append(card)
	return out
