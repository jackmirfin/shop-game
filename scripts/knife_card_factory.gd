class_name KnifeCardFactory
extends RefCounted
## Data-driven throwing knife equipment and main card.

const PREFIX: String = "knife://"
const BLUE_BACKDROP: Texture2D = preload("res://assets/Cards/blue-backdrop.png")
const KNIFE_ARTWORK_SCALE: float = 0.55
const MATERIALS: Array[String] = ["nightiron", "bloodsteel", "swamp-gold", "froststeel", "stormfire"]
const ICONS: Dictionary = {"nightiron":"night-iron", "bloodsteel":"blood-steel", "swamp-gold":"swamp-gold", "froststeel":"frost-steel", "stormfire":"storm-fire"}
const EFFECTS: Dictionary = {
	"nightiron": {"status":"block", "amount":1},
	"bloodsteel": {"status":"bleed", "amount":1},
	"swamp-gold": {"status":"poison", "amount":1},
	"froststeel": {"status":"chill", "amount":1},
	"stormfire": {"status":"cycle", "statuses":["burn", "shock"]},
}

static func main_id(material: String) -> String:
	return PREFIX + material.to_lower() + "/main"

static func is_card_id(path: String) -> bool:
	return path.begins_with(PREFIX) and path.ends_with("/main")

static func material_from_id(path: String) -> String:
	return path.trim_prefix(PREFIX).trim_suffix("/main")

static func card_from_id(path: String) -> CardData:
	if not is_card_id(path):
		return null
	var material: String = material_from_id(path)
	if not MATERIALS.has(material):
		return null
	var card: CardData = CardData.new()
	card.card_name = "%s Throwing Knives" % material.capitalize()
	card.energy_cost = 1
	card.description = "Add 2 %s Throw cards to your hand." % material.capitalize()
	card.artwork = BLUE_BACKDROP
	card.artwork_overlay = load("res://assets/Inventory/Items/knives/%s.png" % str(ICONS.get(material, material))) as Texture2D
	card.artwork_overlay_scale = KNIFE_ARTWORK_SCALE
	card.combat_actions = [{"type":"generate_throws", "material":material, "count":2}]
	card.card_type = "skill"
	return card

static func throw_card(material: String) -> CardData:
	var card: CardData = CardData.new()
	card.card_name = "%s Throw" % material.capitalize()
	card.energy_cost = 0
	card.damage = 2
	card.consume = true
	card.temporary_combat = true
	card.description = "Deal 2 damage."
	card.artwork = BLUE_BACKDROP
	card.artwork_overlay = load("res://assets/Inventory/Items/knives/%s.png" % str(ICONS.get(material, material))) as Texture2D
	card.artwork_overlay_scale = KNIFE_ARTWORK_SCALE
	var effect: Dictionary = EFFECTS.get(material, {}) as Dictionary
	if effect.get("status", "") == "block":
		card.block = 1
	elif effect.get("status", "") == "cycle":
		card.combat_actions = [{"type":"cycle_status", "statuses":["burn", "shock"]}]
	else:
		card.combat_actions = [{"type":"apply_status", "status":str(effect.get("status", "")), "amount":int(effect.get("amount", 1))}]
	if effect.get("status", "") != "block":
		card.keyword_ids.append(str(effect.get("status", "")))
	card.keyword_ids.append("consume")
	card.card_type = "attack"
	return card
