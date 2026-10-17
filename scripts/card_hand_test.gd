class_name CardHandTest
extends Control
## Prototype hand / deck interaction test.
##
## Cards are played either by dragging them from the hand onto the Play Area, or
## by pressing the number key shown above each card (1 = leftmost). Both inputs
## go through the single try_play_card() path. Energy = ENERGY_PER_TURN / turn.
##
## Interaction test only: no damage, Block, Weak, Focus draw or Throw Stone
## Consume yet. A played card is simply moved from the hand to the discard pile.

const CARD_SCENE: PackedScene = preload("res://card.tscn")
const HAND_SIZE: int = 4
const ENERGY_PER_TURN: int = 3
const SLOT_SIZE: Vector2 = Vector2(222, 294)
## Matches the Card's offset inside the original CardSlot.
const CARD_OFFSET: Vector2 = Vector2(-12, 0)
## Drag-handle geometry is derived at runtime from the card's visible face
## (see _card_face_rect_for) so a handle never covers a neighbouring card.

## Deck contents — one entry per card copy. Edit freely; duplicates are allowed.
## 11 copies: 4 Long Stick, 4 Bark Shield, 1 Heavy Swing, 1 Throw Stone, 1 Focus.
const DECK_PATHS: Array[String] = [
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/long_stick.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/bark_shield.tres",
	"res://resources/cards/heavy_swing.tres",
	"res://resources/cards/throw_stone.tres",
	"res://resources/cards/focus.tres",
]

@onready var _hand_container: HBoxContainer = $HandContainer
@onready var _counts_label: Label = $CountsLabel
@onready var _energy_label: Label = $EnergyLabel
@onready var _feedback_label: Label = $FeedbackLabel
@onready var _end_turn_button: Button = $EndTurnButton
@onready var _play_area: Control = $PlayArea
@onready var _play_area_label: Label = $PlayArea/PlayAreaLabel

var _draw_pile: Array[CardData] = []
var _hand: Array[CardData] = []
var _discard_pile: Array[CardData] = []
var _energy: int = ENERGY_PER_TURN
var _feedback_token: int = 0
## The card's visible face relative to its slot origin, derived once from the
## Frame texture's opaque pixels. Drag handles are sized from this so they cover
## exactly what is drawn instead of the Frame's transparent margins.
var _card_face_rect: Rect2 = Rect2()
var _card_face_ready: bool = false
## The Card hidden because it is currently being dragged (restored on drag end).
var _drag_source_card: Control = null


## Invisible hit area laid over a hand card. Starts a drag carrying its index.
class CardDragHandle extends Control:
	var test_root: Node
	var hand_index: int = -1
	var card_node: Control
	## Where the card's visible face starts relative to the Card node's origin.
	var face_offset: Vector2 = Vector2.ZERO

	func _get_drag_data(at_position: Vector2) -> Variant:
		if test_root == null or hand_index < 0:
			return null
		if card_node:
			# Godot puts the drag preview's root at the mouse pointer, so wrap the
			# card and shift it inside the wrapper by the grab point measured from
			# the card's own origin. That keeps the grabbed pixel under the cursor
			# instead of the card's top-left corner.
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

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if test_root:
			test_root.try_play_card(int(data.get("index", -1)))


func _ready() -> void:
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_create_drop_zone()
	_play_area_label.text = "PLAY AREA  —  drag a card here, or press %s" % _hand_hint()
	_build_deck()
	_energy = ENERGY_PER_TURN
	draw_cards(HAND_SIZE)
	_update_hud()


## "1 / 2 / 3 / ..." hotkey hint derived from HAND_SIZE.
func _hand_hint() -> String:
	var parts: Array[String] = []
	for i in HAND_SIZE:
		parts.append(str(i + 1))
	return " / ".join(parts)


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
## while keeping its slot, so the rest of the hand does not move.
func _begin_drag(handle: Node) -> void:
	_drag_source_card = handle.card_node as Control
	if _drag_source_card:
		_drag_source_card.visible = false


## Restores a hidden source card once the drag is over — cancelled, or a play
## that failed (e.g. not enough energy). A successful play rebuilds the hand via
## try_play_card(), so the old card is simply discarded.
func _process(_delta: float) -> void:
	if _drag_source_card == null:
		return
	if not get_viewport().gui_is_dragging():
		if is_instance_valid(_drag_source_card):
			_drag_source_card.visible = true
		_drag_source_card = null


# --- Deck / piles ---

## Builds the draw pile from DECK_PATHS and shuffles it.
func _build_deck() -> void:
	_draw_pile.clear()
	_hand.clear()
	_discard_pile.clear()
	for path in DECK_PATHS:
		var data: CardData = load(path) as CardData
		if data:
			_draw_pile.append(data)
		else:
			push_warning("CardHandTest: could not load card at %s" % path)
	_draw_pile.shuffle()


## Draws up to `count` cards into the hand. When the draw pile runs out mid-draw
## the discard pile is shuffled back into it and drawing continues.
func draw_cards(count: int) -> void:
	for _i in count:
		if _draw_pile.is_empty():
			_recycle_discard()
		if _draw_pile.is_empty():
			break  # Nothing left in draw or discard.
		_hand.append(_draw_pile.pop_back())
	_rebuild_hand()
	_update_hud()


## Moves the entire hand into the discard pile.
func discard_hand() -> void:
	_discard_pile.append_array(_hand)
	_hand.clear()


## Shuffles the discard pile back into the draw pile.
func _recycle_discard() -> void:
	if _discard_pile.is_empty():
		return
	_draw_pile.append_array(_discard_pile)
	_discard_pile.clear()
	_draw_pile.shuffle()


# --- Playing cards ---

## The single play path used by BOTH drag-and-drop and the number hotkeys.
## Returns true if a card was played.
func try_play_card(index: int) -> bool:
	if index < 0 or index >= _hand.size():
		if index >= 0:
			_show_feedback("No card in slot %d." % (index + 1))
		return false
	var data: CardData = _hand[index]
	if data.energy_cost > _energy:
		_show_feedback("Not enough energy — %s needs %d, you have %d." % [
			data.card_name, data.energy_cost, _energy])
		return false
	_energy -= data.energy_cost
	_hand.remove_at(index)
	_discard_pile.append(data)
	_rebuild_hand()
	_update_hud()
	_show_feedback("Played %s." % data.card_name)
	return true


func _on_end_turn_pressed() -> void:
	discard_hand()
	_energy = ENERGY_PER_TURN
	draw_cards(HAND_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var code: int = key.keycode
			if code >= KEY_1 and code <= KEY_9:
				try_play_card(code - KEY_1)


# --- Hand display ---

## Rebuilds the visible hand from _hand, creating one slot + Card per card.
func _rebuild_hand() -> void:
	for child in _hand_container.get_children():
		_hand_container.remove_child(child)
		child.queue_free()
	for i in _hand.size():
		_create_hand_slot(i)


func _create_hand_slot(index: int) -> void:
	var slot := Control.new()
	slot.name = "Slot%d" % (index + 1)
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_container.add_child(slot)

	var card := CARD_SCENE.instantiate() as Card
	slot.add_child(card)
	card.card_data = _hand[index]
	card.position = CARD_OFFSET
	# Card visuals are display-only and overlap the neighbouring card, so they
	# must not swallow mouse input: only the drag handles receive clicks.
	_set_mouse_ignore(card)

	# Invisible drag handle sized to the card's visible face, drawn on top. Its
	# width is clipped to the slot spacing so it never reaches into the next
	# card's clickable strip (the last card keeps its full face).
	var face: Rect2 = _card_face_rect_for(card)
	var handle := CardDragHandle.new()
	handle.name = "DragHandle"
	handle.test_root = self
	handle.hand_index = index
	handle.card_node = card
	handle.face_offset = face.position - CARD_OFFSET
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.add_child(handle)
	handle.position = face.position
	var handle_width: float = face.size.x
	if index < _hand.size() - 1:
		var spacing: float = SLOT_SIZE.x + float(_hand_container.get_theme_constant("separation"))
		handle_width = minf(face.size.x, spacing)
	handle.size = Vector2(handle_width, face.size.y)

	# Hand-position number, above the card and on top of the handle.
	var number := Label.new()
	number.name = "Number"
	number.text = str(index + 1)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.add_theme_font_size_override("font_size", 22)
	number.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	number.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	number.add_theme_constant_override("outline_size", 6)
	slot.add_child(number)
	number.position = Vector2(4, -38)
	number.size = Vector2(48, 32)


## Returns (and caches) the card's visible face relative to its slot origin,
## derived from the Frame texture's non-transparent pixels.
func _card_face_rect_for(card: Control) -> Rect2:
	if _card_face_ready:
		return _card_face_rect
	var frame := card.get_node_or_null("Frame") as TextureRect
	if frame and frame.texture and frame.size.x > 0.0:
		var tex_size := Vector2(frame.texture.get_width(), frame.texture.get_height())
		var bbox := _texture_alpha_bbox(frame.texture)
		var in_frame := frame.size / tex_size
		var local_pos: Vector2 = frame.position + bbox.position * in_frame
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


# --- HUD ---

func _update_hud() -> void:
	_counts_label.text = "Draw: %d    Hand: %d    Discard: %d" % [
		_draw_pile.size(), _hand.size(), _discard_pile.size()]
	_energy_label.text = "Energy: %d / %d" % [_energy, ENERGY_PER_TURN]


func _show_feedback(message: String) -> void:
	_feedback_label.text = message
	_feedback_token += 1
	var token: int = _feedback_token
	await get_tree().create_timer(2.0).timeout
	if _feedback_token == token:
		_feedback_label.text = ""
