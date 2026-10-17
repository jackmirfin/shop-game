class_name CombatTest
extends Control
## Minimal standalone combat slice, built from the card_hand_test reference.
##
## Player: 8/8 HP, 3 energy per turn, draws 4. One placeholder enemy: 12/12 HP that
## cycles a shuffled bag of three intents (Attack 2 / Defend 2 / Attack 1) shown
## above it. Cards are played by dragging them onto the Play Area or with the
## number hotkeys — both go through try_play_card(), which is also the single
## place that spends energy and sends the card to the discard pile.
##
## Effects are read from structured CardData fields (damage / block), never
## parsed from description text. card.tscn / card.gd are untouched.
##
## Not implemented yet: Weak, Consume, Focus, Heavy Swing, inventory, persistent
## HP, world-scene integration.

## --- Public encounter interface --------------------------------------------
## Used by the EncounterManager autoload when this scene is raised over the
## overworld. Opening this scene directly still boots a normal spider battle
## through _ready(), so it stays usable as a standalone test bed.

## Emitted exactly once, after the fight is decided AND its final animation and
## victory/defeat lock have settled.
signal combat_finished(result: int)

enum CombatResult { VICTORY, DEFEAT, RESCUED }

## True when this instance was raised by an encounter rather than opened directly.
var _hosted: bool = false
## Guards the result signal so it can never fire twice.
var _result_emitted: bool = false
## Data passed by the host. Stored for future use; it deliberately does not alter
## stats, deck, intent bag or presentation.
var _encounter_data: Dictionary = {}

const CARD_SCENE: PackedScene = preload("res://card.tscn")
const HIT_EFFECT_SCENE: PackedScene = preload("res://combat/hit_effect.tscn")

const HAND_SIZE: int = 4
const ENERGY_PER_TURN: int = 3
## Largest hand the deck can produce: HAND_SIZE, or 4 - 1 + 2 when Focus draws 2
## after spending itself.
const MAX_HAND_SIZE: int = 5
const PLAYER_MAX_HP: int = 8
const ENEMY_MAX_HP: int = 12
const PLAYER_BACK_POSITION: Vector2 = Vector2(385.0, 670.0)

## --- Enemy intent bag ---
## Each action appears exactly once per bag, in a random order, so the enemy can
## never string two 2-damage attacks together inside one bag. STRENGTHEN and ATTACK_5
## are appended outside that bag: STRENGTHEN is a scheduled/pooled move and ATTACK_5
## is a plain heavy blow, so the default enemy keeps exactly its original three.
enum EnemyAction {
	ATTACK_1,
	ATTACK_2,
	DEFEND_2,
	STRENGTHEN,
	ATTACK_5,
	## A heavier blow than ATTACK_5. Now the bear's 10-damage swing, so the number in the
	## name no longer matches what it deals — these have always been identifiers rather
	## than values (see the note above ENEMY_DEFEND_BLOCK).
	ATTACK_6,
	## The bear's 6-damage swing.
	ATTACK_7,
	## A light blow that also leaves the PLAYER Weakened (the bear's 2 + 2 Weak).
	ATTACK_WEAK,
	## A lighter guard than DEFEND_2 (the skeleton's 3).
	DEFEND_3,
}
const ENEMY_INTENT_BAG: Array[int] = [EnemyAction.ATTACK_2, EnemyAction.DEFEND_2, EnemyAction.ATTACK_1]
## Block granted by the Defend action. Enemy damage/block is doubled relative to
## the original tuning; the enum names (ATTACK_1/ATTACK_2/DEFEND_2) are kept as
## identifiers — the live numbers are the ones below and in _intent_attack_damage().
const ENEMY_DEFEND_BLOCK: int = 4
## The enemy's intent icons. Attack.png is a plain strike; Attack_Debuff.png is a strike
## that also leaves a debuff on the player, so the extra effect is still disclosed even
## though the readout shows only the damage.
const TEX_INTENT_ATTACK: Texture2D = preload("res://assets/Characters/Enemies/Attack.png")
const TEX_INTENT_ATTACK_DEBUFF: Texture2D = preload("res://assets/Characters/Enemies/Attack_Debuff.png")
const TEX_INTENT_DEFEND: Texture2D = preload("res://assets/Combat/BlockIntent.png")
## Shown over the player when a Focus-type effect actually draws cards.
const TEX_FOCUS_EYE: Texture2D = preload("res://assets/Combat/FocusEye.png")
## Impact flashes: Hit when health was actually lost, Blocked when the attack was
## absorbed entirely by Block (health untouched, Block not broken).

## --- Optional enemy capability: Flight ---
## Flight is NEVER inferred from artwork, names, animations or UI text: it exists
## only when an encounter configuration enables it, so the ground spider — and
## every other enemy — is completely unaffected by its presence here.
enum FlightState { NONE, AIRBORNE, GROUNDED_STUNNED, GROUNDED_RECOVERY }
## Damage typing exists so Flight can ignore Poison later without redesigning the
## rule. Poison itself is not implemented in this pass.
enum DamageType { NORMAL, POISON }
## Defaults for an unconfigured enemy: no Flight at all.
const ENEMY_HAS_FLIGHT: bool = false
const ENEMY_MAX_FLIGHT: int = 3
## Status artwork: an icon with a single stack number beside it.
const TEX_STATUS_FLYING: Texture2D = preload("res://assets/Combat/FlyingStatus.png")
const TEX_STATUS_WEAK: Texture2D = preload("res://assets/Combat/WeakenedStatus.png")
const TEX_STATUS_STRENGTH: Texture2D = preload("res://assets/Combat/StrengthStatus.png")
const STATUS_ICON_SCALE: float = 2.0        # 32 px art -> 64 px
## The hover tooltip's text size, between the status numbers and the intent readout.
const TOOLTIP_FONT: int = 26
const STATUS_FONT: int = 36
## State words ("Stunned" / "Grounded") are drawn smaller than the stack numbers.
const STATUS_WORD_FONT: int = 24
## The intent readout uses its authored size for a plain total, and a slightly
## smaller size for the taller hit-count form ("2x1"), so both sit in the same space.
const INTENT_FONT: int = 43
const INTENT_MULTI_FONT: int = 35
const STATUS_ICON_GAP: float = 10.0
const STATUS_ROW_HEIGHT: float = 64.0
## The player's own sprite, used for the strike that answers an attack card. It comes
## from the player's scene, so the fight plays the same animations the overworld does.
const PLAYER_SCENE: String = "res://scenes/player.tscn"
## The player's rest pose in the fight: the rear view, which is the bust the fight has
## always shown. An attack card plays the strike that belongs with it.
const PLAYER_IDLE_ANIM: StringName = &"idle_up"
const PLAYER_ATTACK_ANIM: StringName = &"attack_up"
## Flight feedback. How far the enemy falls is defined by the encounter's hover
## offset; every drop returns to exactly the grounded position and every takeoff to
## exactly the airborne one, so repeated cycles can never drift.
const KNOCKDOWN_TIME: float = 0.16
const TAKEOFF_TIME: float = 0.16
const FLIGHT_PULSE_TIME: float = 0.14
## The action display draws an attack or defend icon at its authored scale. Actions
## that are manoeuvres rather than blows — taking off, gaining Strength — are drawn
## smaller and with no number beside them, since they have no damage figure.
const INTENT_ICON_SCALE: float = 4.0
const FLIGHT_INTENT_SCALE: float = 3.0
const STRENGTH_INTENT_SCALE: float = 2.6
## Enemy artwork metrics used to find the enemy's visible centre. A configured
## encounter that supplies different artwork has these measured from it instead.
const ENEMY_TEX_HALF: Vector2 = Vector2(64, 64)
## The default combat enemy: the ground spider. Its animations are reused from its own
## overworld scene, exactly as every other enemy's are.
const DEFAULT_ENEMY_SCENE: String = "res://scenes/enemies/spider.tscn"

## Integer display scale for the End Turn button artwork (64 px canvas -> 384 px).
const END_TURN_ART_SCALE: int = 6

## The font card.tscn uses, reused for every piece of combat UI text.
var ui_font: FontFile = preload("res://assets/Fonts/cardfont.ttf")

## --- Status bar artwork (measured from the assets) ---
## Frame canvas 32x16, hollow at texture x 7..28 / y 7..8.
## Interior canvas 32x12, opaque strip at texture x 7..28 / y 5..6, so the
## interior is drawn 2 source pixels lower than the frame.
const TEX_HEALTH_BAR: Texture2D = preload("res://assets/Combat/HealthBar.png")
const TEX_HEALTH_FILL: Texture2D = preload("res://assets/Combat/HealthBarInterior.png")
const TEX_BLOCK_BAR: Texture2D = preload("res://assets/Combat/BlockBar.png")
const TEX_BLOCK_FILL: Texture2D = preload("res://assets/Combat/BlockBarInterior.png")
## Each bar carries its own integer scale, so the player's bar reads slightly
## larger than the enemy's and the two combatants sit at different visual
## distances. Every frame / interior / clip figure is derived from the bar's own
## scale, so the two never have to agree.
const PLAYER_BAR_SCALE: int = 9
const ENEMY_BAR_SCALE: int = 7
## Largest whole-pixel number size that sits comfortably inside each emblem.
const PLAYER_BAR_FONT: int = 52
const ENEMY_BAR_FONT: int = 43
const BAR_INTERIOR_DROP: int = 2
const BAR_FILL_X: int = 7
const BAR_FILL_W: int = 22
const BAR_CANVAS: Vector2 = Vector2(32, 16)
const BAR_INTERIOR_CANVAS: Vector2 = Vector2(32, 12)
## Both bars use the SAME normal (non-mirrored) orientation: each origin is the
## bar's LEFT edge and the artwork's visible rect is origin + (scale, 4*scale)
## with size (29*scale, 8*scale) — so the visible centre is origin +
## (15.5*scale, 8*scale): (139.5, 72) for the player, (108.5, 56) for the enemy.
##
## Player (9x): the visible centre (385.5, 432) is the horizontal centre of the
## rear-view bust's head/upper-body column — PlayerBack sits at x 385 because its
## 27 px canvas centre and its measured head/shoulder centre are the same column.
## The visible bottom (468) floats 22 px above the bust's highest pixel (490).
## Enemy (7x): the visible centre (807.5, 304) is the centre of the spider's head
## and upper thorax (source columns 44..77 of the 128 px sprite at 8.4x, measured
## while ignoring the splayed legs), and the visible bottom (332) floats 20 px
## above the spider's highest meaningful pixel (352).
const BAR_PLAYER_ORIGIN: Vector2 = Vector2(246, 360)
const BAR_ENEMY_ORIGIN: Vector2 = Vector2(699, 248)

## Matches the Card's offset inside the original CardSlot.
const CARD_OFFSET: Vector2 = Vector2(-12, 0)

## --- Overlapping hand layout (all values are whole pixels) ---
## Horizontal distance between card origins at rest.
const STEP_X: float = 116.0
## Visible top edge of a resting card, preserved from the existing rendered hand position.
const REST_FACE_TOP: float = 510.0
## Visible top edge of a hovered card, preserved from the existing raised position.
const HOVER_FACE_TOP: float = 335.0
## How far the neighbours slide aside while one card is raised.
const HOVER_PUSH: float = 70.0
## Raise / lower transition time, in seconds.
const HOVER_TIME: float = 0.15

## --- Drag release rules ---
## Minimum pointer travel from the grab point before a release outside the hand
## may play the card, so a click or hand jitter can never play one.
const MIN_DRAG_DISTANCE: float = 28.0
## Forgiving padding around the RESTING hand that counts as "returned to hand".
const HAND_RETURN_PAD_X: float = 28.0
const HAND_RETURN_PAD_TOP: float = 20.0

## --- Combat feedback / animation (timings in seconds, distances in pixels) ---
## Played-card travel.
const CARD_TRAVEL_TIME: float = 0.18
const CARD_FADE_TIME: float = 0.10
## How far short of the enemy's visible centre a played attack card stops.
const CARD_STOP_SHORT: float = 64.0
## Height above the player's head where a Block card stops.
const CARD_PLAYER_LIFT: float = 40.0
## Hit reaction.
const HIT_TINT_TIME: float = 0.07
const HIT_RECOIL_TIME: float = 0.12
const HIT_RETURN_TIME: float = 0.12
const ENEMY_RECOIL: float = 18.0
const PLAYER_RECOIL: float = 12.0
## Enemy lunge. Snappy so the strike reads as a sudden jab: 30 px covered in
## 0.05 s forward, 0.06 s back. The forward move accelerates INTO the hit (see
## _enemy_attack), which is what gives the strike its weight.
const ENEMY_LUNGE: float = 30.0
const LUNGE_TIME: float = 0.05
const LUNGE_RETURN_TIME: float = 0.06
const LUNGE_HIT_PAUSE: float = 0.05
## The four strikes of a multi-hit flurry. Each is a distinct lunge — different
## reach, arc and timing — so four consecutive attacks read as a flurry instead of
## the same jab repeated. Offsets are whole pixels, relative to the enemy's current
## position, and negative x lunges toward the player.
const ATTACK_VARIANTS: Array[Dictionary] = [
	{"offset": Vector2(-30, 0), "time": 0.05, "back": 0.06},
	{"offset": Vector2(-36, -8), "time": 0.045, "back": 0.055},
	{"offset": Vector2(-26, 8), "time": 0.04, "back": 0.05},
	{"offset": Vector2(-40, 0), "time": 0.06, "back": 0.07},
]
## Pulses.
const INTENT_PULSE_TIME: float = 0.19
const TURN_PULSE_TIME: float = 0.18
const BAR_PULSE_TIME: float = 0.16
## HP fill catch-up after an impact.
const FILL_TWEEN_TIME: float = 0.19
## Floating values.
const FLOAT_RISE: float = 38.0
const FLOAT_TIME: float = 0.5
const FLOAT_FONT: int = 42
## Temporary shield effect.
const SHIELD_SCALE: int = 4
const SHIELD_RISE: float = 12.0
## Effect icons reuse the exact 4x the enemy intent icons are displayed at.
const EFFECT_ICON_SCALE: int = 4
## Hit / Blocked impact flashes: a short, punchy pop that frees itself.
const IMPACT_FADE_IN: float = 0.04
const IMPACT_HOLD: float = 0.15
const IMPACT_FADE_OUT: float = 0.11
const IMPACT_RISE: float = 10.0
## How far above a combatant's point the impact icon sits. The enemy's burst reads
## best a little above its body centre; the player's bust is tall and sits mostly
## behind the hand, so its flash is dropped BELOW the point (a negative lift) to
## land on the head/body rather than floating above it.
const IMPACT_LIFT: float = 30.0
const IMPACT_LIFT_PLAYER: float = -44.0
## Each flash is rotated by a random angle in this band, so no two hits look
## identical while the icon stays upright enough to read.
const IMPACT_ROTATION_DEG: float = 28.0
## Drawn cards dealt in from the Draw pile. Brisk: the flight is still long enough
## to read as a card flying out of the pile and growing into place, while the
## stagger stays tight so a full hand deals almost instantly.
const DEAL_TIME: float = 0.15
const DEAL_STAGGER: float = 0.035
## A dealt card starts at this fraction of its authored size, tucked in behind the
## Draw pile icon, and grows to full size as it travels into the hand.
const DEAL_START_SCALE: float = 0.18
## Kept well under DEAL_TIME so the card is opaque for most of its flight.
const DEAL_FADE_IN: float = 0.07
## Hit-flash tint (bright, so it reads on the dark artwork).
const TINT_HIT: Color = Color(1.8, 0.55, 0.55, 1)
const COLOUR_DAMAGE: Color = Color(1.0, 0.62, 0.55, 1)
const COLOUR_BLOCK: Color = Color(0.72, 0.86, 1.0, 1)
## The spider artwork's meaningful opaque bounds inside its 128x128 source, used
## only to locate its visible head/body for animation targets.
const SPIDER_BBOX_POS: Vector2 = Vector2(44, 59)
const SPIDER_BBOX_SIZE: Vector2 = Vector2(35, 25)

## Temporary combat deck — test data only (11 cards): 4 Long Stick, 4 Bark Shield,
## 1 Focus, 1 Heavy Swing, 1 Throw Stone. A fixed starting deck, recreated each run
## (this is not persistent inventory).
const DECK_PATHS: Array[String] = [
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/focus.tres",
	"res://resources/cards/heavy_swing.tres",
	"res://resources/cards/throw_stone.tres",
]

enum State { ACTIVE, VICTORY, DEFEAT, RESCUED }

@onready var _hand_container: Control = $HandContainer
@onready var _energy_label: Label = $EnergyLabel
@onready var _intent_label: Label = $IntentLabel
@onready var _feedback_label: Label = $FeedbackLabel
@onready var _result_label: Label = $ResultLabel
@onready var _end_turn_button: Button = $EndTurnButton
@onready var _play_area: Control = $PlayArea
@onready var _intent_icon: Sprite2D = $AttackIntent
## A dark silhouette drawn just behind the action icon, so the icon stays legible over a
## large or similarly coloured enemy.
var _intent_icon_backing: Sprite2D = null
@onready var _end_turn_art: TextureRect = $EndTurnButton/EndTurnArt
@onready var _enemy_sprite: AnimatedSprite2D = $Enemy
@onready var _background: TextureRect = $Background
@onready var _draw_count_label: Label = $DrawCountLabel
@onready var _discard_count_label: Label = $DiscardCountLabel
@onready var _turn_label: Label = $TurnLabel
@onready var _turn_counter_art: Control = $TurnCounter
@onready var _player_sprite_node: AnimatedSprite2D = $PlayerBack
@onready var _effects: Control = $EffectsLayer
## Impact flashes draw ABOVE the hand, so a hit low on the player is never hidden
## behind the cards. Dealt-card copies stay on _effects, behind the hand.
@onready var _front_effects: Control = $FrontEffects

var _draw_pile: Array[CardData] = []
var _hand: Array[CardData] = []
var _discard_pile: Array[CardData] = []
## Cards discarded by Aquamarine Heavy that return on the next reshuffle.
var _retained_next_shuffle: Array[CardData] = []
## Cards removed from the fight by "Consume" — never drawn or reshuffled again.
var _consumed_pile: Array[CardData] = []

## Health. Carried in from the Inventory autoload in _ready and handed back when the fight
## is decided, so it survives from one battle to the next instead of resetting.
var _player_hp: int = PLAYER_MAX_HP
var _player_block: int = 0
var _preserve_block: int = 0
var _next_attack_cost_reduction: int = 0
var _double_next_bleed: bool = false
var _energy: int = ENERGY_PER_TURN
var _cards_played_this_turn: int = 0
var _crown_used: bool = false
var _talisman_used: bool = false
var _player_intangible: bool = false
var _enemy_hp: int = ENEMY_MAX_HP
## This enemy's own maximum HP. Encounters may raise or lower it (the bear has 20, the
## skeleton 14); the default keeps the original 12.
var _enemy_max_hp: int = ENEMY_MAX_HP
## The PLAYER's own Weak, in turns. While it lasts the player's attacks are halved and
## one stack is spent per attack — exactly the rule the enemy's Weak follows. Only an
## enemy move that says so applies it (the bear's 2 + 2 Weak).
var _player_weak: int = 0
## Enemy Block granted by the Defend action; cleared at the start of each enemy turn.
var _enemy_block: int = 0
## Fight state: remaining weakened enemy attacks (never stored on CardData).
var _enemy_weak: int = 0
## Strength: each stack adds +1 damage to the enemy's attacks. It is part of the blow
## itself, so it is added BEFORE Weak halves the total.
var _enemy_strength: int = 0
## Sword status stacks on the enemy. These are explicit combat state, never inferred from
## card description text.
var _enemy_status: Dictionary = {}
var _fracture_bonus_pending: int = 0
var _fracture_draw_pending: bool = false
var _doom_activation_damage: int = 5
var _create_soul_slash_on_doom: bool = false
var _activate_drowsy_on_enemy_turn: bool = false
var _preserve_weak_on_poison: bool = false
var _temporary_costs: Dictionary = {}
var _temporary_damage_bonuses: Dictionary = {}
## Player-side sword statuses and temporary defenses.
var _player_status: Dictionary = {}
## Per-sword counters for every-second/third-hit and cycling effects.
var _sword_counters: Dictionary = {}
## Visual impacts are queued by the authoritative damage/status paths and played once
## after state resolution; no effect callback mutates gameplay.
var _pending_impacts: Array[Dictionary] = []
var _active_hit_effects: Array[HitEffect] = []
## The turn number on which this enemy takes its scheduled Strength move (0 = never).
var _strengthen_on_turn: int = 0
var _group_sprite_y: float = 463.0
var _enemy_hud_y_offset: float = 0.0
var _group_health_bar_y_offset: float = 0.0
## Shuffled intent bag and the action currently on display.
var _intent_bag: Array[int] = []
var _current_intent: int = EnemyAction.ATTACK_1
var _last_intent: int = -1
var _player_bar: StatusBar = null
var _enemy_bar: StatusBar = null
var _enemy_weak_label: Label = null
var _state: State = State.ACTIVE

## Which of this enemy's attack actions split into several quick strikes of 1 instead
## of one bigger blow (so ATTACK_2 can be a 4x1 flurry). Empty for everything else, so
## a normal enemy always resolves its attack as a single hit.
var _multi_hit_actions: Array[int] = []
## The actions this enemy may choose from, when an encounter supplies its own moveset.
## Empty means "use the default shuffled intent bag".
var _intent_pool: Array[int] = []
## Enabled only by an encounter that has Erdon available. If the displayed enemy
## attack would kill the player, Erdon intervenes before that attack resolves.
var _rescue_intervention: bool = false

## --- Flight state (independent of HP, Block, Weak, intent and animation) ---
var _has_flight: bool = ENEMY_HAS_FLIGHT
var _max_flight: int = ENEMY_MAX_FLIGHT
var _flight: int = 0
var _flight_state = FlightState.NONE
## Status widgets. Hidden entirely for enemies without Flight.
var _flight_icon: TextureRect = null
var _flight_label: Label = null
var _weak_icon: TextureRect = null
var _strength_icon: TextureRect = null
var _strength_label: Label = null
## The PLAYER's own status row, above their bar. Weak is the only status the player can
## currently carry, so it is the only row: the same icon-plus-number form as the
## enemy's rows, and likewise hidden entirely when it has no stacks.
var _player_weak_icon: TextureRect = null
var _player_weak_label: Label = null
## Per-animation scale multipliers for the enemy's own artwork, keyed by animation name.
## Some sheets draw different animations at different sizes, so an encounter can correct
## for that without touching the sprite frames. An animation with no entry keeps exactly
## the enemy's base scale.
var _enemy_anim_scales: Dictionary = {}
## Identifies the current player swing, so a second attack card restarts the animation
## rather than being cut short by the previous swing's restore-to-rest timer.
var _player_attack_token: int = 0
## The shared hover tooltip: one label, shown while the mouse is over an intent or status
## icon, saying in words what that icon means.
var _tooltip: Label = null
## The invisible hover target over the intent icon. The icon itself is a Sprite2D and
## cannot take mouse input, so this Control stands in for it.
var _intent_hover: Control = null
## Enemy artwork metrics for the configured enemy (spider by default), so the
## feedback helpers can find its visible centre whatever art is in use.
var _enemy_tex_half: Vector2 = ENEMY_TEX_HALF
var _enemy_bbox_pos: Vector2 = SPIDER_BBOX_POS
var _enemy_bbox_size: Vector2 = SPIDER_BBOX_SIZE
## The enemy's own animation set, shared with its overworld scene: the same
## AnimatedSprite2D animations are used on the combat screen. `ground` is a one-frame
## set built from an encounter's grounded artwork (the dazed moth), used while knocked
## down.
var _enemy_frames_air: SpriteFrames = null
var _enemy_frames_ground: SpriteFrames = null
## An animation, inside the enemy's own frames, to play while it is knocked down. Used
## when the enemy has a real dazed animation; the one-frame set above covers enemies
## whose grounded look only exists as a single image.
var _enemy_ground_anim: StringName = &""
## Additional combat sprites for a grouped dungeon encounter. They share the encounter
## state and moveset, while keeping the existing single-enemy combat rules intact.
var _enemy_group_sprites: Array[AnimatedSprite2D] = []
var _enemy_group_rest_positions: Array[Vector2] = []
var _enemy_group_hp: Array[int] = []
var _enemy_group_max_hp: Array[int] = []
var _enemy_group_block: Array[int] = []
var _enemy_group_intents: Array[int] = []
var _enemy_group_last_intents: Array[int] = []
var _enemy_group_bags: Array[Array] = []
var _enemy_group_status: Array[Dictionary] = []
var _enemy_group_weak: Array[int] = []
var _enemy_group_strength: Array[int] = []
var _enemy_group_flight: Array[int] = []
var _enemy_group_flight_state: Array = []
var _enemy_group_drowsy_activated: Array[bool] = []
var _enemy_group_doom_damage: Array[int] = []
var _enemy_group_soul_slash_on_doom: Array[bool] = []
var _enemy_group_bars: Array[Control] = []
var _enemy_group_status_bars: Array[StatusBar] = []
var _enemy_group_intent_labels: Array[Label] = []
var _enemy_group_intent_icons: Array[Sprite2D] = []
var _enemy_group_status_labels: Array[Label] = []
var _enemy_group_flight_icons: Array[TextureRect] = []
var _enemy_group_weak_icons: Array[TextureRect] = []
var _enemy_group_strength_icons: Array[TextureRect] = []
var _enemy_group_flight_counts: Array[Label] = []
var _enemy_group_weak_counts: Array[Label] = []
var _enemy_group_strength_counts: Array[Label] = []
var _selected_enemy: int = 0
## Which of the enemy's animations to play for each situation, taken from its own
## animation tables. The combat enemy faces the player front-on, so the "down" entry is
## used: the spider plays Idle and Attack, the moth plays down and attack_down. These
## defaults cover enemies whose configuration does not list its tables.
var _enemy_idle_anim: StringName = &"Idle"
var _enemy_attack_anim: StringName = &"Attack"
var _enemy_death_anim: StringName = &"Death"
## The enemy's resting position: where the GROUNDED art sits, and the baseline the
## airborne hover offset is measured from. Captured once so knockdown/takeoff cycles
## always return to exactly the same place.
var _enemy_rest_position: Vector2 = Vector2.ZERO
var _enemy_rest_scale: Vector2 = Vector2.ONE
## Whole-pixel hover offset used while AIRBORNE, so the flying art can sit higher
## than the grounded one. Left at zero for enemies without Flight, which therefore
## keeps exactly the position it always had.
var _enemy_air_offset: Vector2 = Vector2.ZERO
## Player turn number — the single source of truth for the Turn Counter HUD.
## Starts at 1 and advances exactly once each time a new player turn begins,
## never from card plays, Focus draws or reshuffles.
var turn_number: int = 1

var _feedback_token: int = 0
var _end_turn_art_base: Vector2 = Vector2.ZERO
var _end_turn_hover: bool = false
## Overlapping hand state (one entry per card, in hand order).
var _slots: Array[Control] = []
var _slot_x: Array[float] = []
var _slot_y: Array[float] = []
var _target_x: Array[float] = []
var _target_y: Array[float] = []
var _hover_index: int = -1
## The card's visible face relative to its slot origin (derived from the Frame
## texture's opaque pixels so drag handles match exactly what is drawn).
var _card_face_rect: Rect2 = Rect2()
var _card_face_ready: bool = false
## The card's authored template scale, captured when its face was first measured.
var _card_base_scale: float = 3.0
## The Card hidden because it is currently being dragged.
var _drag_source_card: Control = null
## Hand slot index of the card currently travelling, so a release can play it.
var _drag_hand_index: int = -1
## Where the pointer was when the drag began (for the minimum-distance check).
var _drag_start_mouse: Vector2 = Vector2.ZERO
## True when the Drop Zone already routed this release through try_play_card().
var _drag_drop_consumed: bool = false
## True while a played-card animation or an enemy action is resolving. While busy
## the player cannot start a drag, fire a hotkey, or press End Turn; hover may
## still settle, but it can no longer lead to gameplay.
var animation_busy: bool = false
## True while drawn cards are still flying from the Draw pile into the hand, so a
## half-dealt hand cannot be dragged from.
var _dealing: bool = false
var _tutorial: CombatTutorial = null
var _tutorial_active: bool = false


## Invisible hit area laid over a hand card. Starts a drag carrying its index.
class CardDragHandle extends Control:
	var test_root: Node
	var hand_index: int = -1
	var card_node: Control
	## Where the card's visible face starts relative to the Card node's origin.
	var face_offset: Vector2 = Vector2.ZERO

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _on_mouse_entered() -> void:
		if test_root != null and test_root.has_method("_set_card_cursor_active"):
			test_root._set_card_cursor_active(true)

	func _on_mouse_exited() -> void:
		if test_root != null and test_root.has_method("_set_card_cursor_active"):
			test_root._set_card_cursor_active(false)

	func _get_drag_data(at_position: Vector2) -> Variant:
		if test_root == null or hand_index < 0:
			return null
		if card_node:
			# The drag preview's root is placed at the mouse pointer, so wrap the
			# card and shift it by the grab point measured from the card's own
			# origin: that keeps the grabbed pixel under the cursor.
			var wrapper := Control.new()
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var preview := card_node.duplicate() as Control
			if preview:
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
				preview.modulate = Color(1, 1, 1, 0.85)
				wrapper.add_child(preview)
				preview.position = -(face_offset + at_position)
			set_drag_preview(wrapper)
			if test_root.has_method("_begin_drag"):
				test_root._begin_drag(self)
		return {"type": "card", "index": hand_index}


## Drop target that covers the Play Area.
class PlayDropZone extends Control:
	var test_root: Node

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "card"

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if test_root:
			# Tell the drag-end evaluation this release is already accounted for,
			# so the same drag can never be played twice.
			if test_root.has_method("_note_drop_consumed"):
				test_root._note_drop_consumed()
			var target: int = test_root._enemy_target_at(at_position) \
				if test_root.has_method("_enemy_target_at") else -1
			test_root._request_play_card(int(data.get("index", -1)), target)


## One character's status display: a frame whose HP interior is cropped to the
## current HP, plus the HP and Block text. When Block > 0 the Block artwork
## replaces the Health artwork — it never extends the HP fill.
class StatusBar:
	var root: Control
	var frame: TextureRect
	var clip: Control
	var interior: TextureRect
	var hp_label: Label
	var block_label: Label
	## This bar's own integer display scale (PLAYER_BAR_SCALE / ENEMY_BAR_SCALE).
	var bar_scale: int = 8
	## Live HP-fill Tween, so a new impact can finish/kill the previous one safely.
	var fill_tween: Tween = null
	## Width the running fill Tween is heading for; a redundant re-sync that asks
	## for the same width leaves the catch-up running instead of snapping it.
	var fill_target_w: float = -1.0
	## Absolute (global) centres of the heart emblem, the shield emblem and the
	## bar interior. The shield artwork reaches one source row lower than the
	## heart, so its number is centred on its own column.
	var emblem_centre: Vector2 = Vector2.ZERO
	var block_centre: Vector2 = Vector2.ZERO
	var interior_centre: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("combat")
	# The combat enemy plays the SAME AnimatedSprite2D animations as its overworld
	# counterpart. With no encounter configuration that is the ground spider, exactly
	# as it always was.
	ui_font.multichannel_signed_distance_field = true
	ui_font.msdf_pixel_range = 16
	ui_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ui_font.oversampling = 0.0
	ui_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_use_enemy_scene(DEFAULT_ENEMY_SCENE, {})
	# The enemy's authored resting transform. Every knockdown/takeoff cycle returns
	# here exactly, so repeated cycles cannot drift by a single pixel.
	_enemy_rest_position = _enemy_sprite.position
	_enemy_rest_scale = _enemy_sprite.scale
	_build_status_bars()
	_apply_ui_font(self)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_create_drop_zone()
	_setup_end_turn_art()
	_build_deck()
	_setup_player_sprite()
	# Health is carried between fights: the player begins from wherever the last one left
	# them rather than from full. _emit_result_if_decided() hands it back afterwards.
	_player_hp = Inventory.player_hp
	_draw_intent()
	_sync_selected_to_group()
	_energy = ENERGY_PER_TURN
	draw_cards(HAND_SIZE)
	_set_result("")
	_update_hud()


## Builds both status bars from the same construction, each at its own integer
## scale (player 9x, enemy 7x). Both use the normal, non-mirrored orientation and
## the emblem sits on the left of each. Text lives OUTSIDE `root`.
func _build_status_bars() -> void:
	_player_bar = _make_status_bar("PlayerStatus", BAR_PLAYER_ORIGIN, PLAYER_BAR_SCALE, PLAYER_BAR_FONT)
	_enemy_bar = _make_status_bar("EnemyStatus", BAR_ENEMY_ORIGIN, ENEMY_BAR_SCALE, ENEMY_BAR_FONT)

	# Every inset below is expressed in SOURCE pixels and multiplied by that
	# bar's own scale, so the two bars stay correct at different sizes.
	for bar in [_player_bar, _enemy_bar]:
		var s := float(bar.bar_scale)
		var o: Vector2 = (bar.root as Control).position
		# Emblem centres are read from the emblem artwork itself, not from the
		# 32x16 texture or from the frame's wider opaque bounds: the heart spans
		# source x 1..9 / y 4..11 and the shield source x 1..9 / y 4..12, so their
		# own centres are (5.5, 8.0) and (5.5, 8.5) source pixels — the shield
		# reaches one row lower, which is why Block text has its own centre.
		var emblem_y: float = 8.0 * s
		bar.emblem_centre = o + Vector2(5.5 * s, emblem_y)
		bar.block_centre = o + Vector2(5.5 * s, emblem_y + 0.5 * s)
		# The HP number in Block mode sits over the FILL region (texture x 7..28),
		# not the frame's wider opaque bounds.
		bar.interior_centre = o + Vector2((float(BAR_FILL_X) + float(BAR_FILL_W) * 0.5) * s, emblem_y)
		# The number box grows with the emblem, so the digits stay optically
		# centred inside it at either scale.
		var box: float = 10.0 * s
		bar.hp_label.size = Vector2(box, box)
		bar.block_label.size = Vector2(box, box)

	_enemy_weak_label = Label.new()
	_enemy_weak_label.name = "EnemyWeakLabel"
	_enemy_weak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_weak_label.add_theme_font_override("font", ui_font)
	_enemy_weak_label.add_theme_font_size_override("font_size", STATUS_FONT)
	_enemy_weak_label.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	_enemy_weak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_enemy_weak_label.add_theme_constant_override("outline_size", 7)
	# The Weak and Flight readouts belong to the ENEMY bar, so they follow that
	# bar's scale. Each is an icon with a single stack number beside it.
	var es := float(ENEMY_BAR_SCALE)
	var vis_x0 := 1.0 * es                    # opaque frame left
	var status_x: float = BAR_ENEMY_ORIGIN.x + vis_x0
	# The PLAYER's own status row, above their bar, mirroring the enemy's. Weak is the
	# only status the player can currently carry, so it is the only row: the same icon
	# with a single stack number beside it, hidden entirely when it has no stacks.
	var player_status_x: float = BAR_PLAYER_ORIGIN.x + 1.0 * float(PLAYER_BAR_SCALE)
	var player_weak_y: float = BAR_PLAYER_ORIGIN.y - STATUS_ROW_HEIGHT - 10.0
	_player_weak_icon = _make_status_icon(TEX_STATUS_WEAK, Vector2(player_status_x, player_weak_y))
	add_child(_player_weak_icon)
	_player_weak_label = _make_status_label("PlayerWeakLabel", Color(0.85, 0.8, 1.0),
		Vector2(player_status_x + STATUS_ROW_HEIGHT + STATUS_ICON_GAP, player_weak_y + 18.0))
	add_child(_player_weak_label)
	# The status rows stack ABOVE the enemy bar, clear of the bar, of each other and
	# of the intent display to the right. Nearest the bar is Flight, then Weak, then
	# Strength on top. Each row is only ever visible when it actually has stacks.
	var flight_y: float = BAR_ENEMY_ORIGIN.y - STATUS_ROW_HEIGHT - 10.0
	var weak_y: float = flight_y - STATUS_ROW_HEIGHT - 2.0
	var strength_y: float = weak_y - STATUS_ROW_HEIGHT - 2.0
	_strength_icon = _make_status_icon(TEX_STATUS_STRENGTH, Vector2(status_x, strength_y))
	add_child(_strength_icon)
	_strength_label = _make_status_label("EnemyStrengthLabel", Color(1.0, 0.78, 0.62),
		Vector2(status_x + STATUS_ROW_HEIGHT + STATUS_ICON_GAP, strength_y + 18.0))
	add_child(_strength_label)
	_weak_icon = _make_status_icon(TEX_STATUS_WEAK, Vector2(status_x, weak_y))
	add_child(_weak_icon)
	_enemy_weak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_enemy_weak_label.position = Vector2(status_x + STATUS_ROW_HEIGHT + STATUS_ICON_GAP, weak_y + 18.0)
	_enemy_weak_label.size = Vector2(90.0, 30.0)
	add_child(_enemy_weak_label)

	_flight_icon = _make_status_icon(TEX_STATUS_FLYING, Vector2(status_x, flight_y))
	add_child(_flight_icon)
	_flight_label = Label.new()
	_flight_label.name = "EnemyFlightLabel"
	_flight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flight_label.add_theme_font_override("font", ui_font)
	_flight_label.add_theme_font_size_override("font_size", STATUS_FONT)
	_flight_label.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	_flight_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_flight_label.add_theme_constant_override("outline_size", 7)
	_flight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_flight_label.position = Vector2(status_x + STATUS_ROW_HEIGHT + STATUS_ICON_GAP, flight_y + 18.0)
	_flight_label.size = Vector2(240.0, 30.0)
	add_child(_flight_label)

	# A dark silhouette sits just behind the action icon so it stays legible over a large
	# or similarly coloured enemy — the moth is brown, and so is the Strength icon.
	_intent_icon_backing = Sprite2D.new()
	_intent_icon_backing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_intent_icon_backing.modulate = Color(0, 0, 0, 0.8)
	_intent_icon_backing.visible = false
	add_child(_intent_icon_backing)

	# Hover tooltips. The intent icon is a Sprite2D and cannot take mouse input, so a
	# transparent Control stands over it; the status icons are Controls already. Each
	# one asks for its text at the moment it is hovered, so the description always
	# matches the live state and can never contradict the icon beside it.
	_intent_hover = Control.new()
	_intent_hover.name = "IntentHover"
	# PASS, not STOP: the control still reports entering and leaving, but events carry on
	# to whatever is underneath, so dragging a card across this area is unaffected.
	_intent_hover.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_intent_hover)
	_intent_hover.mouse_entered.connect(
		func() -> void: _show_tooltip(_intent_tooltip_text(), _intent_hover))
	_intent_hover.mouse_exited.connect(_hide_tooltip)
	_attach_tooltip(_strength_icon, _strength_tooltip_text)
	_attach_tooltip(_weak_icon, _weak_tooltip_text)
	_attach_tooltip(_flight_icon, _flight_tooltip_text)
	_attach_tooltip(_player_weak_icon, _player_weak_tooltip_text)

	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_font_override("font", ui_font)
	_tooltip.add_theme_font_size_override("font_size", TOOLTIP_FONT)
	_tooltip.add_theme_color_override("font_color", Color(1.0, 0.97, 0.86))
	_tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tooltip.add_theme_constant_override("outline_size", 8)
	_tooltip.visible = false
	add_child(_tooltip)

	# The bars are created at runtime, so without this they would be the LAST
	# children of the root and would draw on top of the card hand. The player's
	# bar is slotted directly after the Energy group: that keeps it behind the
	# raised card hand while still drawing it OVER the Energy icon's soft outer
	# glow, which at 8x reaches far enough to wash out the heart emblem and its
	# number otherwise. (The bar clears the solid orb entirely.)
	_place_after(_player_bar.root, _energy_label)
	_place_after(_player_bar.hp_label, _player_bar.root)
	_place_after(_player_bar.block_label, _player_bar.hp_label)
	_place_after(_enemy_bar.root, _enemy_sprite)
	_place_after(_enemy_bar.hp_label, _enemy_bar.root)
	_place_after(_enemy_bar.block_label, _enemy_bar.hp_label)
	_place_after(_intent_icon_backing, _enemy_bar.block_label)
	_place_after(_intent_icon, _intent_icon_backing)
	_place_after(_intent_label, _intent_icon)
	_place_after(_strength_icon, _intent_label)
	_place_after(_strength_label, _strength_icon)
	_place_after(_weak_icon, _strength_label)
	_place_after(_enemy_weak_label, _weak_icon)
	_place_after(_flight_icon, _enemy_weak_label)
	_place_after(_flight_label, _flight_icon)
	# The player's own status row rides directly above the player's bar.
	_place_after(_player_weak_icon, _player_bar.block_label)
	_place_after(_player_weak_label, _player_weak_icon)
	# The tooltip is drawn over everything, including the raised card hand.
	move_child(_tooltip, get_child_count() - 1)


## One 32 px status icon at the shared status scale, mouse-transparent and crisp.
func _make_status_icon(tex: Texture2D, at: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = at.round()
	icon.size = Vector2(32.0, 32.0) * STATUS_ICON_SCALE
	return icon


## One status number label, styled like the other status readouts.
func _make_status_label(node_name: String, colour: Color, at: Vector2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", STATUS_FONT)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = at.round()
	label.size = Vector2(160.0, 30.0)
	return label


## Re-inserts a runtime-created node directly after `anchor` in our child list.
func _place_after(node: Node, anchor: Node) -> void:
	if node.get_parent() == self and anchor.get_parent() == self:
		move_child(node, anchor.get_index() + 1)


# --- Hover tooltips ------------------------------------------------------------
#
# Every intent icon and status badge can be hovered to say in words what it means. The
# text is produced from the SAME state the icon and its number are drawn from, so a
# tooltip can never describe something the icon does not show.

## Makes a Control a tooltip target. The text is asked for on hover, so it is always
## current rather than captured once.
func _attach_tooltip(node: Control, text_source: Callable) -> void:
	if node == null:
		return
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.mouse_entered.connect(func() -> void: _show_tooltip(str(text_source.call()), node))
	node.mouse_exited.connect(_hide_tooltip)


## Shows the shared tooltip near `anchor`, preferring above it and staying on screen.
func _show_tooltip(text: String, anchor: Control) -> void:
	if _tooltip == null or text.is_empty() or anchor == null:
		return
	_tooltip.text = text
	_tooltip.visible = true
	# Measured from its own metrics immediately, so the label lands where it is put in
	# this same frame instead of sitting at a stale size for a frame and then jumping.
	var ext: Vector2 = _tooltip.get_minimum_size()
	_tooltip.size = ext
	var view: Vector2 = get_viewport_rect().size
	var at_x: float = clampf(anchor.global_position.x, 8.0,
		maxf(8.0, view.x - ext.x - 8.0))
	# Tucked right against the icon, above it where there is room and below it otherwise.
	var above: float = anchor.global_position.y - ext.y - 4.0
	var at_y: float = above if above >= 8.0 else anchor.global_position.y + anchor.size.y + 4.0
	at_y = clampf(at_y, 8.0, maxf(8.0, view.y - ext.y - 8.0))
	_tooltip.position = Vector2(at_x, at_y).round()


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


## What the enemy's intent icon means, in words. Kept to the bare fact — what the icon
## is doing — with no explanation of the mechanic behind it.
func _intent_tooltip_text() -> String:
	if _flight_state == FlightState.GROUNDED_RECOVERY:
		return "This enemy is taking off."
	match _current_intent:
		EnemyAction.DEFEND_2, EnemyAction.DEFEND_3:
			return "This enemy intends to defend for %d." % _intent_block_value()
		EnemyAction.STRENGTHEN:
			return "This enemy intends to gain 1 Strength."
	var tail: String = " and apply a debuff" if _intent_player_weak() > 0 else ""
	var hits: int = _intent_hit_count()
	if hits > 1:
		return "This enemy intends to attack for %d damage %d times%s." % [
			_intent_hit_damage(), hits, tail]
	return "This enemy intends to attack for %d damage%s." % [_intent_attack_damage(), tail]


func _strength_tooltip_text() -> String:
	return "This enemy has %d additional strength." % _enemy_strength


func _weak_tooltip_text() -> String:
	return "This enemy is weakened for %d turn%s." % [
		_enemy_weak, "" if _enemy_weak == 1 else "s"]


func _flight_tooltip_text() -> String:
	match _flight_state:
		FlightState.GROUNDED_STUNNED:
			return "This enemy has been knocked out of the air."
		FlightState.GROUNDED_RECOVERY:
			return "This enemy is grounded."
	return "This enemy can fly."


func _player_weak_tooltip_text() -> String:
	return "You are weakened for %d turn%s." % [
		_player_weak, "" if _player_weak == 1 else "s"]


func _make_status_bar(node_name: String, origin: Vector2, bar_scale: int, font_size: int) -> StatusBar:
	var bar := StatusBar.new()
	bar.bar_scale = bar_scale

	bar.root = Control.new()
	bar.root.name = node_name
	bar.root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.root.position = origin
	add_child(bar.root)

	bar.clip = Control.new()
	bar.clip.name = "FillClip"
	bar.clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.clip.clip_contents = true
	bar.clip.position = Vector2(0.0, float(BAR_INTERIOR_DROP * bar_scale))
	bar.clip.size = BAR_INTERIOR_CANVAS * float(bar_scale)
	bar.root.add_child(bar.clip)

	bar.interior = TextureRect.new()
	bar.interior.name = "Interior"
	bar.interior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.interior.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.interior.texture = TEX_HEALTH_FILL
	bar.interior.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	bar.interior.stretch_mode = TextureRect.STRETCH_SCALE
	bar.interior.position = Vector2.ZERO
	bar.interior.size = BAR_INTERIOR_CANVAS * float(bar_scale)
	bar.clip.add_child(bar.interior)

	# The frame is added last so it always draws above the interior.
	bar.frame = TextureRect.new()
	bar.frame.name = "Frame"
	bar.frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.frame.texture = TEX_HEALTH_BAR
	bar.frame.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	bar.frame.stretch_mode = TextureRect.STRETCH_SCALE
	bar.frame.position = Vector2.ZERO
	bar.frame.size = BAR_CANVAS * float(bar_scale)
	bar.root.add_child(bar.frame)

	bar.hp_label = Label.new()
	bar.hp_label.name = node_name + "HP"
	bar.hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.hp_label.add_theme_font_override("font", ui_font)
	bar.hp_label.add_theme_font_size_override("font_size", font_size)
	bar.hp_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	bar.hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bar.hp_label.add_theme_constant_override("outline_size", 5)
	bar.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(bar.hp_label)

	bar.block_label = Label.new()
	bar.block_label.name = node_name + "Block"
	bar.block_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.block_label.add_theme_font_override("font", ui_font)
	bar.block_label.add_theme_font_size_override("font_size", font_size)
	bar.block_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	bar.block_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bar.block_label.add_theme_constant_override("outline_size", 6)
	bar.block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.block_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(bar.block_label)

	return bar


## Health vs Block mode plus the HP fill, in one place for both characters.
## Block only swaps the artwork: the interior still shows hp / max_hp.
func _sync_status_bar(bar: StatusBar, hp: int, max_hp: int, block: int, animate_fill: bool = false) -> void:
	var block_mode: bool = block > 0
	bar.frame.texture = TEX_BLOCK_BAR if block_mode else TEX_HEALTH_BAR
	bar.interior.texture = TEX_BLOCK_FILL if block_mode else TEX_HEALTH_FILL
	var ratio: float = clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	# Clip width comes from THIS bar's scale — roundi(22 * scale * hp / max_hp)
	# plus the 7 * scale emblem/offset region. The interior texture is never
	# resized or stretched, only revealed through the clip.
	var s: float = float(bar.bar_scale)
	var fill_px: int = roundi(float(BAR_FILL_W) * s * ratio)
	var target_w: float = float(BAR_FILL_X) * s + float(fill_px)
	var clip_h: float = BAR_INTERIOR_CANVAS.y * s
	# A fill Tween already running is finished off before a new one starts, so a
	# rapid second hit can never leave the bar between two widths. A redundant
	# re-sync asking for the SAME width (e.g. _check_result straight after
	# _damage_enemy) leaves the running catch-up alone.
	var keep_running: bool = bar.fill_tween != null and bar.fill_tween.is_valid() \
		and not animate_fill and absf(target_w - bar.fill_target_w) < 0.5
	if bar.fill_tween != null and bar.fill_tween.is_valid() and not keep_running:
		bar.fill_tween.kill()
	if keep_running:
		pass  # already heading for exactly this width
	else:
		bar.fill_tween = null
		if animate_fill and absf(bar.clip.size.x - target_w) > 0.5:
			# The HP TEXT below already shows the real value; only the revealed
			# interior width catches up, always through this clip.
			bar.fill_target_w = target_w
			var bar_ref: StatusBar = bar
			bar.fill_tween = create_tween()
			bar.fill_tween.tween_method(
				func(w: float) -> void: bar_ref.clip.size = Vector2(roundf(w), clip_h),
				bar.clip.size.x, target_w, FILL_TWEEN_TIME).set_ease(Tween.EASE_OUT)
		else:
			bar.clip.size = Vector2(target_w, clip_h)
	# Health mode: the HP number sits inside the heart emblem (no "HP" text).
	# Block mode: the Block number takes the emblem and the HP number moves over
	# the interior, so the shield number can never be read as HP.
	bar.hp_label.visible = true
	bar.hp_label.text = str(hp)
	bar.block_label.visible = block_mode
	bar.block_label.text = str(block) if block_mode else ""
	if block_mode:
		bar.block_label.position = (bar.block_centre - bar.block_label.size * 0.5).round()
		bar.hp_label.position = (bar.interior_centre - bar.hp_label.size * 0.5).round()
	else:
		bar.hp_label.position = (bar.emblem_centre - bar.hp_label.size * 0.5).round()


## Every combat label uses the same Determination font as the cards.
func _apply_ui_font(node: Node) -> void:
	if node is Label:
		(node as Label).add_theme_font_override("font", ui_font)
	for child in node.get_children():
		_apply_ui_font(child)


## Fits the End Turn button's clickable area to its artwork's opaque pixels: the
## PNG has a lot of transparent padding, which must not be clickable.
func _setup_end_turn_art() -> void:
	if _end_turn_art.texture:
		var bbox := _texture_alpha_bbox(_end_turn_art.texture)
		_end_turn_art.scale = Vector2(END_TURN_ART_SCALE, END_TURN_ART_SCALE)
		_end_turn_art.position = -bbox.position * float(END_TURN_ART_SCALE)
		# +ONE: _texture_alpha_bbox returns mx-mn, so add the final pixel row/column
		# back so the clickable area covers the artwork's full extent.
		_end_turn_button.size = (bbox.size + Vector2.ONE) * float(END_TURN_ART_SCALE)
		var end_turn_label: Label = _end_turn_button.get_node_or_null("EndTurnLabel") as Label
		if end_turn_label == null:
			end_turn_label = Label.new()
			end_turn_label.name = "EndTurnLabel"
			end_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			end_turn_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			end_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			end_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			end_turn_label.text = "End Turn"
			end_turn_label.add_theme_font_override("font", ui_font)
			end_turn_label.add_theme_font_size_override("font_size", 36)
			end_turn_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.82, 1.0))
			end_turn_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
			end_turn_label.add_theme_constant_override("outline_size", 3)
			_end_turn_button.add_child(end_turn_label)
		_end_turn_art_base = _end_turn_art.position
	_end_turn_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_end_turn_button.mouse_entered.connect(_on_end_turn_hover.bind(true))
	_end_turn_button.mouse_exited.connect(_on_end_turn_hover.bind(false))
	_end_turn_button.button_down.connect(_on_end_turn_down)
	_end_turn_button.button_up.connect(_refresh_end_turn_art)
	_refresh_end_turn_art()


func _on_end_turn_hover(entered: bool) -> void:
	_end_turn_hover = entered
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor != null:
		cursor.set_click_uses_active(not entered)
		if entered:
			cursor.set_ready()
		else:
			cursor.set_idle()
	_refresh_end_turn_art()


## Pressed feedback: shift down one source pixel and darken — no new artwork.
func _on_end_turn_down() -> void:
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor != null:
		cursor.set_ready()
	_end_turn_art.position = _end_turn_art_base + Vector2(0, float(END_TURN_ART_SCALE))
	_end_turn_art.modulate = Color(0.72, 0.72, 0.72, 1)


func _refresh_end_turn_art() -> void:
	_end_turn_art.position = _end_turn_art_base
	if _end_turn_button.disabled:
		_end_turn_art.modulate = Color(0.45, 0.45, 0.45, 0.75)
	elif _end_turn_hover:
		_end_turn_art.modulate = Color(1.2, 1.2, 1.2, 1)
	else:
		_end_turn_art.modulate = Color(1, 1, 1, 1)


func _create_drop_zone() -> void:
	var zone := PlayDropZone.new()
	zone.name = "DropZone"
	zone.test_root = self
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	zone.anchor_right = 1.0
	zone.anchor_bottom = 1.0
	zone.offset_left = 0.0
	zone.offset_top = 0.0
	zone.offset_right = 0.0
	zone.offset_bottom = 0.0
	_play_area.add_child(zone)


## Called by a CardDragHandle when a drag starts: visually empty the source card
## while keeping its slot, so the rest of the hand does not move. Also records
## where the drag began and which slot is travelling, so the release can be
## judged against the resting hand without disturbing it.
func _begin_drag(handle: Node) -> void:
	var drag_handle := handle as CardDragHandle
	if drag_handle:
		_drag_hand_index = drag_handle.hand_index
		_drag_source_card = drag_handle.card_node as Control
	_drag_start_mouse = get_viewport().get_mouse_position()
	_drag_drop_consumed = false
	if _drag_source_card:
		_drag_source_card.visible = false


## Drives the hand: hover selection, the raise/lower animation, and the drag-end
## evaluation once a drag finishes.
func _process(delta: float) -> void:
	if _drag_source_card == null:
		_update_hover()
	elif not get_viewport().gui_is_dragging():
		_finish_drag()
	_animate_slots(delta)


## Drag-end evaluation. Godot's drag/drop only reports releases over a Control
## that accepts the drop, so the real rule — "released inside the viewport but
## outside the hand means play it" — is applied here, from the drag lifecycle
## the HandContainer already runs. Nothing global is added, so no permanent
## full-screen Control can swallow hover, card selection or End Turn input.
##
## The travelling card is restored first, so a rejected play leaves it exactly
## where it was. A release the Drop Zone already routed through try_play_card()
## is skipped, and so is a drag Godot itself cancelled — Escape ends the drag
## while the mouse button is still held.
func _finish_drag() -> void:
	var source: Control = _drag_source_card
	var index: int = _drag_hand_index
	var consumed: bool = _drag_drop_consumed
	_drag_source_card = null
	_drag_hand_index = -1
	_drag_drop_consumed = false
	if is_instance_valid(source):
		source.visible = true
	if consumed or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var view: Vector2 = get_viewport_rect().size
	var at: Vector2 = get_viewport().get_mouse_position()
	if at.x < 0.0 or at.y < 0.0 or at.x >= view.x or at.y >= view.y:
		return  # Released outside the window: cancel safely.
	if _hand_return_rect().has_point(at):
		return  # Returned to the hand: cancel, keeping the card's own slot.
	if at.distance_to(_drag_start_mouse) < MIN_DRAG_DISTANCE:
		return  # A click or jitter, not a deliberate drag.
	# The single animated play path, shared with the drop zone and the hotkeys. A
	# play that cannot happen (not enough energy) reports through the usual
	# feedback and leaves the card, its slot and the energy untouched.
	_request_play_card(index, _enemy_target_at(at))


func _enemy_target_at(at: Vector2) -> int:
	if _enemy_group_hp.is_empty():
		return -1
	for index: int in range(_enemy_group_hp.size()):
		var sprite: AnimatedSprite2D = _enemy_sprite if index == 0 else _enemy_group_sprites[index - 1]
		if _enemy_group_hp[index] > 0 and Rect2(sprite.position - Vector2(90.0, 110.0),
				Vector2(180.0, 220.0)).has_point(at):
			return index
	return -1


## The resting hand's return/cancel rectangle: a forgiving band around where the
## cards actually REST — never the raised hover positions, which travel with the
## pointer. Rebuilt from the live hand size, so four-card hands, five-card Focus
## hands, hands shrunk by plays and a hand holding a drag placeholder all get the
## right region.
func _hand_return_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	var count: int = _slots.size()
	if count <= 0 or not _card_face_ready:
		return Rect2(0.0, view.y, 0.0, 0.0)
	var face: Rect2 = _card_face_rect
	var span: float = float(count - 1) * STEP_X + face.size.x
	var left: float = (view.x - span) * 0.5 - face.position.x
	var rest_left: float = left + face.position.x
	var rest_right: float = left + float(count - 1) * STEP_X + face.position.x + face.size.x
	var top: float = REST_FACE_TOP - HAND_RETURN_PAD_TOP
	return Rect2(rest_left - HAND_RETURN_PAD_X, top,
		(rest_right - rest_left) + HAND_RETURN_PAD_X * 2.0, view.y - top)


## Marks a drag whose release the Drop Zone already passed to try_play_card().
func _note_drop_consumed() -> void:
	_drag_drop_consumed = true


# --- Deck / piles ---

func _build_deck() -> void:
	_draw_pile.clear()
	_hand.clear()
	_discard_pile.clear()
	_retained_next_shuffle.clear()
	_consumed_pile.clear()
	# The deck comes from the player's inventory: every card is contributed by an item
	# they are carrying, chosen in the deck manager. It falls back to the prototype's
	# fixed deck when nothing carried offers cards, so a fight is never left with nothing.
	var chosen: Array[CardData] = Inventory.deck_cards()
	if chosen.is_empty():
		for path in DECK_PATHS:
			var fallback: CardData = load(path) as CardData
			if fallback:
				chosen.append(fallback)
			else:
				push_warning("CombatTest: could not load card at %s" % path)
	_draw_pile.assign(chosen)
	_draw_pile.shuffle()


## Draws up to `count` cards, reshuffling the discard pile when the draw pile
## runs out mid-draw.
func draw_cards(count: int) -> void:
	var first_new: int = _hand.size()
	for _i in count:
		if _draw_pile.is_empty():
			_recycle_discard()
		if _draw_pile.is_empty():
			break
		_hand.append(_draw_pile.pop_back())
	_rebuild_hand()
	_update_hud()
	# Deal the new cards in from the Draw pile (visual only).
	_animate_draw(first_new)


func discard_hand() -> void:
	var kept: Array[CardData] = []
	for card: CardData in _hand:
		if not card.temporary_combat:
			_discard_pile.append(card)
	_hand = kept


func _recycle_discard() -> void:
	if _discard_pile.is_empty() and _retained_next_shuffle.is_empty():
		return
	_draw_pile.append_array(_discard_pile)
	_draw_pile.append_array(_retained_next_shuffle)
	_discard_pile.clear()
	_retained_next_shuffle.clear()
	_draw_pile.shuffle()


# --- Playing cards (single path for drag + hotkeys) ---

## Returns true if the card was played.
func try_play_card(index: int, target_index: int = -1) -> bool:
	if not _enemy_group_hp.is_empty():
		_selected_enemy = clampi(target_index, 0, _enemy_group_hp.size() - 1) if target_index >= 0 else 0
		_sync_selected_from_group()
	if _state != State.ACTIVE:
		return false  # Fight is over — plays are locked.
	if index < 0 or index >= _hand.size():
		if index >= 0:
			_show_feedback("No card in slot %d." % (index + 1))
		return false
	var data: CardData = _hand[index]
	var card_cost: int = maxi(0, data.energy_cost - int(_temporary_costs.get(data.get_instance_id(), 0)))
	if data.damage > 0 and _next_attack_cost_reduction > 0:
		card_cost = maxi(0, card_cost - _next_attack_cost_reduction)
		_next_attack_cost_reduction = 0
	var crown_free: bool = Inventory.has_relic("Mysterious Crown") and not _crown_used \
			and data.damage <= 0
	if crown_free:
		card_cost = 0
	if card_cost > _energy:
		_show_feedback("Not enough energy — %s needs %d, you have %d." % [
			data.card_name, card_cost, _energy])
		return false
	_energy -= card_cost
	if crown_free:
		_crown_used = true
	_hand.remove_at(index)
	_cards_played_this_turn += 1
	if _cards_played_this_turn == 3 and Inventory.has_relic("Mysterious Orb"):
		_energy += 1
		_show_feedback("Mysterious Orb grants 1 Energy.")
	if data.consume:
		# Consumed cards leave the fight: they go to their own pile and are never
		# drawn or reshuffled again. If the card also names an inventory item, playing
		# it spends that as well — the stone really does leave the bag.
		_consumed_pile.append(data)
		if not data.consumes_item.is_empty():
			Inventory.spend_consumable(data.consumes_item)
	else:
		_discard_pile.append(data)
	_apply_card_effect(data)
	if data.draw_amount > 0:
		# Draw AFTER the card reaches the discard pile, so a mid-draw reshuffle can
		# legitimately redraw it. draw_cards() performs the reshuffle and refreshes
		# the hand + HUD; it ends no turn and grants no energy.
		draw_cards(data.draw_amount)
		_show_feedback("Played %s — drew %d." % [data.card_name, data.draw_amount])
	else:
		_rebuild_hand()
		_update_hud()
		_show_feedback("Played %s." % data.card_name)
	_check_result()
	return true


## Applies a played card's structured effect data. Sword actions are structured data supplied
## by SwordCardFactory; descriptions are never parsed to decide combat behavior.
func _apply_card_effect(data: CardData) -> void:
	if not _enemy_group_hp.is_empty():
		_sync_selected_from_group()
	var damage_bonus: int = _sword_damage_bonus(data)
	var ignore_block: int = _sword_ignore_block(data)
	var mark_bonus: int = _remove_status(_enemy_status, "mark")
	if mark_bonus > 0:
		_queue_impact(HitEffect.ImpactType.MARK, _selected_enemy_sprite())
	var fracture_bonus: int = _remove_status(_enemy_status, "fracture")
	var raw_damage: int = data.damage + damage_bonus + mark_bonus + fracture_bonus \
		+ int(_temporary_damage_bonuses.get(data.get_instance_id(), 0))
	_fracture_bonus_pending = 0
	_fracture_draw_pending = false
	for action: Dictionary in data.combat_actions:
		if bool(action.get("fracture_on_break", false)):
			_fracture_bonus_pending = int(action.get("fracture_bonus", 2))
			_fracture_draw_pending = bool(action.get("draw_on_break", false))
	var hit_count: int = _sword_hit_count(data)
	if raw_damage > 0:
		if hit_count <= 1:
			_damage_enemy(_player_attack_damage(raw_damage), DamageType.NORMAL, ignore_block)
		else:
			var remaining: int = raw_damage
			for hit_index: int in hit_count:
				var hits_left: int = hit_count - hit_index
				var hit_damage: int = ceili(float(remaining) / float(hits_left))
				remaining -= hit_damage
				_damage_enemy(_player_attack_damage(hit_damage), DamageType.NORMAL, ignore_block)
	if data.heal_amount > 0:
		_player_hp = mini(PLAYER_MAX_HP, _player_hp + data.heal_amount)
		Inventory.set_health(_player_hp)
		_update_hud(true)
	if data.block > 0:
		_player_block += data.block
	if data.weak > 0:
		_enemy_weak += data.weak
	for action: Dictionary in data.combat_actions:
		_apply_sword_action(action, data)
	if not _enemy_group_hp.is_empty():
		_sync_selected_to_group()
		_update_hud()


func _status_value(target: Dictionary, status: String) -> int:
	return int(target.get(status, 0))


func _add_status(target: Dictionary, status: String, amount: int) -> void:
	if amount <= 0:
		return
	target[status] = maxi(0, _status_value(target, status) + amount)
	if Inventory.has_relic("Strange Mask"):
		draw_cards(1)


func _remove_status(target: Dictionary, status: String, amount: int = -1) -> int:
	var current: int = _status_value(target, status)
	var removed: int = current if amount < 0 else mini(current, amount)
	target[status] = maxi(0, current - removed)
	return removed


func _sword_counter(data: CardData, suffix: String) -> int:
	var key: String = "%s:%d:%s:%s" % [data.sword_material, data.sword_upgrade_level,
		data.sword_attack_type, suffix]
	var value: int = int(_sword_counters.get(key, 0)) + 1
	_sword_counters[key] = value
	return value


func _sword_damage_bonus(data: CardData) -> int:
	var bonus: int = 0
	for action: Dictionary in data.combat_actions:
		var action_type: String = str(action.get("type", ""))
		if action_type == "bonus_per_status":
			var status: String = str(action.get("status", ""))
			var per: int = maxi(1, int(action.get("per", 1)))
			var stacks: int = _status_value(_enemy_status, status)
			var amount: int = int(action.get("amount", 1))
			var cap: int = int(action.get("cap", 999))
			bonus += mini(cap, floori(float(stacks) / float(per)) * amount)
			if int(action.get("frozen_bonus", 0)) > 0 and _status_value(_enemy_status, "frozen") > 0:
				bonus += int(action.get("frozen_bonus", 0))
		elif action_type == "duskbloom_bonus":
			var poisoned: bool = _status_value(_enemy_status, "poison") > 0
			var weakened: bool = _enemy_weak > 0
			if (poisoned or weakened) and not data.sword_attack_type == "heavy":
				bonus += int(action.get("amount", 1))
			elif poisoned and weakened:
				bonus += int(action.get("amount", 2))
		elif action_type == "retain_charge":
			var retained: int = mini(int(action.get("cap", 3)), _retained_next_shuffle.size())
			if bool(action.get("heavy", false)):
				bonus += retained * 2
		elif action_type == "intent_adapt" and _current_intent not in [EnemyAction.ATTACK_1,
			EnemyAction.ATTACK_2, EnemyAction.ATTACK_5, EnemyAction.ATTACK_6, EnemyAction.ATTACK_7,
			EnemyAction.ATTACK_WEAK, EnemyAction.DEFEND_2, EnemyAction.DEFEND_3]:
			bonus += int(action.get("amount", 1))
	return bonus


func _sword_ignore_block(data: CardData) -> int:
	for action: Dictionary in data.combat_actions:
		if str(action.get("type", "")) == "ignore_block":
			return int(action.get("amount", 0))
	return 0


func _sword_hit_count(data: CardData) -> int:
	for action: Dictionary in data.combat_actions:
		if str(action.get("type", "")) == "multi_hit":
			return maxi(1, int(action.get("hits", 1)))
	return 1


func _apply_sword_action(action: Dictionary, data: CardData) -> void:
	var action_type: String = str(action.get("type", ""))
	match action_type:
		"apply_status":
			var every_n: int = maxi(1, int(action.get("every_n", 1)))
			var status_name: String = str(action.get("status", ""))
			if _sword_counter(data, action_type + ":" + status_name) % every_n == 0:
				var status_amount: int = int(action.get("amount", 1))
				if status_name == "bleed" and _double_next_bleed:
					status_amount *= 2
					_double_next_bleed = false
				_add_status(_enemy_status, status_name, status_amount)
				_queue_status_impact(status_name, _selected_enemy_sprite())
		"weak":
			var weak_every: int = maxi(1, int(action.get("every_n", 1)))
			if _sword_counter(data, action_type) % weak_every == 0:
				_enemy_weak += int(action.get("amount", 1))
		"block":
			_player_block += int(action.get("amount", 0))
		"conditional_block":
			if _current_intent in [EnemyAction.ATTACK_1, EnemyAction.ATTACK_2, EnemyAction.ATTACK_5,
				EnemyAction.ATTACK_6, EnemyAction.ATTACK_7, EnemyAction.ATTACK_WEAK]:
				_player_block += int(action.get("amount", 0))
		"conditional_block_status":
			if _status_value(_enemy_status, str(action.get("status", ""))) > 0:
				_player_block += int(action.get("amount", 0))
		"draw":
			var draw_every: int = maxi(1, int(action.get("every_n", 1)))
			if _sword_counter(data, action_type) % draw_every == 0:
				draw_cards(int(action.get("amount", 1)))
		"draw_discard":
			draw_cards(int(action.get("draw", 2)))
			if not _hand.is_empty():
				var discarded: CardData = _hand.pop_back()
				if bool(action.get("retain_discard", false)):
					_retained_next_shuffle.append(discarded)
				else:
					_discard_pile.append(discarded)
				_rebuild_hand()
				_update_hud()
		"cost_reduction":
			var reduction_every: int = maxi(1, int(action.get("every_n", 3)))
			if _sword_counter(data, action_type) % reduction_every == 0 and not _hand.is_empty():
				var target_index: int = randi() % _hand.size()
				var target_card: CardData = _hand[target_index]
				_temporary_costs[target_card.get_instance_id()] = int(action.get("amount", 1))
		"temporary_upgrade":
			if not _hand.is_empty():
				var upgrade_card: CardData = _hand[randi() % _hand.size()]
				_temporary_damage_bonuses[upgrade_card.get_instance_id()] = int(action.get("amount", 1))
		"retain_charge":
			if bool(action.get("heavy", false)):
				_retained_next_shuffle.clear()
		"consume_status_damage":
			var status: String = str(action.get("status", ""))
			var consumed: int = _remove_status(_enemy_status, status)
			if consumed > 0:
				var multiplier: int = int(action.get("multiplier", 1))
				var bonus_per: int = int(action.get("bonus_per", 0))
				_damage_enemy(consumed * multiplier + (floori(float(consumed) / float(maxi(1, bonus_per))) if bonus_per > 0 else 0),
					DamageType.NORMAL, 0, _impact_for_status(status))
		"bonus_per_status":
			if bool(action.get("consume", false)):
				_remove_status(_enemy_status, str(action.get("status", "")))
		"heal_if_status":
			if _status_value(_enemy_status, str(action.get("status", ""))) >= int(action.get("threshold", 1)):
				Inventory.heal(int(action.get("amount", 1)))
				_player_hp = mini(PLAYER_MAX_HP, _player_hp + int(action.get("amount", 1)))
		"dodge":
			var dodge_every: int = maxi(1, int(action.get("every_n", 1)))
			if _sword_counter(data, action_type) % dodge_every == 0:
				_add_status(_player_status, "dodge", 1)
		"cycle_status", "alternate_status":
			_apply_cycled_status(action, data)
		"cleanse":
			if _sword_counter(data, action_type) % maxi(1, int(action.get("every_n", 1))) == 0:
				_remove_status(_player_status, "negative", 1)
		"apply_weak_if_poison":
			if _status_value(_enemy_status, "poison") > 0:
				_enemy_weak += int(action.get("amount", 1))
		"preserve_weak":
			_preserve_weak_on_poison = true
		"activate_drowsy":
			if _status_value(_enemy_status, "drowsy") >= 3:
				_remove_status(_enemy_status, "drowsy", 3)
				_activate_drowsy_on_enemy_turn = true
		"doom_config":
			_doom_activation_damage = int(action.get("damage", 5))
			_create_soul_slash_on_doom = bool(action.get("soul_slash", false))
		"intent_adapt":
			var adapt_amount: int = int(action.get("amount", 1))
			if _current_intent in [EnemyAction.ATTACK_1, EnemyAction.ATTACK_2, EnemyAction.ATTACK_5,
				EnemyAction.ATTACK_6, EnemyAction.ATTACK_7, EnemyAction.ATTACK_WEAK]:
				_player_block += adapt_amount
			elif _current_intent in [EnemyAction.DEFEND_2, EnemyAction.DEFEND_3]:
				_add_status(_enemy_status, "mark", adapt_amount if bool(action.get("heavy", false)) else 1)
			else:
				if bool(action.get("heavy", false)):
					_damage_enemy(adapt_amount)
		"generate_throws":
			var knife_material: String = str(action.get("material", "nightiron"))
			var throw_count: int = maxi(0, int(action.get("count", 2)))
			for _throw_index: int in throw_count:
				_hand.append(KnifeCardFactory.throw_card(knife_material))
			_rebuild_hand()
			_update_hud()
		"energy":
			_energy += int(action.get("amount", 1))
		"next_attack_cost":
			_next_attack_cost_reduction = maxi(_next_attack_cost_reduction, 1)
		"preserve_block":
			_preserve_block = mini(int(action.get("amount", 2)), _player_block)
		"contaminate":
			var negative_statuses: Array[String] = ["bleed", "poison", "burn", "weak", "chill", "shock", "drowsy", "rooted", "frozen", "doom", "entangle"]
			var unique_count: int = 0
			for negative: String in negative_statuses:
				if _status_value(_enemy_status, negative) > 0:
					unique_count += 1
			_add_status(_enemy_status, "poison", unique_count)
		"trigger_burn":
			var burn: int = _remove_status(_enemy_status, "burn")
			if burn > 0:
				_damage_enemy(burn, DamageType.NORMAL, 0, HitEffect.ImpactType.BURN)
		"double_next_bleed":
			_double_next_bleed = true
		"draw_discard_choice":
			draw_cards(int(action.get("draw", 2)))
			if not _hand.is_empty():
				var chosen_discard: CardData = _hand.pop_back()
				_discard_pile.append(chosen_discard)
				_rebuild_hand()
			_update_hud()
		"optional_sacrifice":
			# The sacrifice prompt remains opt-in; no automatic HP loss is introduced.
			pass


func _impact_for_status(status: String) -> int:
	match status:
		"bleed": return HitEffect.ImpactType.BLEED
		"poison": return HitEffect.ImpactType.POISON
		"burn": return HitEffect.ImpactType.BURN
		"chill", "frozen": return HitEffect.ImpactType.CHILL
		"shock": return HitEffect.ImpactType.SHOCK
		"doom": return HitEffect.ImpactType.DOOM
		"entangle", "rooted": return HitEffect.ImpactType.ENTANGLE
		"thorns": return HitEffect.ImpactType.THORNS
		"mark": return HitEffect.ImpactType.MARK
		"fracture": return HitEffect.ImpactType.FRACTURE
	return -1


func _set_card_cursor_active(active: bool) -> void:
	var cursor: Node = get_node_or_null("/root/CursorManager")
	if cursor == null:
		return
	cursor.set_click_uses_active(true)
	if active:
		cursor.set_ready()
	else:
		cursor.set_active(false)


func _queue_status_impact(status: String, target: Node2D) -> void:
	var impact_type: int = _impact_for_status(status)
	if impact_type < 0:
		return
	if not _pending_impacts.is_empty():
		var latest: Dictionary = _pending_impacts.back()
		if latest.get("target") == target and int(latest.get("type", -1)) == HitEffect.ImpactType.STANDARD_HIT:
			latest["type"] = impact_type
			_pending_impacts[_pending_impacts.size() - 1] = latest
			return
	_queue_impact(impact_type, target)


func _apply_cycled_status(action: Dictionary, data: CardData) -> void:
	var statuses: Array = action.get("statuses", []) as Array
	if statuses.is_empty():
		return
	var key: String = "%s:cycle" % data.sword_material
	var index: int = int(_sword_counters.get(key, 0))
	_sword_counters[key] = index + 1
	var amount: int = int(action.get("amount", 1))
	if bool(action.get("both", false)):
		for status_value: Variant in statuses:
			var both_status: String = str(status_value)
			_add_status(_enemy_status, both_status, amount)
			_queue_status_impact(both_status, _selected_enemy_sprite())
	else:
		var cycled_status: String = str(statuses[index % statuses.size()])
		_add_status(_enemy_status, cycled_status, amount)
		_queue_status_impact(cycled_status, _selected_enemy_sprite())


## The player's own Weak, applied to a card's damage: halved and rounded down, but never
## below 1, so a weakened attack still does something. One stack is spent per attack —
## the same rule the enemy's Weak follows.
func _player_attack_damage(raw: int) -> int:
	if _player_weak <= 0:
		return raw
	_player_weak = maxi(0, _player_weak - 1)
	return maxi(1, floori(float(raw) * 0.5))


## The single enemy-damage path used by every player damage source.
##
## Order, exactly: raw damage -> damage type -> Flight reduction (non-Poison while
## airborne) -> round the reduced damage UP -> enemy Block -> enemy HP -> spend one
## Flight stack for the hit -> knockdown if that reached zero -> HUD -> victory.
## Flight reduction happens BEFORE Block, and the hit still spends a stack even
## when Block absorbs all of the final damage: the enemy was struck regardless.
func _selected_enemy_sprite() -> AnimatedSprite2D:
	if _selected_enemy <= 0:
		return _enemy_sprite
	var clone_index: int = _selected_enemy - 1
	return _enemy_group_sprites[clone_index] if clone_index < _enemy_group_sprites.size() else _enemy_sprite


func _selected_enemy_status_bar() -> StatusBar:
	if not _enemy_group_status_bars.is_empty() \
			and _selected_enemy >= 0 and _selected_enemy < _enemy_group_status_bars.size():
		return _enemy_group_status_bars[_selected_enemy]
	return _enemy_bar


func _selected_enemy_flight_icon() -> TextureRect:
	if _selected_enemy <= 0:
		return _flight_icon
	var clone_index: int = _selected_enemy - 1
	if clone_index >= 0 and clone_index < _enemy_group_flight_icons.size():
		return _enemy_group_flight_icons[clone_index]
	return _flight_icon


func _sync_selected_from_group() -> void:
	if _enemy_group_hp.is_empty() or _selected_enemy >= _enemy_group_hp.size():
		return
	_enemy_hp = _enemy_group_hp[_selected_enemy]
	_enemy_max_hp = _enemy_group_max_hp[_selected_enemy]
	_enemy_block = _enemy_group_block[_selected_enemy]
	_current_intent = _enemy_group_intents[_selected_enemy]
	_enemy_status = _enemy_group_status[_selected_enemy].duplicate()
	_enemy_weak = _enemy_group_weak[_selected_enemy]
	_enemy_strength = _enemy_group_strength[_selected_enemy]
	_flight = _enemy_group_flight[_selected_enemy]
	_flight_state = _enemy_group_flight_state[_selected_enemy]
	if _selected_enemy < _enemy_group_drowsy_activated.size():
		_activate_drowsy_on_enemy_turn = _enemy_group_drowsy_activated[_selected_enemy]
	if _selected_enemy < _enemy_group_doom_damage.size():
		_doom_activation_damage = _enemy_group_doom_damage[_selected_enemy]
	if _selected_enemy < _enemy_group_soul_slash_on_doom.size():
		_create_soul_slash_on_doom = _enemy_group_soul_slash_on_doom[_selected_enemy]


func _sync_selected_to_group() -> void:
	if _enemy_group_hp.is_empty() or _selected_enemy >= _enemy_group_hp.size():
		return
	_enemy_group_hp[_selected_enemy] = _enemy_hp
	_enemy_group_block[_selected_enemy] = _enemy_block
	_enemy_group_intents[_selected_enemy] = _current_intent
	_enemy_group_status[_selected_enemy] = _enemy_status.duplicate()
	_enemy_group_weak[_selected_enemy] = _enemy_weak
	_enemy_group_strength[_selected_enemy] = _enemy_strength
	_enemy_group_flight[_selected_enemy] = _flight
	_enemy_group_flight_state[_selected_enemy] = _flight_state
	if _selected_enemy < _enemy_group_drowsy_activated.size():
		_enemy_group_drowsy_activated[_selected_enemy] = _activate_drowsy_on_enemy_turn
	if _selected_enemy < _enemy_group_doom_damage.size():
		_enemy_group_doom_damage[_selected_enemy] = _doom_activation_damage
	if _selected_enemy < _enemy_group_soul_slash_on_doom.size():
		_enemy_group_soul_slash_on_doom[_selected_enemy] = _create_soul_slash_on_doom


func _damage_enemy(amount: int, damage_type: int = DamageType.NORMAL, ignore_block: int = 0,
		impact_type: int = -1) -> void:
	if amount <= 0:
		return
	var raw: int = amount
	var dealt: int = raw
	if _flight_state == FlightState.AIRBORNE and damage_type != DamageType.POISON:
		# Half damage, rounded UP: a 1-damage attack must never become zero.
		dealt = ceili(float(raw) * 0.5)
	var blocked_before: int = _enemy_block
	var effective_block: int = 0 if ignore_block < 0 else maxi(0, _enemy_block - ignore_block)
	var absorbed: int = mini(effective_block, dealt)
	_enemy_block = maxi(0, _enemy_block - absorbed)
	if ignore_block > 0:
		_enemy_block = mini(_enemy_block, blocked_before)
	if _fracture_bonus_pending > 0 and blocked_before > 0 and _enemy_block == 0:
		_add_status(_enemy_status, "fracture", _fracture_bonus_pending)
		if _fracture_draw_pending:
			draw_cards(1)
		_fracture_bonus_pending = 0
		_fracture_draw_pending = false
	var through: int = dealt - absorbed
	var target_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	if absorbed > 0:
		_queue_impact(HitEffect.ImpactType.BLOCKED_HIT, target_sprite)
	if through > 0:
		_enemy_hp = maxi(0, _enemy_hp - through)
		if not _enemy_group_hp.is_empty() and _enemy_hp <= 0 and target_sprite.sprite_frames != null \
				and target_sprite.sprite_frames.has_animation(_enemy_death_anim):
			target_sprite.play(_enemy_death_anim)
		var resolved_impact: int = impact_type if impact_type >= 0 else HitEffect.ImpactType.STANDARD_HIT
		_queue_impact(resolved_impact, target_sprite)
	# One resolved damaging hit spends exactly one Flight stack. Poison bypasses
	# Flight entirely (no card or status uses it yet).
	if damage_type != DamageType.POISON:
		_spend_flight()
	_sync_selected_to_group()
	_update_hud(true)
	_check_result()


func _queue_impact(impact_type: HitEffect.ImpactType, target: Node2D) -> void:
	_pending_impacts.append({"type": int(impact_type), "target": target})


func _impact_anchor(target: Node2D) -> Vector2:
	if target == _enemy_sprite:
		return _spider_point().round()
	if target == _player_sprite_node:
		return _player_point().round()
	return target.global_position.round()


func _spawn_hit_effect(impact_type: HitEffect.ImpactType, target: Node2D,
		display_scale: int) -> HitEffect:
	if not is_inside_tree() or target == null or not is_instance_valid(target):
		return null
	var effect: HitEffect = HIT_EFFECT_SCENE.instantiate() as HitEffect
	if effect == null:
		return null
	_front_effects.add_child(effect)
	effect.global_position = _impact_anchor(target)
	effect.setup(impact_type, display_scale)
	effect.finished.connect(_on_hit_effect_finished.bind(effect), CONNECT_ONE_SHOT)
	_active_hit_effects.append(effect)
	return effect


func _on_hit_effect_finished(effect: HitEffect) -> void:
	_active_hit_effects.erase(effect)


func _wait_for_active_hit_effects() -> void:
	while not _active_hit_effects.is_empty():
		var alive: Array[HitEffect] = []
		for effect: HitEffect in _active_hit_effects:
			if is_instance_valid(effect):
				alive.append(effect)
		_active_hit_effects = alive
		if not _active_hit_effects.is_empty():
			await get_tree().process_frame


func play_impact(impact_type: HitEffect.ImpactType, target: Node2D,
		await_completion: bool = true, display_scale: int = HitEffect.DISPLAY_SCALE) -> void:
	var effect: HitEffect = _spawn_hit_effect(impact_type, target, display_scale)
	if effect == null:
		return
	effect.play_effect()
	if await_completion:
		await effect.finished


func play_impact_sequence(impact_types: Array[int], target: Node2D) -> void:
	for impact_type: int in impact_types:
		if _state != State.ACTIVE and _state != State.VICTORY:
			return
		await play_impact(impact_type as HitEffect.ImpactType, target, true)
		if impact_type != impact_types.back():
			await get_tree().create_timer(0.06).timeout


func _play_pending_impacts() -> void:
	var pending: Array[Dictionary] = _pending_impacts.duplicate()
	_pending_impacts.clear()
	for entry: Dictionary in pending:
		var target: Node2D = entry.get("target") as Node2D
		if target == null or not is_instance_valid(target):
			continue
		var effect: HitEffect = _spawn_hit_effect(
			int(entry.get("type", HitEffect.ImpactType.STANDARD_HIT)), target, HitEffect.DISPLAY_SCALE)
		if effect == null:
			continue
		effect.play_effect()
		var peak_state: Array = [false]
		effect.peak_started.connect(func() -> void: peak_state[0] = true, CONNECT_ONE_SHOT)
		while not bool(peak_state[0]) and is_instance_valid(effect):
			await get_tree().process_frame
		if entry != pending.back():
			await get_tree().create_timer(0.06).timeout


## One qualifying hit removes exactly one Flight stack, and reaching zero grounds
## the enemy as STUNNED. The stack can never fall below zero, and once grounded
## this does nothing at all.
func _spend_flight() -> void:
	if not _has_flight or _flight_state != FlightState.AIRBORNE:
		return
	_flight = maxi(0, _flight - 1)
	if _flight <= 0:
		_flight = 0
		_flight_state = FlightState.GROUNDED_STUNNED


## End Turn. The gameplay sequence is unchanged — discard the hand, clear the
## enemy's stale Block, act, resolve, then open the next player turn — it is only
## bracketed by feedback and held under the animation lock, and the next intent is
## drawn AFTER the current action has visibly resolved.
func _on_end_turn_pressed() -> void:
	if _state != State.ACTIVE or animation_busy:
		return  # Fight is over, or an animation is still resolving.
	_run_enemy_turn()


func _run_enemy_turn() -> void:
	if not _enemy_group_hp.is_empty():
		await _run_group_enemy_turn()
		return
	animation_busy = true
	_apply_lock()
	_temporary_costs.clear()
	_temporary_damage_bonuses.clear()
	# Unplayed cards fly into the Discard pile first, then the hand is cleared and
	# the enemy acts. Played cards never take this path.
	await _animate_hand_to_discard()
	discard_hand()
	_rebuild_hand()
	# Enemy Block never persists indefinitely: clear it at the START of the enemy
	# turn, before this turn's already-displayed intent executes.
	_enemy_block = 0
	_process_enemy_start_turn_effects()
	await _play_pending_impacts()
	_update_hud()
	# Turn classification: a stunned enemy skips its action entirely; a grounded one
	# spends its whole action taking off again; anything else acts normally.
	var stunned: bool = _flight_state == FlightState.GROUNDED_STUNNED
	var flying: bool = _flight_state == FlightState.GROUNDED_RECOVERY
	var controlled: bool = _consume_control_status()
	if not stunned and not controlled:
		# Anticipation: pulse exactly the action that is on display, then act.
		await _pulse_intent()
	var before: Dictionary = _combat_snapshot()
	var rescue_intervened: bool = false
	if stunned:
		# Flight knockdown is distinct: the queued action is neither executed, nor
		# replaced, nor consumed, and the enemy recovers on the next enemy turn.
		_flight_state = FlightState.GROUNDED_RECOVERY
		_show_feedback("Enemy is stunned — its action is skipped.")
		_update_hud(true)
		await _stun_effect()
	elif controlled:
		# Status control skips only this action; it does not alter Flight state.
		_show_feedback("Enemy is controlled — its action is skipped.")
		_update_hud(true)
		await _stun_effect()
	elif flying:
		# Still on the ground: it cannot attack or defend this turn. Its action is the
		# takeoff, restoring full Flight. The intent it kept is deferred, not consumed.
		_flight_state = FlightState.AIRBORNE
		_flight = _max_flight
		_show_feedback("Enemy takes flight again — %d Flight." % _max_flight)
		_update_hud(true)
		await _takeoff_effect()
	elif _enemy_hp > 0:
		if _rescue_intervention and _enemy_attack_would_kill_player():
			await _run_rescue_intervention()
			rescue_intervened = true
		elif _current_intent == EnemyAction.DEFEND_2:
			_execute_intent(EnemyAction.DEFEND_2)
			_update_hud(true)
			await _feedback_from_deltas(before)
			await _wait_for_active_hit_effects()
		else:
			await _enemy_attack(before)
	if not rescue_intervened:
		_process_enemy_end_turn_effects()
	await _play_pending_impacts()
	# Resolve the fight BEFORE touching the counter: an enemy action that ends the
	# fight must not create a next player turn.
	_check_result()
	if _state != State.ACTIVE:
		animation_busy = false
		_update_hud()
		# The enemy's action and its feedback have fully resolved by now.
		_emit_result_if_decided()
		return
	# The next player turn begins now. Exactly one increment per completed enemy
	# action — Defend counts the same as an attack, and so does a skipped one.
	turn_number += 1
	_cards_played_this_turn = 0
	if turn_number == 4 and Inventory.has_relic("Photo of a Ghost"):
		_player_intangible = true
		_show_feedback("Photo of a Ghost grants Intangible.")
	if not stunned and not controlled and not flying:
		# The displayed action has fully resolved, so the next one may now replace it.
		# Drawn AFTER the increment so a scheduled move knows which turn it is for. A
		# skipped action, and a turn spent taking off, must NOT advance the bag.
		_draw_intent()
	var preserved_block: int = _preserve_block
	_preserve_block = 0
	_player_block = preserved_block
	_energy = ENERGY_PER_TURN
	# Start of a new player turn: an AIRBORNE enemy's Flight is topped back up, so
	# three hits are needed within one turn to ground it. A grounded enemy is NOT
	# restored — it stays at zero and vulnerable.
	if _flight_state == FlightState.AIRBORNE:
		_flight = _max_flight
	draw_cards(HAND_SIZE)
	_update_hud()
	# Let the dealt cards finish landing before the new-turn pulse.
	while _dealing:
		await get_tree().process_frame
	await _pulse_turn_counter()
	animation_busy = false
	_update_hud()


func _draw_group_intent(index: int) -> void:
	if index < 0 or index >= _enemy_group_bags.size() or _enemy_group_hp[index] <= 0:
		return
	if _strengthen_on_turn > 0 and turn_number == _strengthen_on_turn:
		_enemy_group_intents[index] = EnemyAction.STRENGTHEN
		_enemy_group_last_intents[index] = EnemyAction.STRENGTHEN
		return
	if not _intent_pool.is_empty():
		var options: Array[int] = _intent_pool.filter(
			func(action: int) -> bool: return action != _enemy_group_last_intents[index])
		if options.is_empty():
			options = _intent_pool.duplicate()
		var pooled_intent: int = options[randi() % options.size()]
		_enemy_group_intents[index] = pooled_intent
		_enemy_group_last_intents[index] = pooled_intent
		return
	var bag: Array = _enemy_group_bags[index]
	if bag.is_empty():
		bag = ENEMY_INTENT_BAG.duplicate()
		bag.shuffle()
		if bag.size() > 1 and int(bag[bag.size() - 1]) == _enemy_group_last_intents[index]:
			for bag_index: int in range(bag.size() - 1):
				if int(bag[bag_index]) != _enemy_group_last_intents[index]:
					var swap: int = int(bag[bag_index])
					bag[bag_index] = bag[bag.size() - 1]
					bag[bag.size() - 1] = swap
					break
	var next_intent: int = int(bag.pop_back())
	_enemy_group_intents[index] = next_intent
	_enemy_group_last_intents[index] = next_intent
	_enemy_group_bags[index] = bag


func _run_group_enemy_turn() -> void:
	animation_busy = true
	_apply_lock()
	_temporary_costs.clear()
	_temporary_damage_bonuses.clear()
	await _animate_hand_to_discard()
	discard_hand()
	_rebuild_hand()
	_player_block = 0
	var advance_intent: Array[bool] = []
	for _index: int in range(_enemy_group_hp.size()):
		advance_intent.append(false)
	for index: int in range(_enemy_group_hp.size()):
		if _enemy_group_hp[index] <= 0:
			continue
		_selected_enemy = index
		_sync_selected_from_group()
		# Block expires at the start of this individual enemy's action, not at the
		# start of the entire group turn.
		_enemy_block = 0
		_sync_selected_to_group()
		_process_enemy_start_turn_effects()
		_sync_selected_to_group()
		await _play_pending_impacts()
		_check_result()
		if _state != State.ACTIVE:
			break
		if _enemy_hp <= 0:
			continue
		var stunned: bool = _flight_state == FlightState.GROUNDED_STUNNED
		var recovering: bool = _flight_state == FlightState.GROUNDED_RECOVERY
		var controlled: bool = _consume_control_status()
		if not stunned and not controlled:
			await _pulse_intent()
		var before: Dictionary = _combat_snapshot()
		if stunned:
			_flight_state = FlightState.GROUNDED_RECOVERY
			_show_feedback("Enemy is stunned — its action is skipped.")
			_update_hud(true)
			await _stun_effect()
		elif controlled:
			_show_feedback("Enemy is controlled — its action is skipped.")
			_update_hud(true)
			await _stun_effect()
		elif recovering:
			_flight_state = FlightState.AIRBORNE
			_flight = _max_flight
			_show_feedback("Enemy takes flight again — %d Flight." % _max_flight)
			_update_hud(true)
			await _takeoff_effect()
		elif _enemy_hp > 0:
			if _is_attack_intent(_current_intent):
				await _enemy_attack(before)
			else:
				# Defend and Strengthen resolve exactly as shown, without an attack lunge.
				_execute_intent(_current_intent)
				_update_hud(true)
				await _feedback_from_deltas(before)
				await _wait_for_active_hit_effects()
		_process_enemy_end_turn_effects()
		_sync_selected_to_group()
		await _play_pending_impacts()
		_check_result()
		if _state != State.ACTIVE:
			break
		if not stunned and not controlled and not recovering:
			advance_intent[index] = true
	if _state != State.ACTIVE:
		animation_busy = false
		_update_hud()
		_emit_result_if_decided()
		return
	turn_number += 1
	_cards_played_this_turn = 0
	for index: int in range(_enemy_group_hp.size()):
		if _enemy_group_hp[index] <= 0:
			continue
		if advance_intent[index]:
			_draw_group_intent(index)
		if _enemy_group_flight_state[index] == FlightState.AIRBORNE:
			_enemy_group_flight[index] = _max_flight
	_selected_enemy = 0
	_sync_selected_from_group()
	var preserved_block: int = _preserve_block
	_preserve_block = 0
	_player_block = preserved_block
	_energy = ENERGY_PER_TURN
	draw_cards(HAND_SIZE)
	_update_hud()
	while _dealing:
		await get_tree().process_frame
	animation_busy = false
	_update_hud()


func _enemy_attack_would_kill_player() -> bool:
	if _player_hp <= 0 or _current_intent == EnemyAction.DEFEND_2:
		return false
	if _status_value(_player_status, "dodge") > 0:
		return false
	var incoming: int = _intent_attack_damage()
	var blocked: int = mini(_player_block, incoming)
	return incoming - blocked >= _player_hp


func _run_rescue_intervention() -> void:
	# The bear never resolves its killing blow. This is a combat-side impact on the
	# enemy, followed by the normal enemy death animation before the overlay closes.
	_queue_impact(HitEffect.ImpactType.STANDARD_HIT, _enemy_sprite)
	_enemy_hp = 0
	_update_hud(true)
	await _play_pending_impacts()
	_state = State.RESCUED
	_set_result("ERDON!")
	_play_enemy_anim(_enemy_death_anim, true)
	await _await_enemy_death()


## The displayed attack's base damage, after Weak. Weak is a duration (half damage,
## rounded down) and halves the BASE; Strength is added per strike afterwards.
func _intent_base_damage() -> int:
	# ATTACK_1 and ATTACK_2 were doubled from the original 1 / 2 tuning to match the
	# doubled card values; ATTACK_5 and ATTACK_6 are plain heavy blows, and ATTACK_WEAK
	# is a light blow carrying the Weak rider.
	var base: int = 4
	match _current_intent:
		EnemyAction.ATTACK_1:
			base = 2
		EnemyAction.ATTACK_5:
			base = 5
		EnemyAction.ATTACK_6:
			base = 10
		EnemyAction.ATTACK_7:
			base = 6
		EnemyAction.ATTACK_WEAK:
			base = 4
		_:
			base = 4
	return floori(float(base) * 0.5) if _enemy_weak > 0 else base


## Block granted by the displayed Defend action. The prototype's guard is 4; the
## skeleton's lighter guard is 3. Read from the action on display, so the number the
## player is shown and the number actually granted can never drift apart.
func _intent_block_value() -> int:
	return 3 if _current_intent == EnemyAction.DEFEND_3 else ENEMY_DEFEND_BLOCK


## Weak the displayed attack will leave on the PLAYER. Only ATTACK_WEAK carries it.
func _intent_player_weak() -> int:
	return 2 if _current_intent == EnemyAction.ATTACK_WEAK else 0


## Draws the next intent from the shuffled bag. The bag refills with one of each
## action once empty, and an immediate repeat across the bag boundary is avoided.
func _draw_intent() -> void:
	# A scheduled move replaces the bag draw entirely for its turn, and is shown in
	# advance exactly like a normal intent so the player is never surprised by it. The
	# bag itself is left untouched, so the normal cycle resumes afterwards.
	if _strengthen_on_turn > 0 and turn_number == _strengthen_on_turn:
		_current_intent = EnemyAction.STRENGTHEN
		_last_intent = _current_intent
		_update_hud()
		return
	# An encounter may supply the enemy's whole moveset: then the action is drawn at
	# random from that pool instead of the default bag, never repeating back-to-back.
	if not _intent_pool.is_empty():
		var options: Array[int] = _intent_pool.filter(
			func(action: int) -> bool: return action != _last_intent)
		if options.is_empty():
			options = _intent_pool.duplicate()
		_current_intent = options[randi() % options.size()]
		_last_intent = _current_intent
		_update_hud()
		return
	if _intent_bag.is_empty():
		_intent_bag = ENEMY_INTENT_BAG.duplicate()
		_intent_bag.shuffle()
		if _intent_bag.size() > 1 and _intent_bag[_intent_bag.size() - 1] == _last_intent:
			for i in _intent_bag.size() - 1:
				if _intent_bag[i] != _last_intent:
					var swap: int = _intent_bag[i]
					_intent_bag[i] = _intent_bag[_intent_bag.size() - 1]
					_intent_bag[_intent_bag.size() - 1] = swap
					break
	_current_intent = _intent_bag.pop_back()
	_last_intent = _current_intent
	_update_hud()


func _add_soul_slash() -> void:
	var slash: CardData = CardData.new()
	slash.card_name = "Soul Slash"
	slash.description = "Deal 3 damage. Consume."
	slash.energy_cost = 0
	slash.damage = 3
	slash.consume = true
	slash.artwork = preload("res://assets/Cards/blue-backdrop.png")
	slash.keyword_ids = ["consume"]
	_hand.append(slash)
	_rebuild_hand()
	_update_hud()


func _process_enemy_start_turn_effects() -> void:
	var poison: int = _status_value(_enemy_status, "poison")
	if poison > 0:
		_damage_enemy(poison, DamageType.POISON, -1, HitEffect.ImpactType.POISON)
		_remove_status(_enemy_status, "poison", 1)
	var doom: int = _status_value(_enemy_status, "doom")
	if doom >= 3:
		_remove_status(_enemy_status, "doom", 3)
		_damage_enemy(_doom_activation_damage, DamageType.NORMAL, -1, HitEffect.ImpactType.DOOM)
		if _create_soul_slash_on_doom:
			_add_soul_slash()
			_create_soul_slash_on_doom = false
	var chill: int = _status_value(_enemy_status, "chill")
	if chill >= 3:
		_remove_status(_enemy_status, "chill", 3)
		_add_status(_enemy_status, "frozen", 1)
		_queue_impact(HitEffect.ImpactType.CHILL, _selected_enemy_sprite())
	var entangle: int = _status_value(_enemy_status, "entangle")
	if entangle >= 3:
		_remove_status(_enemy_status, "entangle", 3)
		_add_status(_enemy_status, "rooted", 1)
		_queue_impact(HitEffect.ImpactType.ENTANGLE, _selected_enemy_sprite())


func _consume_control_status() -> bool:
	if _activate_drowsy_on_enemy_turn:
		_activate_drowsy_on_enemy_turn = false
		_show_feedback("Enemy is Drowsy — its action is delayed.")
		return true
	if _status_value(_enemy_status, "frozen") > 0:
		_remove_status(_enemy_status, "frozen", 1)
		_add_status(_enemy_status, "freeze_immunity", 2)
		_show_feedback("Enemy is Frozen — its action is skipped.")
		return true
	if _status_value(_enemy_status, "rooted") > 0:
		_remove_status(_enemy_status, "rooted", 1)
		_show_feedback("Enemy is Rooted — its action is skipped.")
		return true
	if _status_value(_enemy_status, "drowsy") >= 3:
		_remove_status(_enemy_status, "drowsy", 3)
		_show_feedback("Enemy is Drowsy — its action is delayed.")
		return true
	return false


func _process_enemy_end_turn_effects() -> void:
	var burn: int = _status_value(_enemy_status, "burn")
	if burn > 0:
		_damage_enemy(burn, DamageType.NORMAL, -1, HitEffect.ImpactType.BURN)
		_enemy_status["burn"] = 0
	if _status_value(_enemy_status, "freeze_immunity") > 0:
		_remove_status(_enemy_status, "freeze_immunity", 1)


func _resolve_enemy_attack_statuses() -> void:
	var bleed: int = _status_value(_enemy_status, "bleed")
	if bleed > 0:
		_damage_enemy(bleed, DamageType.NORMAL, 0, HitEffect.ImpactType.BLEED)
		_remove_status(_enemy_status, "bleed", 1)
	var thorns: int = _status_value(_player_status, "thorns")
	if thorns > 0:
		_damage_enemy(thorns, DamageType.NORMAL, -1, HitEffect.ImpactType.THORNS)
		_remove_status(_player_status, "thorns")


## Runs exactly the action that was on display.
func _execute_intent(action: int) -> void:
	match action:
		EnemyAction.ATTACK_1, EnemyAction.ATTACK_2, EnemyAction.ATTACK_5, EnemyAction.ATTACK_6, EnemyAction.ATTACK_7, EnemyAction.ATTACK_WEAK:
			var damage: int = _intent_attack_damage()
			var weakened: bool = _enemy_weak > 0
			if _remove_status(_player_status, "dodge", 1) > 0:
				_show_feedback("Enemy attacks for %d — Dodged." % damage)
				if weakened:
					_enemy_weak = maxi(0, _enemy_weak - 1)
				return
			var absorbed: int = mini(_player_block, damage)
			_player_block = maxi(0, _player_block - absorbed)
			var through: int = damage - absorbed
			if absorbed > 0:
				_queue_impact(HitEffect.ImpactType.BLOCKED_HIT, _player_sprite_node)
			if _player_intangible:
				_player_intangible = false
				_show_feedback("Intangible prevents the attack.")
				through = 0
			if through > 0:
				var previous_hp: int = _player_hp
				_player_hp = maxi(0, _player_hp - through)
				if Inventory.has_relic("Talisman") and not _talisman_used \
						and previous_hp >= ceili(float(PLAYER_MAX_HP) * 0.5) \
						and _player_hp < ceili(float(PLAYER_MAX_HP) * 0.5):
					_player_block += 6
					_talisman_used = true
					_show_feedback("Talisman grants 6 Block.")
				_queue_impact(HitEffect.ImpactType.STANDARD_HIT, _player_sprite_node)
			# A rider that weakens the player is applied only when the move carries one,
			# and is announced in the same breath as the damage, so the player is never
			# quietly saddled with it.
			var rider: int = _intent_player_weak()
			if rider > 0:
				_player_weak += rider
				_show_feedback("Enemy attacks for %d%s — %d blocked, %d to HP, and Weakens you (now %d)." % [
					damage, " (Weakened)" if weakened else "", absorbed, through, _player_weak])
			else:
				_show_feedback("Enemy attacks for %d%s — %d blocked, %d to HP." % [
					damage, " (Weakened)" if weakened else "", absorbed, through])
			if weakened:
				# Weak is a duration: one stack is spent per weakened ATTACK.
				_enemy_weak = maxi(0, _enemy_weak - 1)
			_resolve_enemy_attack_statuses()
		EnemyAction.DEFEND_2, EnemyAction.DEFEND_3:
			var guard: int = _intent_block_value()
			_enemy_block += guard
			_show_feedback("Enemy defends — gains %d Block." % guard)
		EnemyAction.STRENGTHEN:
			_enemy_strength += 1
			_show_feedback("Enemy strengthens — +1 Strength (now %d): its attacks hit harder." % _enemy_strength)


## Public entry point. Starts an ordinary battle using this prototype's own HP,
## deck, hand size, intent bag and animations, then applies any optional enemy
## configuration carried by the encounter data. Everything is additive: with no
## data — or with data that never mentions them — the enemy is exactly the ground
## spider, and running this scene directly still boots a plain spider battle.
func begin_encounter(encounter_data: Dictionary = {}) -> void:
	_hosted = true
	_encounter_data = encounter_data.duplicate()
	_apply_encounter_config(_encounter_data)
	# A per-animation scale correction is only meaningful once the enemy's base scale
	# has been applied, so the opening pose is re-played here to pick up its own.
	_play_enemy_anim(_enemy_idle_anim, true)
	_update_hud()
	if bool(_encounter_data.get("tutorial_spider", false)):
		call_deferred("_start_first_spider_tutorial")


func _start_first_spider_tutorial() -> void:
	while _dealing:
		await get_tree().process_frame
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or bool(state.get("first_spider_tutorial_seen")):
		return
	_tutorial_active = true
	animation_busy = true
	_apply_lock()
	_tutorial = CombatTutorial.new()
	_tutorial.name = "CombatTutorial"
	_tutorial.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_tutorial)
	var steps: Array[Array] = [
		[_energy_label],
		[_intent_label],
		[_hand_container],
		[_end_turn_button],
	]
	var messages: Array[String] = [
		"This is your Energy. You get 3 each turn.",
		"This is what the enemy intends to do.",
		"Play cards to engage in combat.",
		"When you're done or you've run out of Energy,\nhit 'End Turn' or press E.",
	]
	_tutorial.start(steps, messages, Callable(self, "_finish_first_spider_tutorial"))


func _finish_first_spider_tutorial() -> void:
	if not _tutorial_active:
		return
	_tutorial_active = false
	var state: Node = get_node_or_null("/root/GameState")
	if state != null:
		state.set("first_spider_tutorial_seen", true)
	if is_instance_valid(_tutorial):
		_tutorial.queue_free()
	_tutorial = null
	animation_busy = false
	_apply_lock()


## Applies optional enemy configuration. Recognised keys, all optional:
##   has_flight: bool          enables the Flight capability
##   max_flight: int           stacks restored at the start of each player turn
##   sprite: String            airborne artwork path
##   sprite_grounded: String   grounded/dazed artwork path
##   sprite_scale: float       scale for that artwork
##   sprite_position: Vector2  where the enemy sits
##   group_sprite_y: float     optional shared Y position for grouped enemies
##   enemy_hud_y_offset: float optional vertical shift for enemy-owned HUD elements
##   group_health_bar_y_offset: float extra shift for each grouped health bar
## Flight is NEVER inferred from artwork, the enemy's name, its animations or any
## UI text: it comes only from has_flight.
func _apply_encounter_config(config: Dictionary) -> void:
	_multi_hit_actions.assign(config.get("multi_hit_actions", []))
	_intent_pool.assign(config.get("intent_pool", []))
	_strengthen_on_turn = int(config.get("strengthen_on_turn", 0))
	_group_sprite_y = float(config.get("group_sprite_y", 463.0))
	_enemy_hud_y_offset = float(config.get("enemy_hud_y_offset", 0.0))
	_group_health_bar_y_offset = float(config.get("group_health_bar_y_offset", 0.0))
	_rescue_intervention = bool(config.get("erden_rescue", false))
	# Optional per-animation scale corrections, for sheets whose animations are drawn at
	# different sizes. Empty (the default) leaves every animation at the base scale.
	_enemy_anim_scales = config.get("anim_scales", {}) as Dictionary
	# An enemy may bring its own maximum HP — the bear has 20, the skeleton 14 — and
	# without one it keeps the prototype's original 12.
	if config.has("max_hp"):
		_enemy_max_hp = maxi(1, int(config["max_hp"]))
		_enemy_hp = _enemy_max_hp
	# The enemy's own scene supplies its animation set, so the combat screen plays the
	# same animations the overworld does.
	_use_enemy_scene(String(config.get("enemy_scene", DEFAULT_ENEMY_SCENE)), config)
	if config.has("sprite_scale"):
		var s: float = float(config["sprite_scale"])
		_enemy_sprite.scale = Vector2(s, s)
	if config.has("sprite_position"):
		_enemy_sprite.position = (config["sprite_position"] as Vector2).round()
	# The configured position is where the GROUNDED art sits, and is the resting
	# baseline: every knockdown/takeoff cycle is measured from it, so cycles cannot
	# drift.
	_enemy_rest_position = _enemy_sprite.position
	_enemy_rest_scale = _enemy_sprite.scale
	_configure_enemy_group(maxi(1, int(config.get("enemy_count", 1))))
	if bool(config.get("dungeon_encounter", false)):
		var cave_background: Texture2D = load("res://assets/Combat/cavefight.png") as Texture2D
		if cave_background != null:
			_background.texture = cave_background
		else:
			push_warning("CombatTest: cavefight.png is not present; using ForestFight.png fallback.")

	_has_flight = bool(config.get("has_flight", ENEMY_HAS_FLIGHT))
	_max_flight = maxi(1, int(config.get("max_flight", ENEMY_MAX_FLIGHT)))
	if not _enemy_group_flight.is_empty():
		for index: int in range(_enemy_group_flight.size()):
			_enemy_group_flight[index] = _max_flight if _has_flight else 0
			_enemy_group_flight_state[index] = FlightState.AIRBORNE if _has_flight else FlightState.NONE
	if _has_flight:
		# A flying enemy hovers: its airborne art may sit above the grounded spot.
		if config.has("sprite_air_offset"):
			_enemy_air_offset = (config["sprite_air_offset"] as Vector2).round()
		_enemy_sprite.position = _enemy_air_position()
		for clone_index: int in range(_enemy_group_sprites.size()):
			var rest_index: int = clone_index + 1
			if rest_index < _enemy_group_rest_positions.size():
				_enemy_group_sprites[clone_index].position = (
					_enemy_group_rest_positions[rest_index] + _enemy_air_offset).round()
		_flight_state = FlightState.AIRBORNE
		_flight = _max_flight
	else:
		_enemy_air_offset = Vector2.ZERO
		_flight_state = FlightState.NONE
		_flight = 0
	# _ready() drew a first action before this configuration existed, so choose it
	# again when the encounter changed how that choice is made. Enemies with no
	# schedule and no custom pool keep the action _ready() already drew, untouched.
	if _strengthen_on_turn > 0 or not _intent_pool.is_empty():
		_draw_intent()
	_offset_primary_enemy_hud(_enemy_hud_y_offset)
	_update_hud()


func _offset_primary_enemy_hud(y_offset: float) -> void:
	if is_zero_approx(y_offset):
		return
	_enemy_bar.root.position.y += y_offset
	_enemy_bar.emblem_centre.y += y_offset
	_enemy_bar.block_centre.y += y_offset
	_enemy_bar.interior_centre.y += y_offset
	_intent_icon.position.y += y_offset
	_intent_label.position.y += y_offset
	_intent_icon_backing.position.y += y_offset
	_strength_icon.position.y += y_offset
	_strength_label.position.y += y_offset
	_weak_icon.position.y += y_offset
	_enemy_weak_label.position.y += y_offset
	_flight_icon.position.y += y_offset
	_flight_label.position.y += y_offset


## Where the enemy sits while AIRBORNE: the grounded resting position plus the
## hover offset. Always whole pixels, and always derived from the rest position, so
## repeated knockdown cycles cannot accumulate drift.
func _configure_enemy_group(count: int) -> void:
	for sprite: AnimatedSprite2D in _enemy_group_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()
	_enemy_group_sprites.clear()
	_enemy_group_rest_positions.clear()
	for bar: Control in _enemy_group_bars:
		if is_instance_valid(bar):
			bar.queue_free()
	_enemy_group_bars.clear()
	for group_bar: StatusBar in _enemy_group_status_bars:
		if is_instance_valid(group_bar.root):
			group_bar.root.queue_free()
		if is_instance_valid(group_bar.hp_label):
			group_bar.hp_label.queue_free()
		if is_instance_valid(group_bar.block_label):
			group_bar.block_label.queue_free()
	_enemy_group_status_bars.clear()
	for label: Label in _enemy_group_intent_labels:
		if is_instance_valid(label):
			label.queue_free()
	_enemy_group_intent_labels.clear()
	for icon: Sprite2D in _enemy_group_intent_icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_enemy_group_intent_icons.clear()
	for label: Label in _enemy_group_status_labels:
		if is_instance_valid(label):
			label.queue_free()
	_enemy_group_status_labels.clear()
	_enemy_group_flight_icons.clear()
	_enemy_group_weak_icons.clear()
	_enemy_group_strength_icons.clear()
	_enemy_group_flight_counts.clear()
	_enemy_group_weak_counts.clear()
	_enemy_group_strength_counts.clear()
	_enemy_group_hp.clear()
	_enemy_group_max_hp.clear()
	_enemy_group_block.clear()
	_enemy_group_intents.clear()
	_enemy_group_last_intents.clear()
	_enemy_group_bags.clear()
	_enemy_group_status.clear()
	_enemy_group_weak.clear()
	_enemy_group_strength.clear()
	_enemy_group_flight.clear()
	_enemy_group_flight_state.clear()
	_enemy_group_drowsy_activated.clear()
	_enemy_group_doom_damage.clear()
	_enemy_group_soul_slash_on_doom.clear()
	_selected_enemy = 0
	_player_sprite_node.position = PLAYER_BACK_POSITION
	# Grouped enemy sprites share the background's normal depth so they render above it.
	_enemy_sprite.z_index = 0
	if count <= 1:
		return
	var positions: Array[Vector2] = []
	if count == 2:
		positions = [Vector2(480, _group_sprite_y), Vector2(820, _group_sprite_y)]
	else:
		positions = [Vector2(470, _group_sprite_y), Vector2(770, _group_sprite_y),
			Vector2(1070, _group_sprite_y)]
	_enemy_sprite.position = positions[0]
	for index: int in range(count):
		_enemy_group_rest_positions.append(positions[index])
		_enemy_group_hp.append(_enemy_max_hp)
		_enemy_group_max_hp.append(_enemy_max_hp)
		_enemy_group_block.append(0)
		var intent_source: Array = _intent_pool if not _intent_pool.is_empty() else ENEMY_INTENT_BAG
		var bag: Array = intent_source.duplicate()
		bag.shuffle()
		_enemy_group_bags.append(bag)
		var first_intent: int = int(bag.pop_back()) if not bag.is_empty() else EnemyAction.ATTACK_1
		if _strengthen_on_turn > 0 and turn_number == _strengthen_on_turn:
			first_intent = EnemyAction.STRENGTHEN
		_enemy_group_intents.append(first_intent)
		_enemy_group_last_intents.append(first_intent)
		_enemy_group_status.append({})
		_enemy_group_weak.append(0)
		_enemy_group_strength.append(0)
		_enemy_group_flight.append(_max_flight if _has_flight else 0)
		_enemy_group_flight_state.append(FlightState.AIRBORNE if _has_flight else FlightState.NONE)
		_enemy_group_drowsy_activated.append(false)
		_enemy_group_doom_damage.append(_doom_activation_damage)
		_enemy_group_soul_slash_on_doom.append(false)
		if index > 0:
			var clone: AnimatedSprite2D = AnimatedSprite2D.new()
			clone.name = "EnemyGroup%d" % (index + 1)
			clone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			clone.sprite_frames = _enemy_frames_air
			clone.scale = _enemy_sprite.scale
			clone.position = positions[index]
			clone.z_index = 0
			add_child(clone)
			_enemy_group_sprites.append(clone)
		_add_group_enemy_widgets(index, positions[index])
	_enemy_rest_position = _enemy_sprite.position
	_enemy_rest_scale = _enemy_sprite.scale
	_play_enemy_anim(_enemy_idle_anim, true)
	for index: int in range(_enemy_group_sprites.size()):
		var clone: AnimatedSprite2D = _enemy_group_sprites[index]
		var frame_count: int = clone.sprite_frames.get_frame_count(_enemy_idle_anim) \
			if clone.sprite_frames != null and clone.sprite_frames.has_animation(_enemy_idle_anim) else 1
		if clone.sprite_frames != null and clone.sprite_frames.has_animation(_enemy_idle_anim):
			clone.play(_enemy_idle_anim)
		clone.frame = (index + 1) % maxi(1, frame_count)


func _add_group_enemy_widgets(index: int, at: Vector2) -> void:
	var bar_origin: Vector2 = Vector2(at.x - 108.5,
		248.0 + _enemy_hud_y_offset + _group_health_bar_y_offset)
	var real_bar: StatusBar = _make_status_bar("Enemy%dStatusBar" % index, bar_origin,
		ENEMY_BAR_SCALE, ENEMY_BAR_FONT)
	var bar_scale_value: float = float(ENEMY_BAR_SCALE)
	real_bar.emblem_centre = bar_origin + Vector2(5.5 * bar_scale_value, 8.0 * bar_scale_value)
	real_bar.block_centre = bar_origin + Vector2(5.5 * bar_scale_value, 8.5 * bar_scale_value)
	real_bar.interior_centre = bar_origin + Vector2((float(BAR_FILL_X) + float(BAR_FILL_W) * 0.5) * bar_scale_value,
		8.0 * bar_scale_value)
	var label_box: float = 10.0 * bar_scale_value
	real_bar.hp_label.size = Vector2(label_box, label_box)
	real_bar.block_label.size = Vector2(label_box, label_box)
	_enemy_group_status_bars.append(real_bar)
	var intent: Label = Label.new()
	intent.name = "Enemy%dIntent" % index
	# Keep each enemy's intent in the narrow lane immediately to the right of its bar.
	intent.position = at + Vector2(103.0, -161.0)
	intent.size = Vector2(90.0, 30.0)
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intent.add_theme_font_override("font", ui_font)
	intent.add_theme_font_size_override("font_size", 16)
	add_child(intent)
	_enemy_group_intent_labels.append(intent)
	var intent_icon: Sprite2D = Sprite2D.new()
	intent_icon.name = "Enemy%dIntentIcon" % index
	intent_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	intent_icon.position = at + Vector2(148.0, -183.0)
	intent_icon.scale = Vector2(2.0, 2.0)
	intent_icon.z_index = 1
	add_child(intent_icon)
	_enemy_group_intent_icons.append(intent_icon)
	var status: Label = Label.new()
	status.name = "Enemy%dStatuses" % index
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.position = at + Vector2(-100.0, -270.0)
	status.size = Vector2(200.0, 28.0)
	status.visible = false
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_override("font", ui_font)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.86, 0.9, 1.0))
	add_child(status)
	_enemy_group_status_labels.append(status)
	var flight_icon: TextureRect = _make_group_status_icon(TEX_STATUS_FLYING, status, 0.0)
	var weak_icon: TextureRect = _make_group_status_icon(TEX_STATUS_WEAK, status, 42.0)
	var strength_icon: TextureRect = _make_group_status_icon(TEX_STATUS_STRENGTH, status, 84.0)
	_enemy_group_flight_icons.append(flight_icon)
	_enemy_group_weak_icons.append(weak_icon)
	_enemy_group_strength_icons.append(strength_icon)
	_enemy_group_flight_counts.append(_make_group_status_count(status, 25.0))
	_enemy_group_weak_counts.append(_make_group_status_count(status, 67.0))
	_enemy_group_strength_counts.append(_make_group_status_count(status, 109.0))


func _group_intent_texture(action: int) -> Texture2D:
	match action:
		EnemyAction.DEFEND_2, EnemyAction.DEFEND_3:
			return TEX_INTENT_DEFEND
		EnemyAction.STRENGTHEN:
			return TEX_STATUS_STRENGTH
		EnemyAction.ATTACK_WEAK:
			return TEX_INTENT_ATTACK_DEBUFF
	return TEX_INTENT_ATTACK


func _make_group_status_count(parent: Control, x: float) -> Label:
	var count: Label = Label.new()
	count.position = Vector2(x, -1.0)
	count.size = Vector2(32.0, 28.0)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	count.add_theme_font_override("font", ui_font)
	count.add_theme_font_size_override("font_size", 18)
	count.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	parent.add_child(count)
	return count


func _make_group_status_icon(texture: Texture2D, parent: Control, x: float) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(x, 2.0)
	icon.size = Vector2(34.0, 24.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	parent.add_child(icon)
	return icon


func _enemy_rest_position_for_selected() -> Vector2:
	if not _enemy_group_rest_positions.is_empty() \
			and _selected_enemy >= 0 and _selected_enemy < _enemy_group_rest_positions.size():
		return _enemy_group_rest_positions[_selected_enemy]
	return _enemy_rest_position


func _enemy_air_position() -> Vector2:
	return (_enemy_rest_position_for_selected() + _enemy_air_offset).round()


## Adopts an enemy scene's own SpriteFrames — taken without adding it to the tree, so
## its _ready never runs — and applies any encounter overrides on top. This is what
## makes the combat screen play the same animations as the overworld.
func _use_enemy_scene(scene_path: String, config: Dictionary) -> void:
	if config.has("sprite_frames"):
		_enemy_frames_air = config["sprite_frames"] as SpriteFrames
	elif ResourceLoader.exists(scene_path):
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed:
			var probe: Node = packed.instantiate()
			var spr: AnimatedSprite2D = probe.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if spr:
				_enemy_frames_air = spr.sprite_frames
			probe.free()
	if _enemy_frames_air == null:
		push_warning("CombatTest: no enemy animation set available for '%s'." % scene_path)
		return
	# The enemy's animation tables decide which animation the combat screen plays, just
	# as they decide which one the overworld walks with. The combat enemy faces the
	# player front-on, so the "down" entry is used throughout: the spider plays Idle and
	# Attack, the moth plays down and attack_down.
	if config.has("idle_anims"):
		_enemy_idle_anim = StringName(str((config["idle_anims"] as Dictionary).get("down", "")))
	if config.has("attack_anims"):
		_enemy_attack_anim = StringName(str((config["attack_anims"] as Dictionary).get("down", "")))
	if config.has("death_animation"):
		_enemy_death_anim = StringName(str(config["death_animation"]))
	if config.has("grounded_animation"):
		_enemy_ground_anim = StringName(str(config["grounded_animation"]))
	if config.has("sprite_grounded"):
		var tex: Texture2D = load(String(config["sprite_grounded"])) as Texture2D
		if tex:
			_enemy_frames_ground = _single_frame_set(tex)
	_enemy_sprite.sprite_frames = _enemy_frames_air
	_enemy_sprite.flip_h = false
	_measure_enemy_frames()
	_play_enemy_anim(_enemy_idle_anim)


## A one-frame animation set, for artwork that has no animations of its own (the dazed
## moth, which only exists as a single image).
func _single_frame_set(tex: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation(&"ground")
	frames.set_animation_speed(&"ground", 1.0)
	frames.set_animation_loop(&"ground", false)
	frames.add_frame(&"ground", tex)
	return frames


## Plays one of the enemy's animations on the combat screen. Unknown names are ignored,
## so an enemy missing an animation simply keeps the pose it had. `restart` forces the
## animation back to its first frame, which is what makes each strike of a flurry read
## as a fresh attack rather than one continuous loop.
func _play_enemy_anim(anim: StringName, restart: bool = false) -> void:
	var actor_index: int = clampi(_selected_enemy, 0, maxi(0, _enemy_group_hp.size() - 1))
	if not _enemy_group_hp.is_empty() and _enemy_group_hp[actor_index] <= 0:
		return
	var sprite: AnimatedSprite2D = _selected_enemy_sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	# Only the selected group member performs this action. The rest hold their own
	# idle/state animation until their turn in the sequence.
	if _enemy_anim_scales.has(anim):
		sprite.scale = _enemy_rest_scale * float(_enemy_anim_scales[anim])
	if not restart and sprite.animation == anim and sprite.is_playing():
		return
	sprite.play(anim)


## Waits for the enemy's death animation to finish, with a timeout so a missing or
## looping animation can never wedge the end of the fight.
func _await_enemy_death() -> void:
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	if actor_sprite.sprite_frames == null:
		return
	if not actor_sprite.sprite_frames.has_animation(_enemy_death_anim):
		return
	if actor_sprite.sprite_frames.get_animation_loop(_enemy_death_anim):
		return
	var speed: float = maxf(actor_sprite.sprite_frames.get_animation_speed(_enemy_death_anim), 0.001)
	var length: float = float(actor_sprite.sprite_frames.get_frame_count(_enemy_death_anim)) / speed
	var elapsed := 0.0
	while elapsed < length + 0.4 and actor_sprite.is_playing():
		elapsed += get_process_delta_time()
		await get_tree().process_frame


## Waits out the enemy's CURRENT animation, bounded so a looping or missing animation can
## never wedge the turn. This is what lets a strike actually be SEEN: the lunge tween is
## very quick, so without waiting, the attack animation was replaced by the idle after a
## single frame and the blow never read as a blow.
##
## The cap is set above the longest attack in the project (the bear's 1.25 s, the moth's
## 1.17 s), so every enemy plays its whole swing; the skeleton's 0.67 s and the spider's
## 0.80 s are well inside it.
func _await_enemy_anim(max_wait: float = 1.4) -> void:
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	var frames: SpriteFrames = actor_sprite.sprite_frames
	if frames == null:
		return
	var anim: StringName = actor_sprite.animation
	if not frames.has_animation(anim) or frames.get_animation_loop(anim):
		return
	var speed: float = maxf(frames.get_animation_speed(anim), 0.001)
	var length: float = minf(float(frames.get_frame_count(anim)) / speed, max_wait)
	var waited := 0.0
	while waited < length and actor_sprite.is_playing() \
			and actor_sprite.animation == anim:
		waited += get_process_delta_time()
		await get_tree().process_frame


# --- The player's own sprite ---------------------------------------------------

## Takes the player's animation set from the player's scene, exactly as the enemy takes
## its own from the enemy scene, so the fight plays the same animations the overworld
## does. The rest pose is the rear view the fight has always shown.
func _setup_player_sprite() -> void:
	if _player_sprite_node.sprite_frames != null:
		return
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	if packed == null:
		return
	var source: Node = packed.instantiate()
	var src_sprite: AnimatedSprite2D = source.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if src_sprite != null:
		_player_sprite_node.sprite_frames = src_sprite.sprite_frames
	source.free()
	if _player_sprite_node.sprite_frames == null \
			or not _player_sprite_node.sprite_frames.has_animation(PLAYER_IDLE_ANIM):
		return
	# The player's sheet puts the art BELOW the middle of its 48x48 frame — measured, the
	# idle art's centre sits at (24.5, 32.5) against a frame centre of (24, 24). Nudging
	# the sprite up by that difference puts the bust exactly where the fight has always
	# drawn it, so _player_point() keeps measuring the same column and the damage floats,
	# impact icons and recoil all stay where they were.
	_player_sprite_node.offset = Vector2(-0.5, -8.5)
	_player_sprite_node.play(PLAYER_IDLE_ANIM)


## The player's strike, played when an attack card lands. It returns to the rest pose
## once the swing has finished, and a second attack restarts it from frame zero rather
## than being cut short by the previous swing's timer.
func _play_player_attack() -> void:
	var frames: SpriteFrames = _player_sprite_node.sprite_frames
	if frames == null or not frames.has_animation(PLAYER_ATTACK_ANIM):
		return
	_player_attack_token += 1
	var token: int = _player_attack_token
	_player_sprite_node.play(PLAYER_ATTACK_ANIM)
	var speed: float = maxf(frames.get_animation_speed(PLAYER_ATTACK_ANIM), 0.001)
	var length: float = float(frames.get_frame_count(PLAYER_ATTACK_ANIM)) / speed
	await get_tree().create_timer(length).timeout
	if not is_inside_tree() or token != _player_attack_token:
		return
	if _player_sprite_node.animation == PLAYER_ATTACK_ANIM:
		_player_sprite_node.play(PLAYER_IDLE_ANIM)


## The enemy's visible centre, measured from the artwork of its idle animation, so the
## feedback helpers work for any enemy art without hand-tuned constants.
func _measure_enemy_frames() -> void:
	if _enemy_sprite.sprite_frames == null:
		return
	if not _enemy_sprite.sprite_frames.has_animation(_enemy_idle_anim):
		return
	var tex: Texture2D = _enemy_sprite.sprite_frames.get_frame_texture(_enemy_idle_anim, 0)
	if tex != null:
		_measure_enemy_texture(tex)


## Measures an artwork's visible centre from its opaque pixels, so every feedback
## helper works for any enemy art without hand-tuned constants.
func _measure_enemy_texture(tex: Texture2D) -> void:
	var img: Image = tex.get_image()
	if img == null:
		return
	var min_x := img.get_width()
	var max_x := -1
	var min_y := img.get_height()
	var max_y := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.05:
				min_x = mini(min_x, x); max_x = maxi(max_x, x)
				min_y = mini(min_y, y); max_y = maxi(max_y, y)
	if max_x < 0:
		return
	_enemy_tex_half = Vector2(float(img.get_width()), float(img.get_height())) * 0.5
	_enemy_bbox_pos = Vector2(float(min_x), float(min_y))
	_enemy_bbox_size = Vector2(float(max_x - min_x + 1), float(max_y - min_y + 1))


func _emit_result_if_decided() -> void:
	if _result_emitted or _state == State.ACTIVE:
		return
	_result_emitted = true
	# Hand the health back BEFORE the result goes out, so the overworld — and the next
	# fight — both see where this one left the player. A loss stands them back up: a fight
	# that ended in defeat would otherwise leave them at zero for ever.
	if _state == State.VICTORY:
		Inventory.set_health(_player_hp)
	else:
		Inventory.set_health(Inventory.PLAYER_MAX_HP)
	var result: int = CombatResult.VICTORY
	if _state == State.DEFEAT:
		result = CombatResult.DEFEAT
	elif _state == State.RESCUED:
		result = CombatResult.RESCUED
	combat_finished.emit(result)


func _check_result() -> void:
	if _state != State.ACTIVE:
		return
	var group_alive: bool = false
	for hp: int in _enemy_group_hp:
		if hp > 0:
			group_alive = true
	if (not _enemy_group_hp.is_empty() and not group_alive) or (_enemy_group_hp.is_empty() and _enemy_hp <= 0):
		_state = State.VICTORY
		_set_result("VICTORY")
		# The enemy falls where it stands: its own death animation plays before the
		# combat screen closes, so the win is shown rather than only announced.
		_play_enemy_anim(_enemy_death_anim, true)
	elif _player_hp <= 0:
		_state = State.DEFEAT
		_set_result("DEFEAT")
	_update_hud()


func _set_result(text: String) -> void:
	_result_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if not _tutorial_active and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_on_end_turn_pressed()
		return
	if _tutorial_active:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var code: int = key.keycode
			if code >= KEY_1 and code <= KEY_9:
				# Same animated request path as a drag: the hotkey only asks.
				_request_play_card(code - KEY_1)


# --- Hand display ---

func _rebuild_hand() -> void:
	for child in _hand_container.get_children():
		_hand_container.remove_child(child)
		child.queue_free()
	_slots.clear()
	_slot_x.clear()
	_slot_y.clear()
	_target_x.clear()
	_target_y.clear()
	_hover_index = -1
	for i in _hand.size():
		_create_hand_slot(i)
	_apply_hover_layout()
	# A newly built hand starts settled in its resting arrangement.
	for i in _slots.size():
		_slot_x[i] = _target_x[i]
		_slot_y[i] = _target_y[i]
		_slots[i].position = Vector2(_slot_x[i], _slot_y[i])


## Lays the hand out as an overlapping fan, centred for the current card count:
## left = (view width - visible span) / 2 - face x. The span is always even, so
## every target coordinate is a whole pixel. The hovered card rises and its
## neighbours slide aside by HOVER_PUSH.
func _apply_hover_layout() -> void:
	var count: int = _slots.size()
	if count <= 0 or not _card_face_ready:
		return
	var face: Rect2 = _card_face_rect
	var span: float = float(count - 1) * STEP_X + face.size.x
	var left: float = (get_viewport_rect().size.x - span) * 0.5 - face.position.x
	var rest_y: float = REST_FACE_TOP - face.position.y
	var hover_y: float = HOVER_FACE_TOP - face.position.y
	for i in count:
		var tx: float = left + float(i) * STEP_X
		var ty: float = rest_y
		if _hover_index >= 0 and i != _hover_index:
			tx += HOVER_PUSH if i > _hover_index else -HOVER_PUSH
		elif i == _hover_index:
			ty = hover_y
		_target_x[i] = tx
		_target_y[i] = ty
		# A raised card exposes its whole face; the last resting card also does
		# (nothing overlaps it), every other resting card only its own strip.
		var handle := _slots[i].get_node_or_null("DragHandle") as Control
		if handle:
			var full: bool = i == _hover_index or i == count - 1
			var width: float = face.size.x if full else minf(face.size.x, STEP_X)
			handle.size = Vector2(width, face.size.y)
	# Draw (and hit-test) the raised card above its neighbours.
	if _hover_index >= 0 and _hover_index < count:
		_hand_container.move_child(_slots[_hover_index], -1)
	else:
		for i in count:
			_hand_container.move_child(_slots[i], i)


## Stable hover pick. The layout used for picking is the fixed TARGET layout, so
## moving cards can never flip the selection: the raised card keeps the hover
## while the pointer is anywhere on it (hysteresis), otherwise the front-most
## card whose target rect contains the pointer wins.
func _update_hover() -> void:
	var next: int = _hover_target_at(_hand_container.get_local_mouse_position())
	if next == _hover_index:
		return
	_hover_index = next
	_apply_hover_layout()


func _hover_target_at(point: Vector2) -> int:
	var count: int = _slots.size()
	if count <= 0 or not _card_face_ready:
		return -1
	if point.y < HOVER_FACE_TOP or point.y > get_viewport_rect().size.y:
		return -1
	if _hover_index >= 0 and _hover_index < count and _hit_rect(_hover_index).has_point(point):
		return _hover_index
	for i in range(count - 1, -1, -1):
		if i != _hover_index and _hit_rect(i).has_point(point):
			return i
	return -1


## The interactive rect of card i: its target x, spanning the whole raised band.
func _hit_rect(i: int) -> Rect2:
	var face: Rect2 = _card_face_rect
	return Rect2(_target_x[i] + face.position.x, HOVER_FACE_TOP,
		face.size.x, get_viewport_rect().size.y - HOVER_FACE_TOP)


## Animates positions only, snapping to whole pixels so the pixel art stays crisp.
func _animate_slots(delta: float) -> void:
	var f: float = 1.0 - pow(0.001, delta / HOVER_TIME)
	for i in _slots.size():
		_slot_x[i] += (_target_x[i] - _slot_x[i]) * f
		_slot_y[i] += (_target_y[i] - _slot_y[i]) * f
		if absf(_slot_x[i] - _target_x[i]) < 0.5:
			_slot_x[i] = _target_x[i]
		if absf(_slot_y[i] - _target_y[i]) < 0.5:
			_slot_y[i] = _target_y[i]
		_slots[i].position = Vector2(roundf(_slot_x[i]), roundf(_slot_y[i]))


func _create_hand_slot(index: int) -> void:
	var slot := Control.new()
	slot.name = "Slot%d" % (index + 1)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_container.add_child(slot)

	var card := CARD_SCENE.instantiate() as Card
	slot.add_child(card)
	card.card_data = _hand[index]
	card.position = CARD_OFFSET
	# Card visuals are display-only and overlap their neighbours, so they must not
	# swallow mouse input: only the drag handles receive clicks.
	_set_mouse_ignore(card)

	var face: Rect2 = _card_face_rect_for(card)

	# Invisible drag handle covering exactly this card's exposed strip (its whole
	# face while it is the raised card — see _apply_hover_layout).
	var handle := CardDragHandle.new()
	handle.name = "DragHandle"
	handle.test_root = self
	handle.hand_index = index
	handle.card_node = card
	handle.face_offset = face.position - CARD_OFFSET
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.add_child(handle)
	handle.position = face.position
	handle.size = Vector2(minf(face.size.x, STEP_X), face.size.y)

	# No visible hotkey number any more — keys 1..N still map to hand order via
	# _unhandled_input(), they just are not drawn on the cards.

	_slots.append(slot)
	_slot_x.append(0.0)
	_slot_y.append(0.0)
	_target_x.append(0.0)
	_target_y.append(0.0)


## Returns (and caches) the card's visible face relative to its slot origin.
func _card_face_rect_for(card: Control) -> Rect2:
	if _card_face_ready:
		return _card_face_rect
	var frame := card.get_node_or_null("Frame") as TextureRect
	if frame and frame.texture and frame.size.x > 0.0:
		_card_base_scale = card.scale.x
		var tex_size := Vector2(frame.texture.get_width(), frame.texture.get_height())
		var bbox := _texture_alpha_bbox(frame.texture)
		# Frame.size is the unscaled Control size. Include the Frame node's own scale
		# and pivot when measuring the face, otherwise the layout centres an inflated
		# mathematical rectangle rather than the pixels the player actually sees.
		var frame_scale: Vector2 = frame.scale
		var frame_visual_pos: Vector2 = frame.position + frame.pivot_offset \
			- frame.pivot_offset * frame_scale
		var in_frame: Vector2 = frame.size / tex_size * frame_scale
		var local_pos: Vector2 = frame_visual_pos + bbox.position * in_frame
		var local_size: Vector2 = bbox.size * in_frame
		_card_face_rect = Rect2(card.position + local_pos * card.scale, local_size * card.scale)
		_card_face_ready = true
	elif frame:
		_card_face_rect = Rect2(card.position + frame.position * card.scale, frame.size * card.scale)
		_card_face_ready = true
	return _card_face_rect


## Bounding box of the non-transparent pixels of a texture.
func _texture_alpha_bbox(tex: Texture2D) -> Rect2:
	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var img := tex.get_image()
	if img == null:
		return Rect2(Vector2.ZERO, tex_size)
	var mn := tex_size
	var mx := Vector2.ZERO
	var found := false
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.01:
				found = true
				mn.x = minf(mn.x, float(x))
				mn.y = minf(mn.y, float(y))
				mx.x = maxf(mx.x, float(x))
				mx.y = maxf(mx.y, float(y))
	if not found:
		return Rect2(Vector2.ZERO, tex_size)
	return Rect2(mn, mx - mn)


## Makes a node and all of its Control descendants transparent to the mouse.
func _set_mouse_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_ignore(child)


# --- Animated card play + combat feedback ------------------------------------
#
# All presentation. Gameplay stays in try_play_card() / _execute_intent(): the
# animation calls them exactly once, at the moment of impact, and every piece of
# feedback is chosen from the ACTUAL before/after state deltas rather than from a
# card's nominal numbers or its name.

## Validates a play request, then animates it. Both a drag release and a hotkey
## come through here, so there is exactly one animated play path.
func _request_play_card(index: int, target_index: int = -1) -> void:
	if not _enemy_group_hp.is_empty():
		_selected_enemy = clampi(target_index, 0, _enemy_group_hp.size() - 1) if target_index >= 0 else 0
		_sync_selected_from_group()
	if animation_busy or _state != State.ACTIVE:
		return
	if index < 0 or index >= _hand.size():
		if index >= 0:
			_show_feedback("No card in slot %d." % (index + 1))
		return
	var data: CardData = _hand[index]
	if data.energy_cost > _energy:
		_show_feedback("Not enough energy — %s needs %d, you have %d." % [
			data.card_name, data.energy_cost, _energy])
		return
	await _animate_card_play(index, data, target_index)


## Lock, launch a temporary visual, commit the real play at impact, play the
## feedback the real deltas ask for, clean up, unlock.
func _animate_card_play(index: int, data: CardData, target_index: int = -1) -> void:
	animation_busy = true
	_apply_lock()
	_pending_impacts.clear()
	var source: Control = null
	if index < _slots.size():
		source = _slots[index].get_node_or_null("Card") as Control
	var visual: Control = _spawn_card_visual(source)
	if source != null:
		source.visible = false         # the slot placeholder itself stays put
	var before: Dictionary = _combat_snapshot()
	if visual != null:
		var from: Vector2 = visual.position
		var to: Vector2 = _card_target_for(data, target_index) - _visual_face_offset()
		var travel := create_tween()
		travel.tween_method(func(p: Vector2) -> void: _set_pixel_pos(visual, p),
			from, to, CARD_TRAVEL_TIME).set_ease(Tween.EASE_OUT)
		var fade := create_tween()
		fade.tween_property(visual, "modulate:a", 0.0, CARD_FADE_TIME) \
			.set_delay(maxf(CARD_TRAVEL_TIME - CARD_FADE_TIME, 0.0))
		await travel.finished
		# Impact. The real play runs here, exactly once, and nowhere else.
		var played: bool = try_play_card(index, target_index)
		if played and data.damage > 0:
			# An attack card: the player strikes. Decided from the card's effect data
			# (does it deal damage), never from its name or any UI text.
			_play_player_attack()
		if not played and source != null and is_instance_valid(source):
			source.visible = true      # rejected: the card comes back visibly
		await fade.finished
		_cleanup_visual(visual)
	else:
		if try_play_card(index, target_index) and data.damage > 0:
			_play_player_attack()
	await _play_pending_impacts()
	await _feedback_from_deltas(before)
	await _wait_for_active_hit_effects()
	# On a win the enemy is already falling, so let its death animation play out before
	# the result is reported: the victory is seen, not cut short.
	if _state == State.VICTORY:
		await _await_enemy_death()
	animation_busy = false
	_update_hud()
	# The impact feedback above is the fight's last animation, so the encounter
	# result is safe to report from here.
	_emit_result_if_decided()


## A display-only duplicate of a hand card on the effects layer: its script is
## removed, its processing disabled and every child made mouse-transparent, so it
## can never emit a signal or run an effect.
func _spawn_card_visual(source: Control) -> Control:
	if source == null:
		return null
	var visual := source.duplicate() as Control
	if visual == null:
		return null
	visual.set_script(null)
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	# duplicate() copies the source's `visible` flag, and dealt cards are hidden
	# before their copy is made — without this the copy would never be drawn.
	visual.visible = true
	_effects.add_child(visual)
	visual.global_position = source.global_position
	_set_mouse_ignore(visual)
	return visual


## The card FACE's centre relative to the Card node, so a target point can be hit
## exactly by the travelling visual's centre.
func _visual_face_offset() -> Vector2:
	return _card_face_rect.position + _card_face_rect.size * 0.5 - CARD_OFFSET


## Structural targeting: where a card flies is decided from its effect fields —
## never from its name, description or any UI text.
func _card_target_for(data: CardData, target_index: int = -1) -> Vector2:
	if data.damage > 0:
		var target: AnimatedSprite2D = _selected_enemy_sprite() if target_index >= 0 else _enemy_sprite
		return _sprite_point(target) - Vector2(CARD_STOP_SHORT, 0.0)    # toward the enemy
	if data.block > 0:
		return _player_point() - Vector2(0.0, CARD_PLAYER_LIFT)  # above the player
	return Vector2(get_viewport_rect().size.x * 0.5, REST_FACE_TOP - 100.0)


## The spider's visible body centre, from its live transform plus the artwork's
## measured opaque bounds.
func _sprite_point(sprite: AnimatedSprite2D) -> Vector2:
	var s: float = sprite.scale.x
	return sprite.position - _enemy_tex_half * s + (_enemy_bbox_pos + _enemy_bbox_size * 0.5) * s


func _spider_point() -> Vector2:
	return _sprite_point(_selected_enemy_sprite())


## The player's visible head/upper-body column.
func _player_point() -> Vector2:
	var s: float = _player_sprite_node.scale.x
	var opaque_top: float = _player_sprite_node.position.y - 16.0 * s + 6.0 * s
	return Vector2(_player_sprite_node.position.x, opaque_top + 40.0)


## Tween helper: whole-pixel positions keep the pixel art crisp.
func _set_pixel_pos(node: CanvasItem, p: Vector2) -> void:
	node.position = Vector2(roundf(p.x), roundf(p.y))


## Everything feedback can be derived from, captured before an effect resolves.
func _combat_snapshot() -> Dictionary:
	return {
		"php": _player_hp, "pblk": _player_block,
		"ehp": _enemy_hp, "eblk": _enemy_block, "weak": _enemy_weak,
		"flight": _flight, "fstate": _flight_state,
		"draw": _draw_pile.size(), "hand": _hand.size(),
		"disc": _discard_pile.size(), "cons": _consumed_pile.size(),
	}


## Turns the ACTUAL deltas of a resolved effect into feedback. Generic: nothing
## here knows which card was played, so future cards are covered automatically.
func _feedback_from_deltas(before: Dictionary) -> void:
	var e_hp: int = maxi(0, int(before["ehp"]) - _enemy_hp)
	var e_blk: int = maxi(0, int(before["eblk"]) - _enemy_block)
	var e_gain: int = maxi(0, _enemy_block - int(before["eblk"]))
	var p_hp: int = maxi(0, int(before["php"]) - _player_hp)
	var p_blk: int = maxi(0, int(before["pblk"]) - _player_block)
	var p_gain: int = maxi(0, _player_block - int(before["pblk"]))
	var gained_weak: int = maxi(0, _enemy_weak - int(before["weak"]))
	var drawn: int = maxi(0, int(before["draw"]) - _draw_pile.size())

	if p_gain > 0:
		await _block_gain_effect(true, p_gain)
	if e_gain > 0:
		await _block_gain_effect(false, e_gain)

	# Enemy side: Block is consumed before HP, so a broken Block shows both. The
	# icon follows the same rule as the numbers: any health lost is a Hit, damage
	# that was absorbed entirely is a Blocked.
	if e_blk > 0 and e_hp > 0:
		_spawn_float("-%d" % e_blk, _spider_point() + Vector2(-52.0, 26.0), COLOUR_BLOCK)
	if e_hp > 0:
		await _hit_reaction(_selected_enemy_sprite(), ENEMY_RECOIL)
		_spawn_float("-%d" % e_hp, _spider_point(), COLOUR_DAMAGE)
	elif e_blk > 0:
		_flash_shield(_spider_point())
		_spawn_float("-%d" % e_blk, _spider_point(), COLOUR_BLOCK)

	# Flight reacts to the ACTUAL state change, never to which card was played, so
	# the hit feedback above always plays first. A knockdown is a heavier landing.
	var fstate_before: int = int(before.get("fstate", _flight_state))
	var flight_before: int = int(before.get("flight", _flight))
	if _has_flight and _flight_state == FlightState.GROUNDED_STUNNED \
			and fstate_before == FlightState.AIRBORNE:
		await _knockdown_effect()
	elif _has_flight and _flight < flight_before:
		await _flight_stack_effect()

	# Player side, same rules.
	if p_blk > 0 and p_hp > 0:
		_spawn_float("-%d" % p_blk, _player_point() + Vector2(-52.0, 26.0), COLOUR_BLOCK)
	if p_hp > 0:
		await _hit_reaction(_player_sprite_node, -PLAYER_RECOIL)
		_spawn_float("-%d" % p_hp, _player_point(), COLOUR_DAMAGE)
	elif p_blk > 0:
		_flash_shield(_player_point())
		_spawn_float("-%d" % p_blk, _player_point(), COLOUR_BLOCK)

	if gained_weak > 0:
		await _pulse_weak()
	if drawn > 0:
		# Draw/utility effect: the Focus eye appears over the player at the same
		# 4x the intent icons use, the REAL number of cards drawn floats up in the
		# same style as gained Block, and the Draw pile gives a small pulse.
		_spawn_focus_eye(_player_point() - Vector2(0.0, 70.0))
		_spawn_float("+%d" % drawn, _player_point() - Vector2(0.0, 26.0), COLOUR_BLOCK)
		await _pulse_draw_pile()


## Tint + recoil away from the attacker, then restore the EXACT original position
## and modulation. No screen shake, no scale change.
func _hit_reaction(node: CanvasItem, dx: float) -> void:
	var base: Vector2 = node.position
	var base_colour: Color = node.modulate
	var out := create_tween()
	out.set_parallel(true)
	out.tween_method(func(p: Vector2) -> void: _set_pixel_pos(node, p),
		base, base + Vector2(dx, 0.0), HIT_RECOIL_TIME).set_ease(Tween.EASE_OUT)
	out.tween_property(node, "modulate", TINT_HIT, HIT_TINT_TIME)
	await out.finished
	var back := create_tween()
	back.set_parallel(true)
	back.tween_method(func(p: Vector2) -> void: _set_pixel_pos(node, p),
		base + Vector2(dx, 0.0), base, HIT_RETURN_TIME).set_ease(Tween.EASE_OUT)
	back.tween_property(node, "modulate", base_colour, HIT_RETURN_TIME)
	await back.finished
	node.position = base
	node.modulate = base_colour


## Block gained: shield + "+N" (the real delta) + a pulse on that character's bar.
## The status display has already switched to Block mode at impact.
func _block_gain_effect(is_player: bool, amount: int) -> void:
	var at: Vector2 = _player_point() if is_player else _spider_point()
	_spawn_shield(at - Vector2(0.0, 96.0), false)
	_spawn_float("+%d" % amount, at - Vector2(0.0, 26.0), COLOUR_BLOCK)
	var bar: StatusBar = _player_bar if is_player else _selected_enemy_status_bar()
	await _pulse_node(bar.root as Control, 1.35, 3.0, BAR_PULSE_TIME)


## One Flight stack spent. The number has already been updated by _update_hud, so
## this is only the restrained acknowledgement: a brief brightening of the readout.
func _flight_stack_effect() -> void:
	var flight_icon: TextureRect = _selected_enemy_flight_icon()
	if flight_icon == null or not is_instance_valid(flight_icon):
		return
	var base: Color = flight_icon.modulate
	var t := create_tween()
	t.tween_property(flight_icon, "modulate", Color(1.6, 1.6, 1.6, 1.0), FLIGHT_PULSE_TIME * 0.5)
	t.tween_property(flight_icon, "modulate", base, FLIGHT_PULSE_TIME * 0.5)
	await t.finished


## Flight broken: the enemy drops to the ground and lands heavily. The drop is a
## whole-pixel offset from the stored rest position, so repeated cycles can never
## drift, and the grounded artwork is swapped in when the encounter supplied one.
func _knockdown_effect() -> void:
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	var air: Vector2 = _enemy_air_position()
	var ground: Vector2 = _enemy_rest_position_for_selected().round()
	if _enemy_ground_anim != StringName() \
			and actor_sprite.sprite_frames != null \
			and actor_sprite.sprite_frames.has_animation(_enemy_ground_anim):
		# The enemy brought its own knocked-down animation: just play it.
		actor_sprite.play(_enemy_ground_anim)
	elif _enemy_frames_ground != null:
		actor_sprite.sprite_frames = _enemy_frames_ground
		actor_sprite.play(&"ground")
	var t := create_tween()
	t.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
		air, ground, KNOCKDOWN_TIME).set_ease(Tween.EASE_IN)
	await t.finished
	actor_sprite.position = ground
	# Heavier landing response: pulse this enemy's own bar, not the whole group.
	var status_bar: StatusBar = _selected_enemy_status_bar()
	await _pulse_node(status_bar.root as Control, 1.4, 3.0, BAR_PULSE_TIME)


## Flight restored: the enemy rises back to exactly its airborne hover position.
func _takeoff_effect() -> void:
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	if _enemy_frames_air != null:
		actor_sprite.sprite_frames = _enemy_frames_air
	_play_enemy_anim(_enemy_idle_anim, true)
	var air: Vector2 = _enemy_air_position()
	var t := create_tween()
	t.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
		actor_sprite.position, air, TAKEOFF_TIME).set_ease(Tween.EASE_OUT)
	await t.finished
	actor_sprite.position = air


## The stunned enemy turn: a short, restrained beat so the skipped action reads
## without pretending anything happened.
func _stun_effect() -> void:
	await _pulse_node(_enemy_bar.root as Control, 1.2, 3.0, BAR_PULSE_TIME)
	await get_tree().create_timer(0.22).timeout


## Temporary shield built from the existing BlockIntent artwork. Fades in, rises a
## little, holds, fades out and frees itself. Never clickable, never permanent.
func _spawn_shield(at: Vector2, bright: bool) -> void:
	var shield := Sprite2D.new()
	shield.texture = TEX_INTENT_DEFEND
	shield.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shield.scale = Vector2(SHIELD_SCALE, SHIELD_SCALE)
	shield.position = at.round()
	shield.modulate = Color(1, 1, 1, 0)
	_effects.add_child(shield)
	var top: Vector2 = (at - Vector2(0.0, SHIELD_RISE)).round()
	var t := create_tween()
	t.tween_property(shield, "modulate:a", 1.0 if not bright else 0.95, 0.09)
	t.parallel().tween_method(func(p: Vector2) -> void: _set_pixel_pos(shield, p),
		at.round(), top, 0.28).set_ease(Tween.EASE_OUT)
	if bright:
		t.tween_property(shield, "modulate", Color(2.0, 2.0, 2.0, 0.95), 0.07)
	t.tween_interval(0.12)
	t.tween_property(shield, "modulate:a", 0.0, 0.22)
	t.tween_callback(shield.queue_free)


## Where dealt cards emerge from: the Draw pile's visible core centre, read from
## the count label that is centred on that artwork.
func _draw_pile_point() -> Vector2:
	return _draw_count_label.position + _draw_count_label.size * 0.5


## Where spent cards land: the Discard pile's visible core centre, again read from
## its count label.
func _discard_pile_point() -> Vector2:
	return _discard_count_label.position + _discard_count_label.size * 0.5


## End-of-turn housekeeping, animated: every card still in hand flies into the
## Discard pile, shrinking as it lands. Purely visual — the real cards are hidden
## for the flight and the normal discard_hand()/rebuild happens afterwards.
## Only ever called for UNPLAYED cards; a card being played does not use this.
func _animate_hand_to_discard() -> void:
	if _slots.is_empty():
		return
	var pile: Vector2 = _discard_pile_point()
	var local_centre: Vector2 = _card_local_face_centre()
	var flying: Array[Control] = []
	for i in _slots.size():
		var card: Control = _slots[i].get_node_or_null("Card") as Control
		if card == null:
			continue
		var visual: Control = _spawn_card_visual(card)
		if visual == null:
			continue
		card.visible = false
		flying.append(visual)
	# Staggered starts, then wait only for the last one — the whole sweep takes
	# about as long as a single card's flight plus the stagger tail.
	var last: Tween = null
	for n in flying.size():
		if n > 0:
			await get_tree().create_timer(DEAL_STAGGER).timeout
		last = _fly_to_discard(flying[n], pile, local_centre)
	if last != null:
		await last.finished


## Flies one card's copy from its hand position into the Discard pile. It keeps
## its full size for most of the trip and shrinks into the pile at the end, the
## exact mirror of how a drawn card grows out of the Draw pile. The copy frees
## itself when it lands.
func _fly_to_discard(visual: Control, pile: Vector2, local_centre: Vector2) -> Tween:
	var base: Vector2 = Vector2(_card_base_scale, _card_base_scale)
	var start_centre: Vector2 = visual.position + local_centre * base.x
	var t := create_tween()
	t.tween_method(func(tv: float) -> void:
			var move: float = tv * tv * (3.0 - 2.0 * tv)
			var shrink: float = lerpf(1.0, DEAL_START_SCALE, tv * tv)
			visual.scale = base * shrink
			var centre: Vector2 = start_centre.lerp(pile, move)
			_set_pixel_pos(visual, centre - local_centre * base.x * shrink),
		0.0, 1.0, DEAL_TIME)
	var fade := create_tween()
	fade.tween_property(visual, "modulate:a", 0.0, DEAL_FADE_IN) \
		.set_delay(maxf(DEAL_TIME - DEAL_FADE_IN, 0.0))
	t.finished.connect(visual.queue_free)
	return t


## Deals the newly drawn cards in from the Draw pile, one after another. Purely
## visual — the real slots and cards are already in place, and each real card is
## simply revealed as its travelling copy lands on it.
func _animate_draw(first_new: int) -> void:
	var indices: Array[int] = []
	for i in range(maxi(first_new, 0), _slots.size()):
		indices.append(i)
	if indices.is_empty():
		return
	_dealing = true
	_apply_lock()
	# Hide every incoming card up front, so none of them pops in before its turn.
	for i in indices:
		var incoming: Control = _slots[i].get_node_or_null("Card") as Control
		if incoming != null:
			incoming.visible = false
	for n in indices.size():
		if n > 0:
			await get_tree().create_timer(DEAL_STAGGER).timeout
		await _deal_one_card(indices[n])
	_dealing = false
	_apply_lock()


## The card FACE's centre in the Card node's own local space, before its authored
## scale — so a copy at ANY scale can be positioned by its visible centre.
func _card_local_face_centre() -> Vector2:
	var base: float = maxf(_card_base_scale, 0.001)
	return (_card_face_rect.position - CARD_OFFSET + _card_face_rect.size * 0.5) / base


## Flies one card's copy out of the Draw pile into its resting slot, growing from
## a small card tucked behind the pile icon to full size on arrival. The landing
## position and scale are exact, so the hand is pixel-identical afterwards.
func _deal_one_card(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var card: Control = _slots[index].get_node_or_null("Card") as Control
	if card == null:
		return
	var visual: Control = _spawn_card_visual(card)
	if visual == null:
		return
	card.visible = false
	var start_centre: Vector2 = _draw_pile_point()
	var end_centre: Vector2 = Vector2(_target_x[index], _target_y[index]) \
		+ _card_face_rect.position + _card_face_rect.size * 0.5
	var local_centre: Vector2 = _card_local_face_centre()
	var base_scale: Vector2 = card.scale
	# Fade in quickly so it reads as emerging from behind the pile, not popping on
	# top of it.
	visual.modulate = Color(1, 1, 1, 0)
	var fade := create_tween()
	fade.tween_property(visual, "modulate:a", 1.0, DEAL_FADE_IN)
	var t := create_tween()
	t.tween_method(func(tv: float) -> void:
			# Position travels on an even smoothstep, but the SIZE deliberately
			# grows on a slower curve: the card stays small behind the pile for the
			# first half of the flight, then blooms into full size as it settles
			# into the hand — otherwise it reads as simply appearing.
			var move: float = tv * tv * (3.0 - 2.0 * tv)
			var grow: float = lerpf(DEAL_START_SCALE, 1.0, tv * tv)
			visual.scale = base_scale * grow
			var centre: Vector2 = start_centre.lerp(end_centre, move)
			_set_pixel_pos(visual, centre - local_centre * base_scale.x * grow),
		0.0, 1.0, DEAL_TIME)
	await t.finished
	if is_instance_valid(card):
		card.visible = true
	_cleanup_visual(visual)


## Shield flash for absorbed damage.
func _flash_shield(at: Vector2) -> void:
	_spawn_shield(at, true)


## Temporary Focus eye over the player for draw/utility effects. Same artwork
## treatment as the intent icons: integer scale, Nearest filtering, pixel-snapped,
## mouse-transparent — and it frees itself when it is done.
func _spawn_focus_eye(at: Vector2) -> void:
	var eye := Sprite2D.new()
	eye.texture = TEX_FOCUS_EYE
	eye.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	eye.scale = Vector2(EFFECT_ICON_SCALE, EFFECT_ICON_SCALE)
	eye.position = at.round()
	eye.modulate = Color(1, 1, 1, 0)
	_effects.add_child(eye)
	var base: Vector2 = at.round()
	var top: Vector2 = (at - Vector2(0.0, SHIELD_RISE)).round()
	var t := create_tween()
	t.tween_property(eye, "modulate:a", 1.0, 0.10)
	t.parallel().tween_method(func(p: Vector2) -> void: _set_pixel_pos(eye, p),
		base, top, 0.30).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.30)
	t.tween_property(eye, "modulate:a", 0.0, 0.24)
	t.tween_callback(eye.queue_free)


## Temporary floating value in the existing Determination font, showing a REAL
## state delta. Rises and fades, then frees itself.
func _spawn_float(text: String, at: Vector2, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", FLOAT_FONT)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(120.0, 44.0)
	label.position = (at - label.size * 0.5).round()
	_effects.add_child(label)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position", label.position + Vector2(0.0, -FLOAT_RISE),
		FLOAT_TIME).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, FLOAT_TIME).set_delay(0.12)
	t.chain().tween_callback(label.queue_free)


## Brief brighten + tiny bop, restoring the exact original position and colour.
func _pulse_node(node: CanvasItem, amount: float, distance: float, time: float) -> void:
	var base: Vector2 = node.position
	var base_colour: Color = node.modulate
	var half: float = maxf(time * 0.5, 0.05)
	var out := create_tween()
	out.set_parallel(true)
	out.tween_method(func(p: Vector2) -> void: _set_pixel_pos(node, p),
		base, base - Vector2(0.0, distance), half).set_ease(Tween.EASE_OUT)
	out.tween_property(node, "modulate", base_colour * amount, half)
	await out.finished
	var back := create_tween()
	back.set_parallel(true)
	back.tween_method(func(p: Vector2) -> void: _set_pixel_pos(node, p),
		base - Vector2(0.0, distance), base, half).set_ease(Tween.EASE_IN_OUT)
	back.tween_property(node, "modulate", base_colour, half)
	await back.finished
	node.position = base
	node.modulate = base_colour


## Anticipation pulse on the intent that is currently on display.
func _pulse_intent() -> void:
	var intent_icon: CanvasItem = _intent_icon
	if not _enemy_group_hp.is_empty() and _selected_enemy < _enemy_group_intent_icons.size():
		intent_icon = _enemy_group_intent_icons[_selected_enemy]
	await _pulse_node(intent_icon, 1.5, 4.0, INTENT_PULSE_TIME)
	await get_tree().create_timer(0.06).timeout


## New-turn pulse: the Turn Counter image and its label move together and return
## to their exact positions, with the image brightening briefly.
func _pulse_turn_counter() -> void:
	var art_base: Vector2 = _turn_counter_art.position
	var label_base: Vector2 = _turn_label.position
	var art_colour: Color = _turn_counter_art.modulate
	var half: float = TURN_PULSE_TIME * 0.5
	var mover := func(p: Vector2) -> void:
		_turn_counter_art.position = Vector2(roundf(p.x), roundf(p.y))
		_turn_label.position = label_base + (p - art_base)
	var lift := Vector2(0.0, -5.0)
	var out := create_tween()
	out.set_parallel(true)
	out.tween_method(mover, art_base, art_base + lift, half).set_ease(Tween.EASE_OUT)
	out.tween_property(_turn_counter_art, "modulate", Color(1.3, 1.3, 1.3, 1.0), half)
	await out.finished
	var back := create_tween()
	back.set_parallel(true)
	back.tween_method(mover, art_base + lift, art_base, half).set_ease(Tween.EASE_IN_OUT)
	back.tween_property(_turn_counter_art, "modulate", art_colour, half)
	await back.finished
	_turn_counter_art.position = art_base
	_turn_label.position = label_base
	_turn_counter_art.modulate = art_colour


## Weak gained: pulse the Weak line and the intent, whose number has already been
## recomputed from the new Weak value.
func _pulse_weak() -> void:
	await _pulse_node(_enemy_weak_label, 1.5, 3.0, BAR_PULSE_TIME)
	await _pulse_node(_intent_icon, 1.5, 3.0, BAR_PULSE_TIME)


## Utility draw: a small pulse on the Draw pile.
func _pulse_draw_pile() -> void:
	await _pulse_node(_draw_count_label, 1.5, 3.0, BAR_PULSE_TIME)


## Enemy attack. A multi-hit enemy strikes several times in quick succession, each
## blow resolving on its own so Block, feedback and the animation all treat it as a
## separate hit; every other enemy commits its displayed attack exactly once.
func _enemy_attack(before: Dictionary) -> void:
	if _multi_hit_actions.has(_current_intent):
		await _enemy_flurry()
		return
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	_play_enemy_anim(_enemy_attack_anim, true)
	var base: Vector2 = actor_sprite.position
	var apex: Vector2 = base - Vector2(ENEMY_LUNGE, 0.0)
	var out := create_tween()
	# EASE_IN, not out: the active enemy accelerates INTO the hit so the strike lands
	# with weight instead of coasting gently into the apex.
	out.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
		base, apex, LUNGE_TIME).set_ease(Tween.EASE_IN)
	await out.finished
	_execute_intent(_current_intent)   # exactly what was displayed for this enemy
	_update_hud(true)
	await get_tree().create_timer(LUNGE_HIT_PAUSE).timeout
	await _play_pending_impacts()
	await _feedback_from_deltas(before)
	await _wait_for_active_hit_effects()
	var back := create_tween()
	back.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
		apex, base, LUNGE_RETURN_TIME).set_ease(Tween.EASE_OUT)
	await back.finished
	actor_sprite.position = base
	await _await_enemy_anim()
	_play_enemy_anim(_enemy_idle_anim)


## True when the intent is one of the enemy's attacks.
func _is_attack_intent(action: int) -> bool:
	return action == EnemyAction.ATTACK_1 or action == EnemyAction.ATTACK_2 \
		or action == EnemyAction.ATTACK_5 or action == EnemyAction.ATTACK_6 \
		or action == EnemyAction.ATTACK_7 or action == EnemyAction.ATTACK_WEAK


## How many separate strikes the displayed attack will land: exactly one for a normal
## enemy, or one per point of post-Weak base damage for an action listed as multi-hit.
func _intent_hit_count() -> int:
	if not _multi_hit_actions.has(_current_intent):
		return 1
	return maxi(1, _intent_base_damage())


## The damage of ONE of those strikes. Strength adds +1 per stack to EVERY strike, so
## a 2x1 flurry becomes 2x2 rather than 3x1 — the count never grows, only the bite.
func _intent_hit_damage() -> int:
	if _multi_hit_actions.has(_current_intent):
		return 1 + _enemy_strength
	return _intent_base_damage() + _enemy_strength


## Total damage the displayed attack will deal: strikes x damage per strike.
func _intent_attack_damage() -> int:
	return _intent_hit_count() * _intent_hit_damage()


## One resolved enemy strike of `amount` raw damage: the player's Block absorbs
## first and the remainder hits the player's HP. Returns [absorbed, through].
func _execute_single_hit(amount: int) -> Array:
	var absorbed: int = mini(_player_block, amount)
	_player_block = maxi(0, _player_block - absorbed)
	var through: int = amount - absorbed
	if through > 0:
		_player_hp = maxi(0, _player_hp - through)
	return [absorbed, through]


## A multi-hit attack: one quick lunge per hit, each landing its own point of damage
## with its own impact feedback, then returning to exactly the same position, so the
## flurry can never drift. Weak is spent once for the whole attack, exactly as on any
## single-attack turn.
func _enemy_flurry() -> void:
	var actor_sprite: AnimatedSprite2D = _selected_enemy_sprite()
	var total: int = _intent_hit_count()
	var weakened: bool = _enemy_weak > 0
	if weakened:
		# One stack per weakened ATTACK, never per hit.
		_enemy_weak = maxi(0, _enemy_weak - 1)
	for i in total:
		var variant: Dictionary = ATTACK_VARIANTS[i % ATTACK_VARIANTS.size()]
		_play_enemy_anim(_enemy_attack_anim, true)
		var base: Vector2 = actor_sprite.position
		var apex: Vector2 = base + (variant["offset"] as Vector2)
		var out := create_tween()
		out.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
			base, apex, float(variant["time"])).set_ease(Tween.EASE_IN)
		await out.finished
		var before: Dictionary = _combat_snapshot()
		var per_hit: int = _intent_hit_damage()
		var result: Array = _execute_single_hit(per_hit)
		if int(result[0]) > 0:
			_queue_impact(HitEffect.ImpactType.BLOCKED_HIT, _player_sprite_node)
		if int(result[1]) > 0:
			_queue_impact(HitEffect.ImpactType.STANDARD_HIT, _player_sprite_node)
		_update_hud(true)
		await get_tree().create_timer(LUNGE_HIT_PAUSE).timeout
		await _play_pending_impacts()
		_show_feedback("Enemy strikes %d/%d for %d%s — %d blocked, %d to HP." % [
			i + 1, total, per_hit, " (Weakened)" if weakened else "", int(result[0]), int(result[1])])
		await _feedback_from_deltas(before)
		await _wait_for_active_hit_effects()
		var back := create_tween()
		back.tween_method(func(p: Vector2) -> void: _set_pixel_pos(actor_sprite, p),
			apex, base, float(variant["back"])).set_ease(Tween.EASE_OUT)
		await back.finished
		actor_sprite.position = base
		# A blow that decided the fight ends the flurry: no further hits land.
		if _state != State.ACTIVE:
			return
	_play_enemy_anim(_enemy_idle_anim)


## Frees a travelling card visual if it is still alive.
func _cleanup_visual(visual: Control) -> void:
	if is_instance_valid(visual):
		visual.queue_free()


## Frees anything the effects layers are still holding.
func _clear_effects() -> void:
	for child in _effects.get_children():
		child.queue_free()
	for child in _front_effects.get_children():
		child.queue_free()


func _exit_tree() -> void:
	_clear_effects()


# --- HUD ---

## The single HUD path: every visual reads from the live fight state here.
func _group_intent_text(index: int) -> String:
	var flight_state: int = int(_enemy_group_flight_state[index])
	if flight_state == FlightState.GROUNDED_STUNNED:
		return "Stunned"
	if flight_state == FlightState.GROUNDED_RECOVERY:
		return "Take Off"
	var action: int = _enemy_group_intents[index]
	match action:
		EnemyAction.DEFEND_2:
			return "Block %d" % ENEMY_DEFEND_BLOCK
		EnemyAction.DEFEND_3:
			return "Block 3"
		EnemyAction.STRENGTHEN:
			return "Strengthen"
	var attack_text: String = "Attack %d" % _intent_attack_damage_for(action, index)
	if action == EnemyAction.ATTACK_WEAK:
		attack_text += " + Weak 2"
	return attack_text


func _intent_attack_damage_for(action: int, index: int) -> int:
	var base: int = 4
	match action:
		EnemyAction.ATTACK_1:
			base = 2
		EnemyAction.ATTACK_5:
			base = 5
		EnemyAction.ATTACK_6:
			base = 10
		EnemyAction.ATTACK_7:
			base = 6
	var enemy_weak: int = _enemy_group_weak[index]
	if enemy_weak > 0:
		base = floori(float(base) * 0.5)
	var enemy_strength: int = _enemy_group_strength[index]
	if _multi_hit_actions.has(action):
		return maxi(1, base) * (1 + enemy_strength)
	return base + enemy_strength


func _update_group_widgets() -> void:
	for index: int in range(_enemy_group_hp.size()):
		if index >= _enemy_group_status_bars.size():
			continue
		var enemy_alive: bool = _enemy_group_hp[index] > 0
		if index < _enemy_group_status_bars.size():
			var real_bar: StatusBar = _enemy_group_status_bars[index]
			_sync_status_bar(real_bar, _enemy_group_hp[index], _enemy_group_max_hp[index],
				_enemy_group_block[index])
			real_bar.root.visible = _enemy_group_hp[index] > 0
			real_bar.hp_label.visible = _enemy_group_hp[index] > 0
			real_bar.block_label.visible = _enemy_group_hp[index] > 0 and _enemy_group_block[index] > 0
		var flight_state: int = int(_enemy_group_flight_state[index])
		var is_stunned: bool = flight_state == FlightState.GROUNDED_STUNNED
		var is_recovering: bool = flight_state == FlightState.GROUNDED_RECOVERY
		if index < _enemy_group_intent_labels.size():
			_enemy_group_intent_labels[index].text = _group_intent_text(index) if enemy_alive else "Defeated"
		if index < _enemy_group_intent_icons.size():
			var group_intent_icon: Sprite2D = _enemy_group_intent_icons[index]
			group_intent_icon.texture = TEX_STATUS_FLYING if is_recovering \
				else _group_intent_texture(_enemy_group_intents[index])
			group_intent_icon.visible = enemy_alive and not is_stunned
		if index < _enemy_group_status_labels.size():
			_enemy_group_flight_icons[index].visible = _has_flight and _enemy_group_hp[index] > 0
			_enemy_group_weak_icons[index].visible = _enemy_group_weak[index] > 0
			_enemy_group_strength_icons[index].visible = _enemy_group_strength[index] > 0
			var flight_active: bool = _has_flight and _enemy_group_hp[index] > 0
			var weak_active: bool = _enemy_group_weak[index] > 0 and _enemy_group_hp[index] > 0
			var strength_active: bool = _enemy_group_strength[index] > 0 and _enemy_group_hp[index] > 0
			_enemy_group_flight_counts[index].text = str(_enemy_group_flight[index])
			_enemy_group_weak_counts[index].text = str(_enemy_group_weak[index])
			_enemy_group_strength_counts[index].text = str(_enemy_group_strength[index])
			_enemy_group_flight_counts[index].visible = flight_active
			_enemy_group_weak_counts[index].visible = weak_active
			_enemy_group_strength_counts[index].visible = strength_active
			var extra_status: Array[String] = []
			for status_name: String in _enemy_group_status[index].keys():
				var status_value: int = int(_enemy_group_status[index][status_name])
				if status_value > 0:
					extra_status.append("%s %d" % [status_name.capitalize(), status_value])
			var status_label: Label = _enemy_group_status_labels[index]
			status_label.text = " ".join(extra_status)
			status_label.visible = _enemy_group_hp[index] > 0 \
				and (flight_active or weak_active or strength_active or not extra_status.is_empty())


func _update_hud(animate_fill: bool = false) -> void:
	var grouped: bool = not _enemy_group_hp.is_empty()
	_enemy_bar.root.visible = not grouped
	_sync_status_bar(_player_bar, _player_hp, PLAYER_MAX_HP, _player_block, animate_fill)
	if grouped:
		_update_group_widgets()
	_sync_status_bar(_enemy_bar, _enemy_hp, _enemy_max_hp, _enemy_block, animate_fill)
	# Weak and Flight are each an icon with a single stack number beside it, and both
	# rows are hidden entirely when they do not apply. Flight is hidden on victory
	# and defeat along with the rest of the enemy state.
	var strength_active: bool = _enemy_strength > 0
	_strength_icon.visible = strength_active
	_strength_label.visible = strength_active
	_strength_label.text = str(_enemy_strength)
	var weak_active: bool = _enemy_weak > 0
	_weak_icon.visible = weak_active
	_enemy_weak_label.visible = weak_active
	_enemy_weak_label.text = str(_enemy_weak)
	# The player's own Weak, shown the same way on their side of the screen.
	var player_weak_active: bool = _player_weak > 0
	_player_weak_icon.visible = player_weak_active
	_player_weak_label.visible = player_weak_active
	_player_weak_label.text = str(_player_weak)
	var flight_active: bool = _has_flight and _enemy_hp > 0 and _state == State.ACTIVE
	_flight_icon.visible = flight_active
	_flight_label.visible = flight_active
	if flight_active:
		match _flight_state:
			FlightState.AIRBORNE:
				_flight_label.text = str(_flight)
				_flight_label.add_theme_font_size_override("font_size", STATUS_FONT)
			FlightState.GROUNDED_STUNNED:
				_flight_label.text = "Stunned"
				_flight_label.add_theme_font_size_override("font_size", STATUS_WORD_FONT)
			_:
				_flight_label.text = "Grounded"
				_flight_label.add_theme_font_size_override("font_size", STATUS_WORD_FONT)
	_energy_label.text = "%d/%d" % [_energy, ENERGY_PER_TURN]
	_draw_count_label.text = str(_draw_pile.size())
	_discard_count_label.text = str(_discard_pile.size())
	# Derived FROM turn_number, which stays the single source of truth.
	_turn_label.text = "TURN %d" % turn_number
	# The victory/defeat banner only appears once the final impact feedback has
	# finished, so the last hit is never hidden behind the result text.
	_result_label.visible = not animation_busy
	# Enemy action display. While stunned the queued action is hidden rather than
	# replaced, and while grounded the enemy's only possible action is taking off
	# again — so that is what is shown, using the Flight icon. The player is never
	# shown one action and then given another.
	var alive: bool = _enemy_hp > 0
	var show_action: bool = alive and _flight_state != FlightState.GROUNDED_STUNNED
	_intent_icon.visible = show_action
	_intent_label.visible = show_action
	if show_action:
		# The readout uses its authored size unless a case below asks for the smaller
		# one, so no case can inherit another case's sizing.
		_intent_label.add_theme_font_size_override("font_size", INTENT_FONT)
		if _flight_state == FlightState.GROUNDED_RECOVERY:
			# Taking off: drawn smaller than an intent and with no number beside it,
			# because it is a manoeuvre rather than an attack.
			_intent_icon.texture = TEX_STATUS_FLYING
			_intent_icon.scale = Vector2(FLIGHT_INTENT_SCALE, FLIGHT_INTENT_SCALE)
			_intent_label.visible = false
		else:
			_intent_icon.scale = Vector2(INTENT_ICON_SCALE, INTENT_ICON_SCALE)
			match _current_intent:
				EnemyAction.DEFEND_2, EnemyAction.DEFEND_3:
					_intent_icon.texture = TEX_INTENT_DEFEND
					_intent_label.text = str(_intent_block_value())
				EnemyAction.STRENGTHEN:
					# A scheduled move, shown in advance exactly like any other action —
					# drawn smaller than a blow, and with no number over it.
					_intent_icon.texture = TEX_STATUS_STRENGTH
					_intent_icon.scale = Vector2(STRENGTH_INTENT_SCALE, STRENGTH_INTENT_SCALE)
					_intent_label.visible = false
				_:
					# A strike that carries a debuff gets its own icon, so the extra effect
					# is still disclosed while the readout stays a plain damage number.
					_intent_icon.texture = TEX_INTENT_ATTACK_DEBUFF \
						if _intent_player_weak() > 0 else TEX_INTENT_ATTACK
					# A multi-hit enemy reads as "count x damage per strike", so the player
					# can see both how many blows are coming and how hard each lands. That
					# form is taller than a plain total, so it is drawn a little smaller.
					var hits: int = _intent_hit_count()
					if hits > 1:
						_intent_label.text = "%dx%d" % [hits, _intent_hit_damage()]
						_intent_label.add_theme_font_size_override("font_size", INTENT_MULTI_FONT)
					else:
						_intent_label.text = str(_intent_attack_damage())
	# The backing silhouette follows whatever the action icon ended up showing, sitting
	# slightly larger behind it so the icon reads over any enemy artwork.
	_intent_icon_backing.visible = show_action
	_intent_icon_backing.texture = _intent_icon.texture
	_intent_icon_backing.position = _intent_icon.position
	_intent_icon_backing.scale = _intent_icon.scale * 1.18
	# The hover target tracks the icon, which changes size with the intent.
	if _intent_hover != null:
		_intent_hover.visible = show_action
		if _intent_icon.texture != null:
			var span: Vector2 = _intent_icon.texture.get_size() * _intent_icon.scale
			_intent_hover.size = span
			_intent_hover.position = (_intent_icon.position - span * 0.5).round()
	if grouped:
		_enemy_bar.root.visible = false
		_enemy_bar.hp_label.visible = false
		_enemy_bar.block_label.visible = false
		_intent_icon.visible = false
		_intent_label.visible = false
		_intent_icon_backing.visible = false
		_intent_hover.visible = false
		_strength_icon.visible = false
		_strength_label.visible = false
		_weak_icon.visible = false
		_enemy_weak_label.visible = false
		_flight_icon.visible = false
		_flight_label.visible = false
	_apply_lock()


## Locks all interaction once the fight is decided, and while an animation, a deal
## or an enemy action is resolving.
func _apply_lock() -> void:
	var active: bool = _state == State.ACTIVE and not animation_busy and not _dealing and not _tutorial_active
	_end_turn_button.disabled = not active
	_refresh_end_turn_art()
	for slot in _hand_container.get_children():
		var handle := slot.get_node_or_null("DragHandle") as Control
		if handle:
			handle.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func _show_feedback(message: String) -> void:
	_feedback_label.text = message
	_feedback_token += 1
	var token: int = _feedback_token
	await get_tree().create_timer(2.0).timeout
	if _feedback_token == token:
		_feedback_label.text = ""
