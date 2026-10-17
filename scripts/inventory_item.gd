class_name InventoryItem
extends Resource
## One thing the player is carrying.
##
## Items are data, not nodes: the same item can sit in a slot, be described on hover, and
## — once the equipping work is done — become the card it plays. Stacking is per item,
## and weapons, shields and keys are always capped at one.

## What kind of thing it is. Kept as an enum because the rule that matters — "weapons and
## shields never stack" — is about the KIND of item, not an arbitrary number.
enum Kind { MATERIAL, WEAPON, SHIELD, KEY, CONSUMABLE, RELIC }

static func make_relic(p_name: String, p_icon_path: String, p_description: String) -> InventoryItem:
	return InventoryItem.make(p_name, p_icon_path, Kind.RELIC, 1, false, p_description)

@export var item_name: String = ""
@export var icon: Texture2D = null
@export var kind: Kind = Kind.MATERIAL
## Most this slot may hold. Forced to 1 for weapons, shields and keys.
@export var max_stack: int = 1
## Consumables (the stone) are spent when played and leave the inventory.
@export var consumed_on_use: bool = false
@export var description: String = ""
## Filled only for generated sword variants; ordinary inventory items leave these empty.
@export var sword_material: String = ""
@export var sword_upgrade_level: int = -1
@export var knife_material: String = ""


## Builds an item, applying the stacking rule so no caller has to remember it.
static func make(p_name: String, p_icon_path: String, p_kind: Kind, p_stack: int = 1,
		p_consumed: bool = false, p_description: String = "") -> InventoryItem:
	var item := InventoryItem.new()
	item.item_name = p_name
	item.icon = load(p_icon_path) as Texture2D
	item.kind = p_kind
	item.max_stack = 1 if _never_stacks(p_kind) else maxi(1, p_stack)
	item.consumed_on_use = p_consumed
	item.description = p_description
	return item


## Builds one data-driven sword variant from the canonical sword asset directory.
static func make_sword(material: String, upgrade_level: int) -> InventoryItem:
	var item: InventoryItem = InventoryItem.make(
		SwordCardFactory.item_name(material, upgrade_level),
		"res://assets/Inventory/Items/swords/%s-%d.png" % [material.to_lower(), upgrade_level],
		InventoryItem.Kind.WEAPON, 1, false,
		"A %s sword, upgrade %d." % [SwordCardFactory.display_material(material), upgrade_level])
	item.sword_material = material.to_lower()
	item.sword_upgrade_level = upgrade_level
	return item


static func make_knife(material: String) -> InventoryItem:
	var icon_key: String = str(KnifeCardFactory.ICONS.get(material, material))
	var item: InventoryItem = InventoryItem.make("%s Throwing Knives" % material.capitalize(),
		"res://assets/Inventory/Items/knives/%s.png" % icon_key, Kind.WEAPON, 1, false,
		"Two throwing knives that generate temporary Throws.")
	item.knife_material = material
	return item


## Keys, weapons and shields are one to a slot; everything else may stack.
static func _never_stacks(p_kind: Kind) -> bool:
	return p_kind == Kind.WEAPON or p_kind == Kind.SHIELD or p_kind == Kind.KEY


## True when this item may sit alongside others of its kind.
func is_stackable() -> bool:
	return max_stack > 1 and not _never_stacks(kind)
