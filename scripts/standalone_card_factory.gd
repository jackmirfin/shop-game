class_name StandaloneCardFactory
extends RefCounted
## Runtime data for cards that exist independently of equipment.

const PREFIX: String = "standalone://"
const DEFINITIONS: Dictionary = {
	"open_wound": {"name":"Open Wound", "cost":1, "rarity":"uncommon", "actions":[{"type":"double_next_bleed"}], "keywords":["bleed"]},
	"contaminate": {"name":"Contaminate", "cost":1, "rarity":"uncommon", "actions":[{"type":"contaminate"}], "keywords":["poison"]},
	"quick_thinking": {"name":"Quick Thinking", "cost":0, "rarity":"common", "actions":[{"type":"draw_discard_choice", "draw":2}], "keywords":["consume"]},
	"preparation": {"name":"Preparation", "cost":1, "rarity":"common", "actions":[{"type":"next_attack_cost"}], "keywords":[]},
	"reinforce": {"name":"Reinforce", "cost":1, "rarity":"uncommon", "block":4, "actions":[{"type":"preserve_block", "amount":2}], "keywords":[]},
	"expose": {"name":"Expose", "cost":1, "actions":[{"type":"apply_status", "status":"mark", "amount":2}], "rarity":"common", "keywords":["mark"]},
	"kindling": {"name":"Kindling", "cost":0, "actions":[{"type":"trigger_burn"}], "rarity":"rare", "keywords":["burn"]},
	"second_wind": {"name":"Second Wind", "cost":0, "consume":true, "actions":[{"type":"energy", "amount":1}], "rarity":"uncommon", "keywords":["consume"]},
}

static func card_id(card_key: String) -> String:
	return PREFIX + card_key

static func is_card_id(path: String) -> bool:
	return path.begins_with(PREFIX) and DEFINITIONS.has(path.trim_prefix(PREFIX))

static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for key: String in DEFINITIONS.keys():
		result.append(card_id(key))
	return result

static func rarity(path: String) -> String:
	return str((DEFINITIONS.get(path.trim_prefix(PREFIX), {}) as Dictionary).get("rarity", "common"))

static func card_from_id(path: String) -> CardData:
	if not is_card_id(path):
		return null
	var key: String = path.trim_prefix(PREFIX)
	var definition: Dictionary = DEFINITIONS[key]
	var card: CardData = CardData.new()
	card.card_name = str(definition["name"])
	card.energy_cost = int(definition["cost"])
	card.description = _description(key)
	card.artwork = preload("res://assets/Cards/blue-backdrop.png")
	card.consume = bool(definition.get("consume", false))
	card.block = int(definition.get("block", 0))
	card.draw_amount = int(definition.get("draw", 0))
	card.combat_actions = (definition.get("actions", []) as Array).duplicate(true)
	card.keyword_ids = definition.get("keywords", []) as Array[String]
	card.keyword_tooltip = _tooltip(card.keyword_ids)
	card.rarity = str(definition.get("rarity", "common"))
	card.card_type = "skill"
	return card

static func _description(key: String) -> String:
	match key:
		"open_wound": return "Double Bleed applied by the next Attack this turn."
		"contaminate": return "Apply 1 Poison for each unique negative status."
		"quick_thinking": return "Draw 2 cards, then discard 1."
		"preparation": return "The next Attack this turn costs 1 less Energy."
		"reinforce": return "Gain 4 Block. Preserve up to 2 Block next turn."
		"expose": return "Apply 2 Mark."
		"kindling": return "Trigger existing Burn and consume it."
		"second_wind": return "Gain 1 Energy. Consume."
	return ""

static func _tooltip(keywords: Array[String]) -> String:
	var lines: Array[String] = []
	for keyword: String in keywords:
		lines.append(KeywordRegistry.description(keyword))
	return "\n".join(lines)
