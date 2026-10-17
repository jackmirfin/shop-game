class_name KeywordRegistry
extends RefCounted
## Shared keyword definitions for sword cards and their hover tooltips.

const DEFINITIONS: Dictionary = {
	"bleed": {"name": "Bleed", "description": "At the enemy's attack resolution, deal Bleed damage, then remove 1 Bleed."},
	"poison": {"name": "Poison", "description": "At the start of the enemy turn, deal Poison damage, then remove 1 Poison."},
	"burn": {"name": "Burn", "description": "At the end of the enemy turn, deal Burn damage, then remove all Burn."},
	"weak": {"name": "Weak", "description": "The enemy's next attack deals half damage, then removes 1 Weak."},
	"entangle": {"name": "Entangle", "description": "At 3 Entangle, convert it to Rooted."},
	"chill": {"name": "Chill", "description": "At 3 Chill, convert it to Frozen."},
	"shock": {"name": "Shock", "description": "An elemental status used by cycling and detonation effects."},
	"mark": {"name": "Mark", "description": "The next player hit consumes Mark and gains its damage bonus."},
	"thorns": {"name": "Thorns", "description": "When the enemy attacks, deal Thorns damage, then remove Thorns."},
	"dodge": {"name": "Dodge", "description": "Negate the next enemy attack, then consume 1 Dodge."},
	"doom": {"name": "Doom", "description": "At 3 Doom, deal 5 damage and remove 3 Doom."},
	"retain": {"name": "Retain", "description": "The card stays in hand when the hand is discarded."},
	"consume": {"name": "Consume", "description": "Remove the card from this combat after playing it."},
	"cleanse": {"name": "Cleanse", "description": "Remove one negative player status."},
	"pierce": {"name": "Pierce", "description": "Ignore the stated amount of enemy Block."},
	"fracture": {"name": "Fracture", "description": "The next hit gains bonus damage, then consumes Fracture."},
	"focus": {"name": "Focus", "description": "A sword charge that increases its damage until consumed or reset."},
	"growth": {"name": "Growth", "description": "A persistent sword charge gained by Rooting; it increases sword damage."},
	"bloom": {"name": "Bloom", "description": "A persistent sword charge that increases the sword's damage."},
	"drowsy": {"name": "Drowsy", "description": "At 3 Drowsy, delay the enemy action and remove 3 Drowsy."},
	"root": {"name": "Root", "description": "The enemy skips its next action, then Root is removed."},
	"freeze": {"name": "Freeze", "description": "The enemy skips its next action, then becomes temporarily immune to Freeze."},
	"hit_counter": {"name": "Hit Counter", "description": "Counts uses of this sword and triggers on the stated interval."},
	"combo": {"name": "Combo", "description": "Counts card types or sequence requirements for bonus damage."},
	"rupture": {"name": "Rupture", "description": "Consumes Bleed to deal immediate damage."},
}

static func definition(keyword_id: String) -> Dictionary:
	return DEFINITIONS.get(keyword_id.to_lower(), {}) as Dictionary

static func display_name(keyword_id: String) -> String:
	var entry: Dictionary = definition(keyword_id)
	return str(entry.get("name", keyword_id.capitalize()))

static func description(keyword_id: String, amount: int = 0) -> String:
	var entry: Dictionary = definition(keyword_id)
	var text: String = str(entry.get("description", "No definition available."))
	return "%s %d — %s" % [display_name(keyword_id), amount, text] if amount > 0 else "%s — %s" % [display_name(keyword_id), text]

static func action_text(action: Dictionary) -> String:
	var action_type: String = str(action.get("type", ""))
	var amount: int = int(action.get("amount", 0))
	match action_type:
		"apply_status", "weak":
			var status: String = str(action.get("status", "weak"))
			var every_n: int = int(action.get("every_n", 1))
			var cadence: String = "" if every_n <= 1 else " every %dth use" % every_n
			return "%s %d%s." % [display_name(status), amount, cadence]
		"block": return "Block %d." % amount
		"conditional_block": return "If Attack intent: Block %d." % amount
		"conditional_block_status": return "If Entangled: Block %d." % amount
		"ignore_block": return "Pierce %s." % ("all Block" if int(action.get("amount", 0)) < 0 else "Block %d" % int(action.get("amount", 0)))
		"draw": return "Draw %d." % int(action.get("amount", 1))
		"draw_discard": return "Draw %d · Discard %d%s." % [int(action.get("draw", 2)), int(action.get("discard", 1)), " · Retain discarded" if bool(action.get("retain_discard", false)) else ""]
		"cost_reduction": return "Every %dth use: random card costs %d less." % [int(action.get("every_n", 3)), int(action.get("amount", 1))]
		"temporary_upgrade": return "Temporarily upgrade a random card by %d." % int(action.get("amount", 1))
		"generate_throws": return "Add %d temporary Throws." % int(action.get("count", 2))
		"double_next_bleed": return "Double Bleed from the next Attack this turn."
		"contaminate": return "Poison for each unique negative status."
		"next_attack_cost": return "The next Attack costs 1 less Energy."
		"preserve_block": return "Preserve up to %d Block next turn." % int(action.get("amount", 2))
		"trigger_burn": return "Trigger and consume Burn."
		"energy": return "Gain %d Energy." % int(action.get("amount", 1))
		"draw_discard_choice": return "Draw %d, then discard 1." % int(action.get("draw", 2))
		"retain_charge": return "Damage scales with Retained cards."
		"consume_status_damage": return "%s: consume all for damage." % display_name(str(action.get("status", "")))
		"fracture_on_break": return "Pierce: apply Fracture when Block breaks."
		"activate_drowsy": return "Activate Drowsy."
		"apply_weak_if_poison": return "If Poisoned: Weak %d." % amount
		"preserve_weak": return "Poison can preserve Weak."
		"doom_config": return "Doom activates for %d." % int(action.get("damage", 5))
		"intent_adapt": return "Adapt to enemy intent."

		"heal_if_status": return "Heal %d if %s reaches %d." % [amount, display_name(str(action.get("status", ""))), int(action.get("threshold", 1))]
		"dodge": return "Dodge%s." % ("" if int(action.get("every_n", 1)) == 1 else " every %dth use" % int(action.get("every_n", 1)))
		"cleanse": return "Cleanse every %dth use." % int(action.get("every_n", 1))
		"multi_hit": return "%dx hit." % int(action.get("hits", 1))
		"cycle_status", "alternate_status": return "Cycle: %s." % ", ".join(action.get("statuses", []))
		"optional_sacrifice": return "Sacrifice 1 HP: apply Bleed%s." % (" and Entangle" if int((action.get("statuses", {}) as Dictionary).get("entangle", 0)) > 0 else "")
	return ""
