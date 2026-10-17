class_name ItemData
extends Resource
## Data container for item definitions. Create .tres files for each item.

enum ItemType {
	GENERIC,
	WEAPON,
	ARMOR,
	CONSUMABLE,
	MATERIAL,
	QUEST,
	KEY
}

@export var item_name: String = "Unknown Item"
@export var description: String = ""
@export var item_type: ItemType = ItemType.GENERIC
@export var value: int = 0          ## Sell/buy price in gold
@export var stackable: bool = false
@export var max_stack: int = 99
@export var icon_texture: Texture2D  ## Optional icon
@export var unique_id: String = ""   ## For save/load and quest checks


## Returns a human-readable string for UI display
func get_display_name() -> String:
	return item_name


func get_tooltip_text() -> String:
	var lines: PackedStringArray = [item_name]
	if description:
		lines.append(description)
	match item_type:
		ItemType.WEAPON:
			lines.append("[Weapon]")
		ItemType.ARMOR:
			lines.append("[Armor]")
		ItemType.CONSUMABLE:
			lines.append("[Consumable]")
		ItemType.MATERIAL:
			lines.append("[Material]")
		ItemType.QUEST:
			lines.append("[Quest Item]")
		ItemType.KEY:
			lines.append("[Key Item]")
	if value > 0:
		lines.append("Value: %d gold" % value)
	return "\n".join(lines)
