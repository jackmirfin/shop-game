class_name CardData
extends Resource
## Data container for a single card.
## Holds the display data that the Card scene renders.
##
## It also names the inventory item that a consumed card spends — the first thread of the
## eventual link between cards and the things the player is carrying. A card with no
## consumes_item costs nothing from the inventory.
@export var consumes_item: String = ""

@export var card_name: String = ""
@export var artwork: Texture2D = null
## Optional sprite drawn over artwork, such as a sword, knife, or shield icon.
@export var artwork_overlay: Texture2D = null
## Scale for the artwork overlay relative to its source texture size.
@export var artwork_overlay_scale: float = 1.0
@export var description: String = ""
@export var energy_cost: int = 0
@export var artwork_offset_x: int = 0
## Combat effect data — structured fields, never parsed out of the description.
@export var damage: int = 0
@export var block: int = 0
@export var draw_amount: int = 0
@export var heal_amount: int = 0
## Weak stacks applied to the enemy (a duration: one weakened attack per stack).
@export var weak: int = 0
## Consume-on-play: the card goes to the Consumed pile instead of the discard.
@export var consume: bool = false
## Runtime sword identity and future combat-effect metadata.
@export var sword_material: String = ""
@export var sword_upgrade_level: int = -1
@export var sword_attack_type: String = ""
@export var sword_effects: Dictionary = {}
## Structured runtime combat operations for generated sword cards.
@export var combat_actions: Array[Dictionary] = []
## Keyword ids shown on the card and expanded in its hover tooltip.
@export var keyword_ids: Array[String] = []
@export var keyword_values: Dictionary = {}
@export_multiline var keyword_tooltip: String = ""
@export var rarity: String = "common"
@export var card_type: String = "skill"
@export var temporary_combat: bool = false
