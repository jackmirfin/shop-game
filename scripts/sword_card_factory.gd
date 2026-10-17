class_name SwordCardFactory
extends RefCounted
## Runtime factory for every material/upgrade sword and its two cards.
##
## Sword identity lives here once: names, cumulative milestone text, damage curves and
## artwork paths. The factory returns CardData, so the existing card scene, Deck Manager and
## combat deck can consume sword cards without one scene or resource per variant.

const SWORD_DIR: String = "res://assets/Inventory/Items/swords/"
const BLUE_BACKDROP: Texture2D = preload("res://assets/Cards/blue-backdrop.png")

const ORDINARY_LIGHT: Array[int] = [2, 2, 3, 3, 4, 4, 5, 5, 6, 7]
const ORDINARY_HEAVY: Array[int] = [4, 4, 6, 6, 8, 8, 10, 10, 12, 14]
const AMETHYST_LIGHT: Array[int] = [2, 3, 3, 4, 4, 5, 6, 6, 7, 9]
const AMETHYST_HEAVY: Array[int] = [5, 7, 7, 9, 9, 11, 13, 13, 15, 19]

static var _definitions: Dictionary = {}


static func _definition(light_name: String, heavy_name: String,
		light_base: Array[String], heavy_base: Array[String],
		light_rules: Dictionary, heavy_rules: Dictionary) -> Dictionary:
	return {
		"light_name": light_name,
		"heavy_name": heavy_name,
		"light_base": light_base,
		"heavy_base": heavy_base,
		"light_rules": light_rules,
		"heavy_rules": heavy_rules,
	}


static func _ensure_definitions() -> void:
	if not _definitions.is_empty():
		return
	_definitions = {
		"amethyst": _definition("Amethyst Slash", "Amethyst Cleaver",
			[], [], {}, {}),
		"nightiron": _definition("Iron Guard", "Iron Reprisal",
			["If the enemy intends to attack, gain 1 Block."],
			["Gain 2 Block before attacking."],
			{1: ["Guard gives 2 Block."], 3: ["Reprisal gains 1 damage if Block remains."],
			 5: ["Heavy grants 3 Block."], 7: ["Full blocks apply 1 Mark."],
			 9: ["Full blocks immediately counter for 3 damage."]},
			{1: ["Guard gives 2 Block."], 3: ["Reprisal gains 1 damage if Block remains."],
			 5: ["Heavy grants 3 Block."], 7: ["Full blocks apply 1 Mark."],
			 9: ["Full blocks immediately counter for 3 damage."]}),
		"coppervine": _definition("Vine Slash", "Overgrowth",
			["Every second hit applies 1 Entangle."],
			["Apply 1 Entangle; gain 2 Block if the enemy was already Entangled."],
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 1 damage per Entangle."], 5: ["Gain 3 Block."],
			 7: ["Rooting draws 1 card."], 9: ["Normal enemies Root at 2 Entangle."]},
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 1 damage per Entangle."], 5: ["Gain 3 Block."],
			 7: ["Rooting draws 1 card."], 9: ["Normal enemies Root at 2 Entangle."]}),
		"sunbronze": _definition("Sunlit Edge", "First Light",
			["The first sword attack each turn deals 1 extra damage."],
			["Deal 2 extra damage if this is the first attack that turn."],
			{1: ["Any first Attack card qualifies."], 3: ["Heavy applies 1 Burn."],
			 5: ["The bonuses become 2 and 3 damage."],
			 7: ["Triggering the bonus gives the next Skill 1 Block."],
			 9: ["The first sword attack costs 0 once per combat."]},
			{1: ["Any first Attack card qualifies."], 3: ["Heavy applies 1 Burn."],
			 5: ["The bonuses become 2 and 3 damage."],
			 7: ["Triggering the bonus gives the next Skill 1 Block."],
			 9: ["The first sword attack costs 0 once per combat."]}),
		"aquamarine": _definition("Flowing Cut", "Riptide",
			["Every third Aquamarine attack draws 1 card."],
			["Draw 2 cards, then discard 1."],
			{1: ["The attack counter persists between turns."],
			 3: ["A discarded card gains Retain next shuffle."],
			 5: ["The Light triggers every second hit."],
			 7: ["Drawn attacks gain 1 damage that turn."],
			 9: ["Heavy makes the Retained card cost 0 on its next play."]},
			{1: ["The attack counter persists between turns."],
			 3: ["A discarded card gains Retain next shuffle."],
			 5: ["The Light triggers every second hit."],
			 7: ["Drawn attacks gain 1 damage that turn."],
			 9: ["Heavy makes the Retained card cost 0 on its next play."]}),
		"sapphire": _definition("Focused Edge", "Perfect Cut",
			["Consecutive Attacks generate 1 Focus, up to 3. Each Focus gives this sword 1 damage. Playing a Skill resets it."],
			["Consume Focus for 2 damage per stack."],
			{1: ["Power cards no longer reset Focus."], 3: ["Heavy gains 2 damage per Focus."],
			 5: ["Maximum Focus becomes 4."], 7: ["Consuming 3 or more Focus draws 1 card."],
			 9: ["Skills reduce Focus by 1 rather than clearing it."]},
			{1: ["Power cards no longer reset Focus."], 3: ["Heavy gains 2 damage per Focus."],
			 5: ["Maximum Focus becomes 4."], 7: ["Consuming 3 or more Focus draws 1 card."],
			 9: ["Skills reduce Focus by 1 rather than clearing it."]}),
		"rose-silver": _definition("Restoring Cut", "Silver Mercy",
			["Every third hit restores 1 HP, initially once per combat."],
			["Restore 1 HP after dealing damage, once per combat."],
			{1: ["The shared healing limit becomes twice per combat."],
			 3: ["Heavy heals only if HP is missing."], 5: ["Third-hit healing gives 1 Block."],
			 7: ["The healing limit becomes three times per combat."],
			 9: ["Excess healing becomes equal Block."]},
			{1: ["The shared healing limit becomes twice per combat."],
			 3: ["Heavy heals only if HP is missing."], 5: ["Third-hit healing gives 1 Block."],
			 7: ["The healing limit becomes three times per combat."],
			 9: ["Excess healing becomes equal Block."]}),
		"jade-steel": _definition("Balanced Edge", "Jade Reversal",
			["Deal 1 extra damage if the previous card granted Block."],
			["The next Block card grants 2 extra Block."],
			{1: ["The bonus carries between turns."], 3: ["Heavy also gains 1 Block."],
			 5: ["The bonuses become 2 damage and 3 Block."],
			 7: ["Successful alternation draws 1 card every third cycle."],
			 9: ["Each alternating card receives both bonuses."]},
			{1: ["The bonus carries between turns."], 3: ["Heavy also gains 1 Block."],
			 5: ["The bonuses become 2 damage and 3 Block."],
			 7: ["Successful alternation draws 1 card every third cycle."],
			 9: ["Each alternating card receives both bonuses."]}),
		"moonleaf": _definition("Lunar Cut", "Waning Strike",
			["Every second hit applies 1 Weak."], ["Apply 2 Weak."],
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 1 damage against Weak enemies."],
			 5: ["Light applies Weak every hit, once per turn."],
			 7: ["Hitting Weak enemies grants 1 Block."],
			 9: ["The first hit each turn applies Weak automatically."]},
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 1 damage against Weak enemies."],
			 5: ["Light applies Weak every hit, once per turn."],
			 7: ["Hitting Weak enemies grants 1 Block."],
			 9: ["The first hit each turn applies Weak automatically."]}),
		"duskthorn": _definition("Briar Edge", "Bramble Crash",
			["Gain 1 temporary Thorns."], ["Gain 1 damage per Thorns, capped at 3."],
			{1: ["Light grants 2 Thorns every second use."],
			 3: ["The Heavy damage cap becomes 4."], 5: ["Gain 2 Thorns per Light."],
			 7: ["Receiving damage retains 1 Thorns next turn."],
			 9: ["Retain half of unused Thorns between turns."]},
			{1: ["Light grants 2 Thorns every second use."],
			 3: ["The Heavy damage cap becomes 4."], 5: ["Gain 2 Thorns per Light."],
			 7: ["Receiving damage retains 1 Thorns next turn."],
			 9: ["Retain half of unused Thorns between turns."]}),
		"bloodsteel": _definition("Bloodletting", "Rupture",
			["Apply 1 Bleed."], ["Consume all Bleed and immediately deal that much damage."],
			{1: ["Bleed does not decrease on its first activation."],
			 3: ["Heavy gains 1 damage for every 2 Bleed consumed."],
			 5: ["Light applies 2 Bleed to unblocked enemies."],
			 7: ["Rupture applies 1 Mark."],
			 9: ["Below 25% enemy HP, Rupture deals consumed Bleed twice."]},
			{1: ["Bleed does not decrease on its first activation."],
			 3: ["Heavy gains 1 damage for every 2 Bleed consumed."],
			 5: ["Light applies 2 Bleed to unblocked enemies."],
			 7: ["Rupture applies 1 Mark."],
			 9: ["Below 25% enemy HP, Rupture deals consumed Bleed twice."]}),
		"ember-gold": _definition("Scorching Edge", "Ignition",
			["Apply 1 Burn."], ["Apply 2 Burn."],
			{1: ["Burn deals at least 1 damage even if cleansed."],
			 3: ["Heavy immediately activates existing Burn before adding more."],
			 5: ["Light applies 2 Burn every second hit."],
			 7: ["Burn activation applies 1 Shock."],
			 9: ["Heavy triggers Burn without removing it, once per turn."]},
			{1: ["Burn deals at least 1 damage even if cleansed."],
			 3: ["Heavy immediately activates existing Burn before adding more."],
			 5: ["Light applies 2 Burn every second hit."],
			 7: ["Burn activation applies 1 Shock."],
			 9: ["Heavy triggers Burn without removing it, once per turn."]}),
		"swamp-gold": _definition("Bogbite", "Septic Cut",
			["Every second hit applies 1 Poison."], ["Apply 2 Poison."],
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy prevents Poison decreasing once."],
			 5: ["Light applies Poison every hit, once per turn."],
			 7: ["Poisoned enemies generate 1 less Block."],
			 9: ["Poison never decreases on its first activation."]},
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy prevents Poison decreasing once."],
			 5: ["Light applies Poison every hit, once per turn."],
			 7: ["Poisoned enemies generate 1 less Block."],
			 9: ["Poison never decreases on its first activation."]}),
		"froststeel": _definition("Cold Edge", "Shatter",
			["Every second hit applies 1 Chill."], ["Gain 1 damage per Chill, then remove the Chill."],
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy no longer removes the first Chill."],
			 5: ["Light applies Chill every hit, once per turn."],
			 7: ["Damaging Frozen enemies draws 1 card."],
			 9: ["Shatter against a Frozen enemy deals 5 extra damage."]},
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy no longer removes the first Chill."],
			 5: ["Light applies Chill every hit, once per turn."],
			 7: ["Damaging Frozen enemies draws 1 card."],
			 9: ["Shatter against a Frozen enemy deals 5 extra damage."]}),
		"deepwater": _definition("Tidal Guard", "Undertow",
			["Gain 1 Block."], ["Gain 3 Block before attacking."],
			{1: ["Light gains 2 Block every second use."],
			 3: ["Heavy deals 1 extra damage if no Block was lost this turn."],
			 5: ["Heavy grants 4 Block."], 7: ["Retain up to 2 unused Block."],
			 9: ["Heavy gains damage equal to half the Block it grants."]},
			{1: ["Light gains 2 Block every second use."],
			 3: ["Heavy deals 1 extra damage if no Block was lost this turn."],
			 5: ["Heavy grants 4 Block."], 7: ["Retain up to 2 unused Block."],
			 9: ["Heavy gains damage equal to half the Block it grants."]}),
		"pearl-gold": _definition("Purifying Edge", "Pearl Remedy",
			["Every third use removes 1 negative player status."],
			["Remove 1 negative status; gain 2 Block if there is nothing to remove."],
			{1: ["The counter persists between combats until triggered."],
			 3: ["Heavy always grants at least 1 Block."], 5: ["Cleansing grants 3 Block."],
			 7: ["Cleansing restores 1 HP once per combat."],
			 9: ["Cleansing also draws 1 card."]},
			{1: ["The counter persists between combats until triggered."],
			 3: ["Heavy always grants at least 1 Block."], 5: ["Cleansing grants 3 Block."],
			 7: ["Cleansing restores 1 HP once per combat."],
			 9: ["Cleansing also draws 1 card."]}),
		"obsidian": _definition("Black Edge", "Obsidian Breaker",
			["Ignore 1 Block."], ["Ignore all Block."],
			{1: ["Light ignores 2 Block."], 3: ["Breaking Block applies Fracture: the next hit deals 2 extra damage."],
			 5: ["Fracture becomes 3 extra damage."], 7: ["Breaking Block draws 1 card once per turn."],
			 9: ["Excess armour-piercing damage is doubled."]},
			{1: ["Light ignores 2 Block."], 3: ["Breaking Block applies Fracture: the next hit deals 2 extra damage."],
			 5: ["Fracture becomes 3 extra damage."], 7: ["Breaking Block draws 1 card once per turn."],
			 9: ["Excess armour-piercing damage is doubled."]}),
		"bloodjade": _definition("Sanguine Edge", "Blood Feast",
			["Every second hit applies 1 Bleed."],
			["Restore 1 HP if the enemy has at least 3 Bleed, once per turn."],
			{1: ["The hit counter persists between turns."], 3: ["Heavy also applies 1 Bleed."],
			 5: ["The healing threshold becomes 2 Bleed."], 7: ["Healing gives equal Block."],
			 9: ["Every 5 Bleed damage restores 1 HP, up to twice per combat."]},
			{1: ["The hit counter persists between turns."], 3: ["Heavy also applies 1 Bleed."],
			 5: ["The healing threshold becomes 2 Bleed."], 7: ["Healing gives equal Block."],
			 9: ["Every 5 Bleed damage restores 1 HP, up to twice per combat."]}),
		"limeflare": _definition("Combo Edge", "Perfect Sequence",
			["Gain 1 damage for every different card type played this turn, up to 2."],
			["Gain 1 damage for each Attack, Skill and Power played, up to 3."],
			{1: ["Cards played before drawing this card count."],
			 3: ["Heavy draws 1 card if all three types were played."],
			 5: ["The caps become 3 and 4."],
			 7: ["Heavy refunds 1 energy after a complete sequence."],
			 9: ["The first complete sequence each turn makes it cost 0."]},
			{1: ["Cards played before drawing this card count."],
			 3: ["Heavy draws 1 card if all three types were played."],
			 5: ["The caps become 3 and 4."],
			 7: ["Heavy refunds 1 energy after a complete sequence."],
			 9: ["The first complete sequence each turn makes it cost 0."]}),
		"viridian-tide": _definition("Toxic Current", "Venom Tide",
			["Apply 1 Poison."], ["Gain 1 damage for every 3 Poison, capped at 3."],
			{1: ["Heavy also applies 1 Poison."], 3: ["The damage cap becomes 4."],
			 5: ["Light applies 2 Poison every second hit."], 7: ["Heavy preserves 1 Poison stack."],
			 9: ["Hitting 6 or more Poison spreads 2 Poison to every other enemy."]},
			{1: ["Heavy also applies 1 Poison."], 3: ["The damage cap becomes 4."],
			 5: ["Light applies 2 Poison every second hit."], 7: ["Heavy preserves 1 Poison stack."],
			 9: ["Hitting 6 or more Poison spreads 2 Poison to every other enemy."]}),
		"nightrose": _definition("Dreaming Edge", "Deep Slumber",
			["Every second hit applies 1 Drowsy. At 3, delay the next normal-enemy action."],
			["Apply 2 Drowsy."],
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 2 damage against Drowsy enemies."],
			 5: ["Boss Drowsy conversion applies 2 Weak."], 7: ["Waking enemies receive 2 Mark."],
			 9: ["Heavy immediately activates 3 Drowsy."]},
			{1: ["The hit counter persists between turns."],
			 3: ["Heavy gains 2 damage against Drowsy enemies."],
			 5: ["Boss Drowsy conversion applies 2 Weak."], 7: ["Waking enemies receive 2 Mark."],
			 9: ["Heavy immediately activates 3 Drowsy."]}),
		"black-rose": _definition("Withering Edge", "Final Petal",
			["Gain 1 damage below 50% enemy HP."], ["Gain 2 damage below 25% enemy HP."],
			{1: ["The thresholds become 60% and 30%."], 3: ["Heavy applies 1 Mark if it fails to kill."],
			 5: ["The bonuses become 2 and 4 damage."], 7: ["Kills draw 1 card."],
			 9: ["Killing creates a temporary 0-cost Black-rose Light attack."]},
			{1: ["The thresholds become 60% and 30%."], 3: ["Heavy applies 1 Mark if it fails to kill."],
			 5: ["The bonuses become 2 and 4 damage."], 7: ["Kills draw 1 card."],
			 9: ["Killing creates a temporary 0-cost Black-rose Light attack."]}),
		"umbral-gold": _definition("Patient Shadow", "Gilded Eclipse",
			["Gain 1 damage for every turn Retained, capped at 3."],
			["Gain 2 damage per Retained turn, then reset."],
			{1: ["The charge remains after shuffling."], 3: ["The Heavy cap becomes 6."],
			 5: ["The Light cap becomes 4."], 7: ["Fully charged attacks draw 1 card."],
			 9: ["A fully charged Heavy returns to hand at 0 cost."]},
			{1: ["The charge remains after shuffling."], 3: ["The Heavy cap becomes 6."],
			 5: ["The Light cap becomes 4."], 7: ["Fully charged attacks draw 1 card."],
			 9: ["A fully charged Heavy returns to hand at 0 cost."]}),
		"thornblood": _definition("Sacrificial Edge", "Bloodroot",
			["Optionally lose 1 HP to apply 2 Bleed."],
			["Optionally lose 1 HP to apply 2 Bleed and 1 Entangle."],
			{1: ["Sacrifice grants 1 Block."], 3: ["Heavy gains 2 damage when accepted."],
			 5: ["Gain 2 Block."], 7: ["Sacrifices cannot reduce the player below 1 HP."],
			 9: ["An accepted sacrifice doubles the applied statuses."]},
			{1: ["Sacrifice grants 1 Block."], 3: ["Heavy gains 2 damage when accepted."],
			 5: ["Gain 2 Block."], 7: ["Sacrifices cannot reduce the player below 1 HP."],
			 9: ["An accepted sacrifice doubles the applied statuses."]}),
		"verdant-aether": _definition("Gale Edge", "Gale Breaker",
			["Count this as two hits while dealing its listed total damage."],
			["Count this as three hits, dividing its damage between them."],
			{1: ["The second hit applies 1 Mark."], 3: ["Heavy removes an additional Flight stack."],
			 5: ["The final hit gains 1 damage."], 7: ["Grounding an enemy draws 1 card."],
			 9: ["Grounding an enemy refunds 1 energy."]},
			{1: ["The second hit applies 1 Mark."], 3: ["Heavy removes an additional Flight stack."],
			 5: ["The final hit gains 1 damage."], 7: ["Grounding an enemy draws 1 card."],
			 9: ["Grounding an enemy refunds 1 energy."]}),
		"voidbloom": _definition("Hollow Edge", "Void Harvest",
			["Gain 1 damage per card Consumed this combat, capped at 3."],
			["Consume a chosen card in hand for 3 damage."],
			{1: ["The Consume bonus persists after reshuffle."],
			 3: ["Heavy gains the consumed card's energy cost as damage."],
			 5: ["The passive cap becomes 4."], 7: ["Consuming a card draws 1 card."],
			 9: ["The first Heavy each combat returns 1 random Consumed card to discard."]},
			{1: ["The Consume bonus persists after reshuffle."],
			 3: ["Heavy gains the consumed card's energy cost as damage."],
			 5: ["The passive cap becomes 4."], 7: ["Consuming a card draws 1 card."],
			 9: ["The first Heavy each combat returns 1 random Consumed card to discard."]}),
		"witchwood": _definition("Hexing Edge", "Greater Hex",
			["Cycle between applying 1 Weak, Poison and Entangle."],
			["Apply 2 of the current status, then advance the cycle."],
			{1: ["The cycle position persists between turns."],
			 3: ["Heavy also applies 1 of the next status."],
			 5: ["Light applies 2 of its current status every third hit."],
			 7: ["Completing a cycle draws 1 card."], 9: ["Every third Heavy applies all three statuses."]},
			{1: ["The cycle position persists between turns."],
			 3: ["Heavy also applies 1 of the next status."],
			 5: ["Light applies 2 of its current status every third hit."],
			 7: ["Completing a cycle draws 1 card."], 9: ["Every third Heavy applies all three statuses."]}),
		"royal-gold": _definition("Noble Edge", "Royal Decree",
			["Every third use makes a random card in hand cost 1 less that turn."],
			["Temporarily upgrade one random card in hand for this combat."],
			{1: ["The counter persists between turns."], 3: ["Heavy also grants the chosen card Retain."],
			 5: ["Light triggers every second use."],
			 7: ["Cards already costing 0 may gain 1 damage or Block."],
			 9: ["The player chooses the upgraded card."]},
			{1: ["The counter persists between turns."], 3: ["Heavy also grants the chosen card Retain."],
			 5: ["Light triggers every second use."],
			 7: ["Cards already costing 0 may gain 1 damage or Block."],
			 9: ["The player chooses the upgraded card."]}),
		"crimson-orchid": _definition("Blooming Cut", "Scarlet Bloom",
			["Apply 1 Bleed. Bleed damage gives this sword 1 combat damage, capped at 3."],
			["Apply 2 Bleed and immediately gain 1 Bloom charge."],
			{1: ["Bloom charge persists after reshuffle."], 3: ["Heavy gains 1 damage per Bloom."],
			 5: ["The Bloom cap becomes 4."], 7: ["Full Bloom grants 1 energy once per combat."],
			 9: ["The cap becomes 5 and Heavy applies 3 Bleed."]},
			{1: ["Bloom charge persists after reshuffle."], 3: ["Heavy gains 1 damage per Bloom."],
			 5: ["The Bloom cap becomes 4."], 7: ["Full Bloom grants 1 energy once per combat."],
			 9: ["The cap becomes 5 and Heavy applies 3 Bleed."]}),
		"stormfire": _definition("Storm Edge", "Thunderflare",
			["Alternate between applying 1 Burn and 1 Shock."],
			["Apply 1 Burn and 1 Shock."],
			{1: ["The element persists between turns."], 3: ["Shock detonation triggers existing Burn."],
			 5: ["Every fourth Light applies both."], 7: ["Detonating either status applies 1 Mark."],
			 9: ["Every third Light applies both effects."]},
			{1: ["The element persists between turns."], 3: ["Shock detonation triggers existing Burn."],
			 5: ["Every fourth Light applies both."], 7: ["Detonating either status applies 1 Mark."],
			 9: ["Every third Light applies both effects."]}),
		"moonstone": _definition("Phasing Edge", "Phase Cut",
			["Every third use grants Dodge."], ["Grant Dodge after attacking, once per combat."],
			{1: ["The counter persists between turns."], 3: ["Heavy can trigger twice per combat."],
			 5: ["A successful Dodge grants 1 Block."], 7: ["Dodging draws 1 card."],
			 9: ["A successful Dodge returns Heavy to hand at 0 cost once per combat."]},
			{1: ["The counter persists between turns."], 3: ["Heavy can trigger twice per combat."],
			 5: ["A successful Dodge grants 1 Block."], 7: ["Dodging draws 1 card."],
			 9: ["A successful Dodge returns Heavy to hand at 0 cost once per combat."]}),
		"duskbloom": _definition("Twilight Edge", "Night Bloom",
			["Deal 1 extra damage against Poisoned or Weak enemies."],
			["Deal 2 extra damage if both Poison and Weak are present; apply 1 Poison."],
			{1: ["Light gains 2 damage when both are present."],
			 3: ["Heavy applies 1 Weak if the enemy is Poisoned."],
			 5: ["The Heavy bonus becomes 3 damage."],
			 7: ["Poison damage has a chance to preserve Weak."],
			 9: ["Poisoned enemies begin each turn with 1 Weak."]},
			{1: ["Light gains 2 damage when both are present."],
			 3: ["Heavy applies 1 Weak if the enemy is Poisoned."],
			 5: ["The Heavy bonus becomes 3 damage."],
			 7: ["Poison damage has a chance to preserve Weak."],
			 9: ["Poisoned enemies begin each turn with 1 Weak."]}),
		"blackfrost": _definition("Abyssal Frost", "Black Shatter",
			["Ignore 1 Block and apply Chill every second hit."],
			["Ignore all Block and apply 2 Chill."],
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 2 damage against Chilled enemies."],
			 5: ["Light applies Chill every hit, once per turn."], 7: ["Freezing applies 2 Mark."],
			 9: ["Frozen enemies temporarily lose all Block and damage resistance."]},
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 2 damage against Chilled enemies."],
			 5: ["Light applies Chill every hit, once per turn."], 7: ["Freezing applies 2 Mark."],
			 9: ["Frozen enemies temporarily lose all Block and damage resistance."]}),
		"venom-rose": _definition("Venom Petal", "Toxic Bloom",
			["Alternate between applying 1 Poison and 1 Bleed."],
			["Apply 1 Poison and 1 Bleed."],
			{1: ["The element persists between turns."],
			 3: ["When both statuses deal damage in one turn, deal 2 extra damage."],
			 5: ["Heavy applies 2 of each status."], 7: ["Reaction damage becomes 3."],
			 9: ["Reaction no longer causes either status to decay that turn."]},
			{1: ["The element persists between turns."],
			 3: ["When both statuses deal damage in one turn, deal 2 extra damage."],
			 5: ["Heavy applies 2 of each status."], 7: ["Reaction damage becomes 3."],
			 9: ["Reaction no longer causes either status to decay that turn."]}),
		"orchid-vine": _definition("Growing Edge", "Wild Growth",
			["Every second hit applies 1 Entangle. Rooting grants Growth: 1 sword damage, capped at 3."],
			["Apply 2 Entangle."],
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 1 damage per Growth."],
			 5: ["The Growth cap becomes 4."], 7: ["Rooting draws 1 card."],
			 9: ["The Growth cap becomes 6 and Rooting grants 1 Block per Growth."]},
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 1 damage per Growth."],
			 5: ["The Growth cap becomes 4."], 7: ["Rooting draws 1 card."],
			 9: ["The Growth cap becomes 6 and Rooting grants 1 Block per Growth."]}),
		"prismleaf": _definition("Prismatic Edge", "Prismatic End",
			["Cycle through Burn, Poison, Chill and Shock, applying 1."],
			["Apply 2 of the current element and advance the cycle."],
			{1: ["The cycle persists between turns."], 3: ["Heavy also applies 1 of the next element."],
			 5: ["Completing a cycle deals 2 unblockable damage."], 7: ["Completion draws 1 card."],
			 9: ["Completion deals 4 unblockable damage."]},
			{1: ["The cycle persists between turns."], 3: ["Heavy also applies 1 of the next element."],
			 5: ["Completing a cycle deals 2 unblockable damage."], 7: ["Completion draws 1 card."],
			 9: ["Completion deals 4 unblockable damage."]}),
		"dawnsteel": _definition("Radiant Edge", "Daybreak",
			["Gain 1 damage per different negative status on the enemy, capped at 3."],
			["Remove 1 negative player status and gain 1 Block per enemy status."],
			{1: ["Heavy gains at least 2 Block."], 3: ["Heavy also deals 1 damage per enemy status."],
			 5: ["The damage caps become 4."], 7: ["Cleansing draws 1 card."],
			 9: ["The caps become 5 and cleansing restores 1 HP once per combat."]},
			{1: ["Heavy gains at least 2 Block."], 3: ["Heavy also deals 1 damage per enemy status."],
			 5: ["The damage caps become 4."], 7: ["Cleansing draws 1 card."],
			 9: ["The caps become 5 and cleansing restores 1 HP once per combat."]}),
		"elder-silver": _definition("Ancient Answer", "Elder Judgement",
			["Against Attack intents, gain 1 Block; Buff intents, deal 1 extra damage; Defence intents, apply 1 Mark."],
			["Gain 3 Block, 3 damage or 2 Mark according to intent."],
			{1: ["Unknown intents give 1 Block."], 3: ["Heavy activates an additional lesser benefit."],
			 5: ["Light values become 2."], 7: ["Correct adaptation draws 1 card every third use."],
			 9: ["Heavy activates all three benefits."]},
			{1: ["Unknown intents give 1 Block."], 3: ["Heavy activates an additional lesser benefit."],
			 5: ["Light values become 2."], 7: ["Correct adaptation draws 1 card every third use."],
			 9: ["Heavy activates all three benefits."]}),
		"embervoid": _definition("Cinderless Edge", "Void Detonation",
			["Apply 1 Burn and gain 1 damage per Consumed card, capped at 3."],
			["Consume all Burn and deal it immediately."],
			{1: ["The Consumed-card counter persists through reshuffles."],
			 3: ["Heavy gains 1 damage per Consumed card."], 5: ["The passive cap becomes 4."],
			 7: ["Detonation applies 1 Shock."], 9: ["Detonation removes only half the Burn."]},
			{1: ["The Consumed-card counter persists through reshuffles."],
			 3: ["Heavy gains 1 damage per Consumed card."], 5: ["The passive cap becomes 4."],
			 7: ["Detonation applies 1 Shock."], 9: ["Detonation removes only half the Burn."]}),
		"grave-gold": _definition("Graven Edge", "Death Knell",
			["Every second hit applies 1 Doom."], ["Apply 2 Doom."],
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 2 damage if Doom activates."],
			 5: ["Doom activation deals 6 damage."], 7: ["Doom activation draws 1 card."],
			 9: ["Activating Doom creates a temporary 0-cost Soul Slash dealing 3 damage."]},
			{1: ["The hit counter persists between turns."], 3: ["Heavy gains 2 damage if Doom activates."],
			 5: ["Doom activation deals 6 damage."], 7: ["Doom activation draws 1 card."],
			 9: ["Activating Doom creates a temporary 0-cost Soul Slash dealing 3 damage."]}),
	}


static func material_def(material: String) -> Dictionary:
	_ensure_definitions()
	return _definitions.get(material.to_lower(), {}) as Dictionary


static func all_materials() -> Array[String]:
	_ensure_definitions()
	var names: Array[String] = []
	for material: String in _definitions.keys():
		names.append(material)
	names.sort()
	return names


static func is_material(material: String) -> bool:
	return not material_def(material).is_empty()


static func roman(level: int) -> String:
	const numerals: Array[String] = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]
	return numerals[level] if level >= 0 and level < numerals.size() else ""


static func display_material(material: String) -> String:
	var words: PackedStringArray = material.to_lower().split("-")
	var display: Array[String] = []
	for word: String in words:
		if word.is_empty():
			continue
		display.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(display)


static func item_name(material: String, level: int) -> String:
	var name: String = "%s Sword" % display_material(material)
	var numeral: String = roman(level)
	return name if numeral.is_empty() else "%s %s" % [name, numeral]


static func item_icon(material: String, level: int) -> Texture2D:
	return load("%s%s-%d.png" % [SWORD_DIR, material.to_lower(), level]) as Texture2D


static func card_id(material: String, level: int, heavy: bool) -> String:
	return "sword://%s/%d/%s" % [material.to_lower(), level, "heavy" if heavy else "light"]


static func is_card_id(path: String) -> bool:
	return path.begins_with("sword://")


static func cards_for(material: String, level: int) -> Array[String]:
	var light: String = card_id(material, level, false)
	var heavy: String = card_id(material, level, true)
	return [light, heavy, light, heavy]


static func _damage(material: String, level: int, heavy: bool) -> int:
	var table: Array[int] = AMETHYST_HEAVY if heavy else AMETHYST_LIGHT
	if material.to_lower() != "amethyst":
		table = ORDINARY_HEAVY if heavy else ORDINARY_LIGHT
	return table[level]


static func _rules_for(definition: Dictionary, heavy: bool, level: int) -> Array[String]:
	var out: Array[String] = []
	var base_key: String = "heavy_base" if heavy else "light_base"
	var rules_key: String = "heavy_rules" if heavy else "light_rules"
	for line: String in definition.get(base_key, []):
		out.append(line)
	var rules: Dictionary = definition.get(rules_key, {}) as Dictionary
	for threshold: int in range(1, level + 1):
		var milestone: Array = rules.get(threshold, []) as Array
		var light_name: String = str(definition.get("light_name", "")).to_lower()
		var heavy_name: String = str(definition.get("heavy_name", "")).to_lower()
		for line: String in milestone:
			var lower_line: String = line.to_lower()
			if heavy and (lower_line.contains("light") or lower_line.contains(light_name)):
				continue
			if not heavy and (lower_line.contains("heavy") or lower_line.contains(heavy_name)):
				continue
			out.append(line)
	return out


static func _description(material: String, level: int, heavy: bool) -> String:
	var lines: Array[String] = ["Deal %d damage." % _damage(material, level, heavy)]
	var actions: Array[Dictionary] = _combat_actions(material, level, heavy)
	for action: Dictionary in actions:
		var action_line: String = KeywordRegistry.action_text(action)
		if not action_line.is_empty() and lines.size() < 4:
			lines.append(action_line)
	if lines.size() == 1:
		var definition: Dictionary = material_def(material)
		var base_key: String = "heavy_base" if heavy else "light_base"
		var base_lines: Array = definition.get(base_key, []) as Array
		if not base_lines.is_empty():
			lines.append(str(base_lines[0]))
	return "\n".join(lines)


static func _keyword_ids(material: String, level: int, heavy: bool) -> Array[String]:
	var result: Array[String] = []
	var full_text: String = " ".join(_rules_for(material_def(material), heavy, level)).to_lower()
	var known: Array[String] = ["bleed", "poison", "burn", "weak", "entangle", "chill", "shock",
		"mark", "thorns", "dodge", "doom", "retain", "consume", "cleanse", "pierce", "fracture",
		"focus", "growth", "bloom", "drowsy", "root", "freeze", "combo", "rupture"]
	for keyword_id: String in known:
		if full_text.contains(keyword_id):
			result.append(keyword_id)
	return result


static func _combat_actions(material: String, level: int, heavy: bool) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var every_two: int = 1 if level >= 5 else 2
	match material.to_lower():
		"nightiron":
			if heavy:
				actions.append({"type": "block", "amount": 3 if level >= 5 else 2})
			else:
				actions.append({"type": "conditional_block", "intent": "attack", "amount": 2 if level >= 1 else 1})
		"coppervine":
			actions.append({"type": "apply_status", "status": "entangle", "amount": 1,
				"every_n": every_two if not heavy else 1})
			if heavy:
				actions.append({"type": "conditional_block_status", "status": "entangle", "amount": 2})
		"aquamarine":
			if heavy:
				actions.append({"type": "draw_discard", "draw": 2, "discard": 1,
				"retain_discard": level >= 3})
			else:
				actions.append({"type": "draw", "amount": 1, "every_n": every_two})
		"moonleaf":
			actions.append({"type": "weak", "amount": 2 if heavy else 1,
				"every_n": 1 if (level >= 5 and not heavy) else (1 if heavy else 2)})
		"duskthorn":
			if heavy:
				actions.append({"type": "bonus_per_status", "status": "thorns", "amount": 1,
					"cap": 4 if level >= 3 else 3, "consume": true})
			else:
				actions.append({"type": "apply_status", "status": "thorns", "amount": 2 if level >= 5 else 1,
					"temporary": true})
		"bloodsteel":
			if heavy:
				actions.append({"type": "consume_status_damage", "status": "bleed",
					"multiplier": 2 if level >= 9 else 1,
					"bonus_per": 2 if level >= 3 else 0})
				if level >= 7:
					actions.append({"type": "apply_status", "status": "mark", "amount": 1})
			else:
				actions.append({"type": "apply_status", "status": "bleed", "amount": 2 if level >= 5 else 1})
		"ember-gold":
			actions.append({"type": "apply_status", "status": "burn", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
		"swamp-gold":
			actions.append({"type": "apply_status", "status": "poison", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
		"froststeel":
			if heavy:
				actions.append({"type": "bonus_per_status", "status": "chill", "amount": 1,
					"consume": level < 3, "frozen_bonus": 5 if level >= 9 else 0})
			else:
				actions.append({"type": "apply_status", "status": "chill", "amount": 1,
					"every_n": every_two})
		"pearl-gold":
			actions.append({"type": "cleanse", "every_n": 3})
		"obsidian":
			actions.append({"type": "ignore_block", "amount": -1 if heavy else (2 if level >= 1 else 1),
			"fracture_on_break": level >= 3, "fracture_bonus": 3 if level >= 5 else 2,
			"draw_on_break": level >= 7, "double_excess": level >= 9})
		"bloodjade":
			if heavy:
				actions.append({"type": "heal_if_status", "status": "bleed", "amount": 1, "threshold": 2 if level >= 5 else 3})
				if level >= 3:
					actions.append({"type": "apply_status", "status": "bleed", "amount": 1})
			else:
				actions.append({"type": "apply_status", "status": "bleed", "amount": 1,
					"every_n": every_two})
		"viridian-tide":
			actions.append({"type": "apply_status", "status": "poison", "amount": 1,
				"also_heavy": heavy})
			if heavy:
				actions.append({"type": "bonus_per_status", "status": "poison", "amount": 1,
					"per": 3, "cap": 4 if level >= 3 else 3})
		"nightrose":
			actions.append({"type": "apply_status", "status": "drowsy", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
			if heavy and level >= 9:
				actions.append({"type": "activate_drowsy"})
		"thornblood":
			actions.append({"type": "optional_sacrifice", "hp": 1, "statuses": {"bleed": 2, "entangle": 1 if heavy else 0}})
		"verdant-aether":
			actions.append({"type": "multi_hit", "hits": 3 if heavy else 2})
		"umbral-gold":
			actions.append({"type": "retain_charge", "heavy": heavy, "cap": 6 if heavy and level >= 3 else (4 if not heavy and level >= 5 else 3)})
		"witchwood":
			actions.append({"type": "cycle_status", "statuses": ["weak", "poison", "entangle"],
				"amount": 2 if heavy else 1})
		"royal-gold":
			if heavy:
				actions.append({"type": "temporary_upgrade", "amount": 1, "retain": level >= 3})
			else:
				actions.append({"type": "cost_reduction", "amount": 1, "every_n": 2 if level >= 5 else 3})
		"crimson-orchid":
			actions.append({"type": "apply_status", "status": "bleed", "amount": 3 if heavy and level >= 9 else (2 if heavy else 1)})
		"stormfire":
			actions.append({"type": "alternate_status", "statuses": ["burn", "shock"], "amount": 1,
				"both": heavy or level >= 9})
		"moonstone":
			actions.append({"type": "dodge", "every_n": 3 if not heavy else 1})
		"duskbloom":
			actions.append({"type": "duskbloom_bonus", "amount": 2 if level >= 1 and not heavy else (3 if level >= 5 and heavy else (2 if heavy else 1))})
			if heavy:
				actions.append({"type": "apply_status", "status": "poison", "amount": 1})
				if level >= 3:
					actions.append({"type": "apply_weak_if_poison", "amount": 1})
				if level >= 7:
					actions.append({"type": "preserve_weak"})
		"blackfrost":
			actions.append({"type": "ignore_block", "amount": -1 if heavy else 1})
			actions.append({"type": "apply_status", "status": "chill", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
		"venom-rose":
			actions.append({"type": "alternate_status", "statuses": ["poison", "bleed"], "amount": 1,
				"both": heavy})
		"orchid-vine":
			actions.append({"type": "apply_status", "status": "entangle", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
		"prismleaf":
			actions.append({"type": "cycle_status", "statuses": ["burn", "poison", "chill", "shock"],
				"amount": 2 if heavy else 1})
		"embervoid":
			if heavy:
				actions.append({"type": "consume_status_damage", "status": "burn", "multiplier": 1})
			else:
				actions.append({"type": "apply_status", "status": "burn", "amount": 1})
		"elder-silver":
			actions.append({"type": "intent_adapt", "amount": 2 if level >= 5 else 1,
				"heavy": heavy, "all_at_9": heavy and level >= 9})
		"grave-gold":
			actions.append({"type": "apply_status", "status": "doom", "amount": 2 if heavy else 1,
				"every_n": 1 if heavy else every_two})
			actions.append({"type": "doom_config", "damage": 6 if level >= 5 else 5,
				"soul_slash": level >= 9})
	return actions


static func _supported_fields(card: CardData, material: String, level: int, heavy: bool) -> void:
	var normalized: String = material.to_lower()
	card.combat_actions = _combat_actions(normalized, level, heavy)
	card.sword_effects = {
		"material": normalized,
		"upgrade_level": level,
		"attack_type": "heavy" if heavy else "light",
		"description_is_authoritative": true,
		"combat_support": "partial",
		"actions": card.combat_actions,
	}
	if normalized == "amethyst":
		card.sword_effects["combat_support"] = "full"
		return
	if normalized == "moonleaf" and heavy:
		card.weak = 2
	if normalized == "deepwater":
		card.block = 3 if heavy else 1
		if heavy and level >= 5:
			card.block = 4
	if normalized == "nightiron" and heavy:
		card.block = 3 if level >= 5 else 2


static func card_from_id(path: String) -> CardData:
	if not is_card_id(path):
		return null
	var parts: PackedStringArray = path.trim_prefix("sword://").split("/")
	if parts.size() != 3:
		return null
	var material: String = parts[0].to_lower()
	var level: int = int(parts[1])
	var heavy: bool = parts[2] == "heavy"
	var definition: Dictionary = material_def(material)
	if definition.is_empty() or level < 0 or level > 9 or (parts[2] != "light" and not heavy):
		return null
	var card: CardData = CardData.new()
	card.card_name = str(definition.get("heavy_name" if heavy else "light_name", ""))
	var numeral: String = roman(level)
	if not numeral.is_empty():
		card.card_name += " " + numeral
	card.artwork = BLUE_BACKDROP
	card.artwork_overlay = item_icon(material, level)
	card.description = _description(material, level, heavy)
	card.keyword_ids = _keyword_ids(material, level, heavy)
	card.keyword_tooltip = "\n".join(_rules_for(definition, heavy, level))
	card.energy_cost = 2 if heavy else 1
	card.damage = _damage(material, level, heavy)
	card.sword_material = material
	card.sword_upgrade_level = level
	card.sword_attack_type = "heavy" if heavy else "light"
	_supported_fields(card, material, level, heavy)
	return card
