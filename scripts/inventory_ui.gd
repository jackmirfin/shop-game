extends CanvasLayer
## The player's inventory, on screen.
##
## An autoload, so it belongs to no level and is available everywhere. It does NOT pause
## the game: the world keeps running behind it and it simply draws over the top. Toggled
## with I.
##
## The layout is MEASURED from the art rather than guessed. Both source images are 320x316
## canvases that are mostly empty; the drawn panels sit inside them, and these regions are
## their opaque bounds:
##   Top-Inventory.png   x 50..269, y 105..174   (220 x 70)  -> the header
##   9-Inventory.png     x 131..208, y 132..212  (78 x 81)   -> the slot grid
## 78 and 81 divide exactly by three, so the grid is a 3x3 of 26x27 slots.
##
## The header is itself two panels: the left one carries the player sprite, health and
## coin, and the right one is the 2x2 crafting grid — left empty for now.

const ART_SCALE: float = 4.0
const TOP_REGION := Rect2(50.0, 105.0, 220.0, 70.0)
const GRID_REGION_9 := Rect2(131.0, 132.0, 78.0, 81.0)
const GRID_REGION_18 := Rect2(128.0, 113.0, 150.0, 83.0)
const SLOT_REGION_9 := Rect2(134.0, 138.0, 70.0, 69.0)
const SLOT_REGION_18 := Rect2(136.0, 122.0, 137.0, 65.0)
const GRID_COLS_9: int = 3
const GRID_COLS_18: int = 6
const GRID_ROWS: int = 3
## Space between the header and the grid beneath it.
const GAP: float = 20.0
const FADE_COLOUR := Color(0.0, 0.0, 0.0, 0.55)
## The two header panels, in the header region's own coordinates.
const HEADER_LEFT := Rect2(0.0, 0.0, 150.0, 70.0)
const HEADER_RIGHT := Rect2(150.0, 0.0, 70.0, 70.0)
## The drawn 3x3 of slots INSIDE the grid art, measured from the dark interiors of the
## squares themselves: they run x 3..73 and y 6..75 OF THE ART, which in the source PNG's
## own coordinates is x 134..204 and y 138..207 — not the image's full 78x81 bounds.
## Laying the squares on the whole image made them overhang the drawn slots.
## The 9-slot inner bounds are kept separately from the 18-slot measurements above.
## Both are expressed in their source PNG coordinates and converted through ART_SCALE.
## Areas inside the left header panel, in the art's own pixels, measured from the panel
## itself. The health figures are the channel INSIDE the bar's frame (the frame runs
## x 67..118, y 17..30 of the art).
const SPRITE_AREA := Rect2(8.0, 8.0, 36.0, 51.0)
const HEALTH_AREA := Rect2(70.0, 19.0, 46.0, 10.0)
## The measured dark interior runs 47 source pixels wide (x 120..166 in the sheet).
const HEALTH_FILL_WIDTH: float = 47.0
const COIN_AREA := Rect2(84.0, 38.0, 28.0, 16.0)
## How big the player's portrait is drawn. 5x fits the portrait field with room around it,
## and the sprite's own offset is what centres the art in that field.
const SPRITE_SCALE: float = 5.0
## Small horizontal correction for the Inventory-only portrait preview; world player layout is untouched.
const PREVIEW_POSITION_OFFSET := Vector2(12.0, 0.0)

const TEX_TOP: Texture2D = preload("res://assets/Inventory/Top-Inventory.png")
const TEX_GRID_9: Texture2D = preload("res://assets/Inventory/9-Inventory.png")
const TEX_GRID_18: Texture2D = preload("res://assets/Inventory/18-inventory.png")
const TEX_HEALTH_FILL: Texture2D = preload("res://assets/Combat/HealthBarInterior.png")
const GOD_ITEM_CARD_ART: Texture2D = preload("res://assets/Cards/Common_Card_Template.png")
const PLAYER_SCENE: String = "res://scenes/player.tscn"
## The project's own font. Every piece of text this interface draws uses it.
const UI_FONT: Font = preload("res://assets/Fonts/cardfont.ttf")
## Text sizes. The panels are drawn at 3-4x, so text has to stay small relative to them —
## a number 60-odd pixels tall dwarfs the artwork it sits in.
const GOLD_FONT: int = 32
const GOLD_LABEL_Y_OFFSET: float = 3.0
const PROMPT_FONT: int = 22

## The one-column composition: the header's top-left corner is the whole interface's
## origin, and every panel is placed from it. Kept as constants so the two-column layout
## can scale the interface as a unit from the same numbers.
const COMPOSITION_HOME := Vector2(200.0, 48.0)
const HEADER_HOME := Vector2(200.0, 48.0)
const GRID_HOME := Vector2(484.0, 348.0)
const PROMPT_HOME := Vector2(484.0, 676.0)
## How much the inventory side shrinks when the deck panel joins it, so the two halves fit
## side by side without either being crowded off the screen.
const TWO_COLUMN_SCALE: float = 0.75
const LAYOUT_MARGIN: float = 24.0
const COLUMN_GAP: float = 24.0

var _root: Control = null
var _slots: Array[Button] = []
var _icons: Array[TextureRect] = []
var _health_fill: TextureRect = null
var _coin_label: Label = null
var _held_icon: TextureRect = null
var _held: InventoryItem = null
var _held_from: int = -1
var _grid_art: TextureRect = null
var _grid_home: Vector2 = Vector2.ZERO
var _header_home: Vector2 = Vector2.ZERO
var _grid_capacity: int = 0
var _god_panel: Control = null
var _god_drag_icon: TextureRect = null
var _god_held: InventoryItem = null
var _god_opened_inventory: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90                      # above the world, below nothing that matters
	_build()
	visible = false
	Inventory.changed.connect(_refresh)
	# Draw the current state straight away, so the gold and the health bar are right the
	# first time the inventory is opened rather than waiting for something to change.
	_refresh()


## Toggles the inventory. Nothing here pauses the tree, so the world carries on.
func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()
	else:
		_drop_held()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_G:
		_toggle_god_menu()
		get_viewport().set_input_as_handled()
		return
	var encounter: Node = get_node_or_null("/root/EncounterManager")
	var combat: Node = get_tree().get_first_node_in_group("combat")
	if (encounter != null and encounter.has_method("is_busy") and encounter.is_busy()) or combat != null:
		if event is InputEventKey:
			var combat_key: InputEventKey = event as InputEventKey
			if combat_key.pressed and not combat_key.echo and combat_key.physical_keycode == KEY_I:
				get_viewport().set_input_as_handled()
				if visible:
					hide()
		return
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_I:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_E and visible:
		# Deck management is a mode of the inventory, not a second screen: E only means
		# anything while the inventory is open.
		set_deck_mode(not _deck_mode)
		get_viewport().set_input_as_handled()


# --- God menu --------------------------------------------------------------------

func _build_god_menu() -> void:
	_god_panel = Control.new()
	_god_panel.name = "GodMenu"
	_god_panel.position = Vector2(36.0, 72.0)
	_god_panel.size = Vector2(646.0, 500.0)
	_god_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_god_panel.visible = false
	_root.add_child(_god_panel)
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.055, 0.07, 0.10, 0.96)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_god_panel.add_child(background)
	var title: Label = Label.new()
	title.text = "GOD MENU  [G]"
	title.position = Vector2(16.0, 12.0)
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 24)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_god_panel.add_child(title)
	_add_god_item("Reinforced Wooden Shield", InventoryItem.make("Reinforced Wooden Shield",
		"res://assets/Inventory/Items/reinforcedwoodenshield.png", InventoryItem.Kind.SHIELD, 1,
		false, "A reinforced wooden shield. Its cards grant 5 Block."), Vector2(16.0, 54.0), true)
	_add_god_item("Aquamarine Sword IV", InventoryItem.make_sword("aquamarine", 4),
		Vector2(16.0, 142.0))
	var knife_positions: Array[Vector2] = [
		Vector2(16.0, 230.0), Vector2(16.0, 318.0), Vector2(16.0, 406.0),
		Vector2(330.0, 54.0), Vector2(330.0, 142.0),
	]
	for index: int in range(KnifeCardFactory.MATERIALS.size()):
		var material: String = KnifeCardFactory.MATERIALS[index]
		var knife: InventoryItem = InventoryItem.make_knife(material)
		_add_god_item("%s Throwing Knives" % material.capitalize(), knife, knife_positions[index], true)
	_god_drag_icon = TextureRect.new()
	_god_drag_icon.name = "GodDragIcon"
	_god_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_god_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_god_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_god_drag_icon.size = Vector2(64.0, 64.0)
	_god_drag_icon.visible = false
	_root.add_child(_god_drag_icon)


func _add_god_item(label_text: String, item: InventoryItem, at: Vector2,
		use_card_artwork: bool = false) -> void:
	var button: Button = Button.new()
	button.name = label_text.replace(" ", "")
	button.position = at
	button.size = Vector2(298.0, 82.0)
	button.text = label_text + "\nDrag into inventory"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.gui_input.connect(_on_god_item_gui_input.bind(item))
	_god_panel.add_child(button)
	if use_card_artwork:
		var card_art: TextureRect = TextureRect.new()
		card_art.name = "CardArtwork"
		card_art.texture = GOD_ITEM_CARD_ART
		card_art.position = Vector2(238.0, 2.0)
		card_art.size = Vector2(52.0, 77.0)
		card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(card_art)
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if use_card_artwork and item.icon != null:
		var icon_size: Vector2 = item.icon.get_size()
		icon.size = icon_size
		icon.position = Vector2(267.0, 36.0) - icon_size * 0.5
	else:
		icon.position = Vector2(230.0, 13.0)
		icon.size = Vector2(56.0, 56.0)
	button.add_child(icon)


func _toggle_god_menu() -> void:
	if _god_panel == null:
		return
	if _god_panel.visible:
		_god_panel.visible = false
		_god_held = null
		_god_drag_icon.visible = false
		if _god_opened_inventory:
			visible = false
		_god_opened_inventory = false
		return
	_god_opened_inventory = not visible
	visible = true
	_refresh()
	_god_panel.visible = true


func _on_god_item_gui_input(event: InputEvent, item: InventoryItem) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		_god_held = item
		_god_drag_icon.texture = item.icon
		_god_drag_icon.visible = true
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _god_held == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		for slot: Button in _slots:
			if slot.get_global_rect().has_point(mouse):
				Inventory.add_item(_god_held)
				break
		_god_held = null
		_god_drag_icon.visible = false
		get_viewport().set_input_as_handled()


# --- Building the panel ----------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "InventoryRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# PASS, not IGNORE. A Control set to IGNORE takes its WHOLE SUBTREE out of mouse
	# picking, so every tile and card below this one was unreachable — which is why the
	# polled item hover worked while the cards' own mouse_entered never fired.
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = FADE_COLOUR
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(fade)

	# The two panels are centred as a pair: the header above, the grid below it. Laid out
	# against the DESIGN resolution rather than the live window: the project stretches
	# with canvas_items, so this CanvasLayer's own coordinates are the design resolution
	# whatever size the window happens to be.
	var view := Vector2(1280.0, 720.0)
	var header_size: Vector2 = TOP_REGION.size * ART_SCALE
	var grid_region: Rect2 = _grid_region_for_capacity(Inventory.inventory_capacity)
	var grid_size: Vector2 = grid_region.size * ART_SCALE
	var total: float = header_size.y + GAP + grid_size.y
	var header_at := Vector2((view.x - header_size.x) * 0.5, (view.y - total) * 0.5)
	var grid_at := Vector2((view.x - grid_size.x) * 0.5, header_at.y + header_size.y + GAP)
	_header_home = header_at
	_grid_home = grid_at
	_grid_capacity = Inventory.inventory_capacity

	_add_art("Header", TEX_TOP, TOP_REGION, header_at)
	_grid_art = _add_grid_art(grid_region, grid_at)

	_build_header(header_at)
	_build_slots(grid_at)

	# The inventory panels are remembered so they can slide left when the deck manager
	# appears beside them. The deck panel is built once and simply hidden until then.
	_panels = [_root.get_node_or_null("Header"), _root.get_node_or_null("Grid")]
	_build_deck_manager()
	_build_god_menu()
	_build_prompt()

	# The item being moved, drawn last so it follows the cursor over everything.
	_held_icon = TextureRect.new()
	_held_icon.name = "HeldItem"
	_held_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_held_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_held_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_icon.visible = false
	_root.add_child(_held_icon)


func _grid_region_for_capacity(capacity: int) -> Rect2:
	return GRID_REGION_18 if capacity == Inventory.UPGRADED_SLOT_COUNT else GRID_REGION_9


func _grid_slot_region_for_capacity(capacity: int) -> Rect2:
	return SLOT_REGION_18 if capacity == Inventory.UPGRADED_SLOT_COUNT else SLOT_REGION_9


func _grid_columns_for_capacity(capacity: int) -> int:
	return GRID_COLS_18 if capacity == Inventory.UPGRADED_SLOT_COUNT else GRID_COLS_9


func _grid_texture_for_capacity(capacity: int) -> Texture2D:
	return TEX_GRID_18 if capacity == Inventory.UPGRADED_SLOT_COUNT else TEX_GRID_9


## Rebuilds only the visual inventory grid when the single inventory array changes capacity.
## The Inventory autoload retains the existing slots and item references unchanged.
func _rebuild_inventory_grid() -> void:
	var grid_panel_index: int = -1
	for i in _panels.size():
		var existing_panel: Control = _panels[i] as Control
		if existing_panel != null and existing_panel.name == "Grid":
			grid_panel_index = i
			_panels[i] = null
	for slot: Button in _slots:
		slot.free()
	for icon: TextureRect in _icons:
		icon.free()
	_slots.clear()
	_icons.clear()
	if _grid_art != null and is_instance_valid(_grid_art):
		_grid_art.free()
	_grid_art = null
	var view := Vector2(1280.0, 720.0)
	var header_size: Vector2 = TOP_REGION.size * ART_SCALE
	var grid_region: Rect2 = _grid_region_for_capacity(Inventory.inventory_capacity)
	var grid_size: Vector2 = grid_region.size * ART_SCALE
	var total: float = header_size.y + GAP + grid_size.y
	_header_home = Vector2((view.x - header_size.x) * 0.5, (view.y - total) * 0.5)
	_grid_home = Vector2((view.x - grid_size.x) * 0.5,
		_header_home.y + header_size.y + GAP)
	_grid_art = _add_grid_art(grid_region, _grid_home)
	_build_slots(_grid_home)
	_grid_capacity = Inventory.inventory_capacity
	if grid_panel_index >= 0:
		_panels[grid_panel_index] = _grid_art
	_layout(_deck_mode)


## One of the two drawn panels, cropped out of its mostly-empty canvas.
func _add_art(node_name: String, sheet: Texture2D, region: Rect2, at: Vector2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	var art := TextureRect.new()
	art.name = node_name
	art.texture = atlas
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = at.round()
	art.size = region.size * ART_SCALE
	_root.add_child(art)
	return art


func _add_grid_art(region: Rect2, at: Vector2) -> TextureRect:
	return _add_art("Grid", _grid_texture_for_capacity(Inventory.inventory_capacity), region, at)


## The header's contents: the player's own sprite, their health, and their coin.
func _build_header(header_at: Vector2) -> void:
	var left := header_at + HEADER_LEFT.position * ART_SCALE

	# The player, playing their idle animation rather than frozen on one frame. Its own
	# offset centres the art inside the portrait field, since the sheet draws the figure
	# low in its 48x48 cell.
	var frames: SpriteFrames = _player_frames()
	const preview_animation: StringName = &"idle_down"
	if frames != null and frames.has_animation(preview_animation):
		var sprite := AnimatedSprite2D.new()
		sprite.name = "PlayerSprite"
		sprite.sprite_frames = frames
		sprite.animation = preview_animation
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.offset = Vector2(-0.5, -8.5)
		sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		sprite.position = (left + (SPRITE_AREA.position + SPRITE_AREA.size * 0.5) * ART_SCALE
			+ PREVIEW_POSITION_OFFSET).round()
		sprite.play()
		_root.add_child(sprite)

	# Health: the fight's own interior bar, resized into its channel here. Nothing is
	# drawn behind it — the bar IS the display, not a bar on a grey plate.
	var health_at := left + HEALTH_AREA.position * ART_SCALE
	var health_size: Vector2 = HEALTH_AREA.size * ART_SCALE
	_health_fill = TextureRect.new()
	_health_fill.name = "HealthFill"
	# Cropped to the fill texture's OPAQUE strip before being stretched. The texture is a
	# 32x12 canvas with a 22x2 strip inside it, so stretching the whole canvas left the bar
	# about two thirds full however much health the player had.
	_health_fill.texture = _cropped(TEX_HEALTH_FILL, Rect2(7.0, 5.0, 22.0, 2.0))
	_health_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_health_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_health_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_fill.position = health_at.round()
	_health_fill.size = health_size
	_root.add_child(_health_fill)

	# Coin: the number of coins, sitting in its own slot.
	_coin_label = Label.new()
	_coin_label.name = "CoinLabel"
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_label.add_theme_font_override("font", UI_FONT)
	_coin_label.add_theme_font_size_override("font_size", GOLD_FONT)
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	_coin_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_coin_label.add_theme_constant_override("outline_size", 8)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin_label.position = (left + COIN_AREA.position * ART_SCALE
		+ Vector2(0.0, GOLD_LABEL_Y_OFFSET)).round()
	_coin_label.size = COIN_AREA.size * ART_SCALE
	_root.add_child(_coin_label)


## Builds the logical grid from the measured inner slot region for the active artwork.
func _build_slots(grid_at: Vector2) -> void:
	var capacity: int = Inventory.inventory_capacity
	var grid_region: Rect2 = _grid_region_for_capacity(capacity)
	var slot_region: Rect2 = _grid_slot_region_for_capacity(capacity)
	var columns: int = _grid_columns_for_capacity(capacity)
	var slot_at: Vector2 = grid_at + (slot_region.position - grid_region.position) * ART_SCALE
	var cell: Vector2 = slot_region.size * ART_SCALE / Vector2(float(columns), float(GRID_ROWS))
	for row in GRID_ROWS:
		for col in columns:
			var index: int = row * columns + col
			var at: Vector2 = slot_at + Vector2(float(col) * cell.x, float(row) * cell.y)

			var button := Button.new()
			button.name = "Slot%d" % index
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.flat = true
			button.focus_mode = Control.FOCUS_NONE
			button.position = at.round()
			button.size = cell
			button.pressed.connect(_on_slot_pressed.bind(index))
			button.gui_input.connect(_on_slot_gui_input.bind(index))
			_root.add_child(button)
			_slots.append(button)

			var icon := TextureRect.new()
			icon.name = "Icon%d" % index
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.position = (at + Vector2.ONE * 2.0).round()
			icon.size = cell - Vector2.ONE * 4.0
			_configure_item_icon(icon, str(Inventory.item_at(index).item_name)
				if Inventory.item_at(index) != null else "")
			_root.add_child(icon)
			_icons.append(icon)


## Standard 32x32 item art uses the shared slot fitting rule. These explicit scales are only
## for the older 64x64 Long Stick and Bark Shield canvases, whose visible art is unusually
## wide or tall after alpha cropping. Stone keeps its existing tiny-art enlargement.
func _item_icon_scale(item_name: String, inventory_slot: bool) -> float:
	match item_name:
		"Long Stick":
			return 0.80 if inventory_slot else 0.82
		"Bark Shield":
			return 0.76 if inventory_slot else 0.78
		"Stone":
			return 3.0
		"Amethyst Sword":
			return 0.65
		"Minor Healing Potion":
			return 0.45
	return 1.0


func _item_icon_offset(item_name: String, inventory_slot: bool) -> Vector2:
	if inventory_slot and item_name == "Long Stick":
		return Vector2(3.0, 0.0)
	return Vector2.ZERO


func _configure_item_icon(icon: TextureRect, item_name: String, inventory_slot: bool = true) -> void:
	if not icon.has_meta("base_position"):
		icon.set_meta("base_position", icon.position)
	var base_position: Vector2 = icon.get_meta("base_position")
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2.ONE * _item_icon_scale(item_name, inventory_slot)
	icon.position = base_position + _item_icon_offset(item_name, inventory_slot)


func _configure_source_button_icon(button: Button, source: String) -> void:
	var icon: TextureRect = button.get_node_or_null("Icon") as TextureRect
	if icon != null:
		_configure_item_icon(icon, source, false)


func _player_frames() -> SpriteFrames:
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	if packed == null:
		return null
	var source: Node = packed.instantiate()
	var sprite: AnimatedSprite2D = source.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = sprite.sprite_frames if sprite != null else null
	source.free()
	return frames


# --- Moving items ----------------------------------------------------------------

## A square is clicked: pick its item up, or put down the one already in hand.
func _on_slot_pressed(index: int) -> void:
	if _held == null:
		if Inventory.is_empty(index):
			return
		_held = Inventory.clear_slot(index)
		_held_from = index
	else:
		# Put it down: swap whatever was in the target square back to where this came
		# from. The held item is released FIRST, so the "put it back" path below can
		# never undo the move that just happened.
		var from_index: int = _held_from
		var held: InventoryItem = _held
		_held = null
		_held_from = -1
		var displaced: InventoryItem = Inventory.item_at(index)
		Inventory.slots[index] = held
		if from_index >= 0 and from_index < Inventory.slots.size():
			Inventory.slots[from_index] = displaced
		Inventory.changed.emit()


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		var item: InventoryItem = Inventory.item_at(index)
		if item != null and item.consumed_on_use and item.item_name == "Minor Healing Potion":
			Inventory.heal(6)
			Inventory.clear_slot(index)
			get_viewport().set_input_as_handled()


## Puts whatever is in hand back where it came from.
func _drop_held() -> void:
	if _held != null and _held_from >= 0 and _held_from < Inventory.slots.size():
		if Inventory.slots[_held_from] == null:
			Inventory.slots[_held_from] = _held
			Inventory.changed.emit()
	_held = null
	_held_from = -1
	if _held_icon != null:
		_held_icon.visible = false


func _process(_delta: float) -> void:
	if _god_held != null and _god_drag_icon != null:
		_god_drag_icon.position = (get_viewport().get_mouse_position() - _god_drag_icon.size * 0.5).round()
	if not visible or _held_icon == null:
		return
	_drive_held_icon()
	_drive_held_card()
	_update_hover()


## The inventory item in hand follows the cursor while one is picked up.
func _drive_held_icon() -> void:
	if _held == null:
		_held_icon.visible = false
		return
	_held_icon.texture = _held.icon
	_held_icon.size = _slots[0].size if not _slots.is_empty() else Vector2(64.0, 64.0)
	_held_icon.position = (get_viewport().get_mouse_position() - _held_icon.size * 0.5).round()
	_held_icon.visible = true


## The complete reusable card scene follows the cursor while one is dragged. The visual copy
## is non-interactive, so the real source card remains in its slot and the existing drop logic
## still decides whether the card joins or leaves the deck.
func _drive_held_card() -> void:
	if _card_icon == null:
		return
	var card: CardData = _held_card.get("card", null) as CardData
	if card == null or not _deck_mode or _deck_panel == null:
		_card_icon.visible = false
		return
	var drag_scale: float = DECK_CARD_SCALE if _held_from_deck >= 0 else STRIP_CARD_SCALE
	var visual_path: String = str(_card_icon.get_meta("path", ""))
	var visual_scale: float = float(_card_icon.get_meta("scale", -1.0))
	if visual_path != str(_held_card.get("path", "")) or absf(visual_scale - drag_scale) > 0.001:
		for child: Node in _card_icon.get_children():
			child.free()
		var preview_card: Card = CARD_SCENE.instantiate() as Card
		if preview_card == null:
			_card_icon.visible = false
			return
		preview_card.card_data = card
		preview_card.scale = Vector2.ONE * drag_scale
		preview_card.position = -CARD_FACE_AT * drag_scale
		var held_modulate: Color = Color(_held_card.get("modulate", Color.WHITE))
		preview_card.modulate = held_modulate
		_mouse_ignore(preview_card)
		_card_icon.add_child(preview_card)
		_card_icon.size = CARD_FACE_SIZE * drag_scale
		_card_icon.set_meta("path", str(_held_card.get("path", "")))
		_card_icon.set_meta("scale", drag_scale)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_card_icon.position = (mouse - _deck_panel.position - _card_icon.size * 0.5).round()
	_card_icon.visible = true


# --- Deck management -------------------------------------------------------------
#
# A MODE of the inventory rather than a second screen: pressing E slides the inventory
# slightly left and brings this panel in beside it. Combat-capable items are highlighted
# in the inventory and mirrored across the panel's top row; hovering one reveals every
# card it can contribute, and those cards are dragged into or out of the active deck.
#
# Nothing here equips anything. An item being present only makes its cards AVAILABLE —
# the player chooses which to take, and the inventory autoload drops any card whose item
# has left the bag.

const DECK_TEX: Texture2D = preload("res://assets/Inventory/deckmanager-inventory.png")
const DECK_REGION := Rect2(3.0, 8.0, 307.0, 274.0)
## Smaller than the rest of the inventory: at 4x this panel would be taller than the
## screen, and at 1.5x it sits neatly beside the shifted inventory.
## Smaller than the rest of the inventory at one column, but the deck panel has the screen
## to itself in deck mode, so it is drawn large enough for its cards to be read.
const DECK_SCALE: float = 2.4
const DECK_AT := Vector2(796.0, 154.0)
## How far the inventory slides left to make room for it.
const DECK_SHIFT: float = 150.0
## The panel's own areas, in the art's pixels: the item row, the strip of cards revealed
## under a hovered item, and the active deck beneath both.
## Measured from the panel art itself, in the art's own coordinates: the six combat-item
## slots across the top, the strip below them where a hovered item's cards appear, and the
## active deck at the bottom. These are the drawn boxes, not approximations of them.
const DECK_ITEM_ROW := Rect2(45.0, 42.0, 234.0, 66.0)
## Measured from the six repeated slot frames in deckmanager-inventory.png. These are
## independent from the normal inventory grid measurements.
const DECK_ITEM_GRID_ORIGIN := Vector2(46.0, 45.0)
const DECK_ITEM_GRID_PITCH := Vector2(40.4, 39.0)
const DECK_ITEM_SLOT_SIZE := Vector2(37.0, 37.0)
const DECK_ITEM_COLUMNS: int = 6
const DECK_CARD_STRIP := Rect2(36.0, 114.0, 254.0, 78.0)
## The deck box starts BELOW its "YOUR DECK" title, which sits in the top of the drawn
## box — otherwise the first row of cards lands across the words.
## Tall enough for a full-size card, since the deck is drawn as an overlapping row.
const DECK_ACTIVE := Rect2(36.0, 168.0, 254.0, 114.0)
## Two compact rows of ten cards fit inside the lower deck panel. The active area reaches
## the panel floor, while each card row stays entirely above that floor.
const DECK_COLUMNS: int = 10
## Card tiles are REAL cards, built from the project's own card scene, so they look exactly
## like the ones in hand — frame, artwork, name, description and cost — rather than just
## the artwork. The scene is 40x40 with a 76x99 face offset inside it, which is what the
## scales below are measured against.
const CARD_SCENE: PackedScene = preload("res://card.tscn")
## The face's offset and size inside the card scene, at scale 1.
const CARD_FACE_AT := Vector2(8.0, 11.0)
const CARD_FACE_SIZE := Vector2(76.0, 99.0)
## The strip has room to show an item's cards at full size; the deck box fits two rows of
## smaller ones.
const STRIP_CARD_SCALE: float = 1.4
const PREVIEW_CARD_MARGIN: float = 12.0
const PREVIEW_CARD_GAP: float = 8.0
## The deck is drawn like the hand: full cards, overlapping, standing on the floor of the
## box and rising above the frame rather than being squashed to fit inside it.
## A compact combat-hand scale that still leaves ten substantial cards across one row.
const DECK_CARD_SCALE: float = 1.6
const DECK_CARD_STEP: float = 54.0
const DECK_ROW_STEP: float = 122.0
const CARD_GAP: float = 3.0
## How a card moves when the pointer finds it: a lift of most of its own height, a little
## growth, and a short ease so it reads as movement rather than a jump.
const CARD_HOVER_TIME: float = 0.12
const CARD_LIFT: float = 120.0
const CARD_HOVER_GROW: float = 1.18
const DECK_CARD_LIFT: float = 48.0
## Cards in the item popup only need a small nudge; deck cards use the full lift to stand
## clear of their neighbours.
const STRIP_CARD_LIFT: float = 24.0
const HOVER_GRACE_TIME: float = 0.28
const SOURCE_ICON_MARGIN: float = 10.0
## The combat-item tiles across the top of the panel, sized to the art's own slot pitch —
## its six slots are 39 art pixels apart, which is 78 at 2x.
const SOURCE_W: float = 78.0
const SOURCE_H: float = 78.0
## How a card already in the deck — and a combat-capable item in the inventory — is lit.
const IN_DECK_TINT := Color(1.45, 1.35, 0.95, 1.0)

var _deck_mode: bool = false
var _panels: Array = []
var _deck_panel: Control = null
var _deck_items: Control = null
var _deck_strip: Control = null
var _deck_active: Control = null
var _prompt: Label = null
var _hovered_source: String = ""
var _held_card: Dictionary = {}
var _held_from_deck: int = -1
var _card_icon: Control = null
var _hover_grace_until: float = 0.0


## Shows or hides the deck manager, re-laying the whole interface around it.
func set_deck_mode(on: bool) -> void:
	_deck_mode = on
	if _deck_panel != null:
		_deck_panel.visible = on
	_layout(on)
	if not on:
		_hovered_source = ""
		_held_card = {}
		_held_from_deck = -1
	_rebuild_deck_panel()


## Lays the interface out. In one column the inventory sits centred on its own; in two, it
## is scaled AS A UNIT and placed on the left with the deck panel beside it. The panels
## keep their positions relative to each other, so nothing inside can drift out of line,
## and both halves stay inside the viewport with matching margins and one shared vertical
## centre.
func _layout(two_column: bool) -> void:
	var view := Vector2(1280.0, 720.0)
	var ui_scale: float = TWO_COLUMN_SCALE if two_column else 1.0
	var side: Vector2 = Vector2(880.0, 624.0) * ui_scale
	var deck_size: Vector2 = DECK_REGION.size * DECK_SCALE
	var at: Vector2 = COMPOSITION_HOME
	var deck_at: Vector2 = DECK_AT
	if two_column:
		var total: float = side.x + COLUMN_GAP + deck_size.x
		var left: float = maxf(LAYOUT_MARGIN, (view.x - total) * 0.5)
		var centre: float = (view.y - maxf(side.y, deck_size.y)) * 0.5
		at = Vector2(left, centre)
		# The deck panel has the screen to itself, simply centred on it.
		deck_at = Vector2((view.x - deck_size.x) * 0.5, (view.y - deck_size.y) * 0.5)
	for panel: Variant in _panels:
		var control := panel as Control
		if control == null:
			continue
		# Scaled about the COMPOSITION's origin rather than each panel's own centre, which
		# is what keeps them in the same arrangement at either size.
		# The inventory side steps aside entirely while the deck is being managed — the
		# portrait, the health bar and the coin go with it.
		control.visible = not two_column
		# The header's contents are their own nodes rather than children of the header, so
		# they have to step aside with it — the portrait and the health bar included.
		for child: Node in _root.get_children():
			var child_name := String(child.name)
			if child_name == "PlayerSprite" or child_name == "HealthFill":
				(child as CanvasItem).visible = not two_column
		control.scale = Vector2(ui_scale, ui_scale)
		control.position = (at + (_home_of(control) - COMPOSITION_HOME) * ui_scale).round()
	if _deck_panel != null:
		_deck_panel.position = deck_at.round()


## A panel's position in the one-column composition, taken from the same numbers that
## layout is built with, so scaling the interface moves every panel as one piece.
func _home_of(control: Control) -> Vector2:
	match String(control.name):
		"Header":
			return _header_home
		"Grid":
			return _grid_home
		"DeckPrompt":
			return PROMPT_HOME
	return COMPOSITION_HOME


# --- Cropping ---------------------------------------------------------------------
#
# Both the item sheets and the health fill are larger canvases than the art inside them,
# and in both the art is off-centre. Drawing the whole canvas is what left items crooked
# in their slots and the health bar permanently two thirds full, so both are cropped to
# the pixels that actually matter.

## Cropped item icons, cached by the texture they came from.
var _icon_cache: Dictionary = {}


## A texture cropped to a region — for stretching a known strip of artwork.
func _cropped(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas


## An item's icon, cropped to the artwork inside its sheet. The item PNGs are 64x64 with
## the art off-centre — the stick is a thin diagonal high and left, the stone a speck near
## the middle — so drawing the whole square sits every item crooked in its slot.
func _icon_for(item: InventoryItem) -> Texture2D:
	if item == null or item.icon == null:
		return null
	var key: int = int(item.icon.get_instance_id())
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img: Image = item.icon.get_image()
	var x0 := 9999
	var y0 := 9999
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	var full := Rect2(Vector2.ZERO, item.icon.get_size())
	var cropped: AtlasTexture = _cropped(item.icon, full)
	if x1 >= 0:
		var art := Rect2(float(x0), float(y0), float(x1 - x0 + 1), float(y1 - y0 + 1))
		# Large subjects benefit from cropping their transparent padding. Keep tiny/dark
		# subjects such as Stone in their authored square so the fitting rule does not
		# enlarge a handful of pixels into an oversized blob.
		if art.size.x * art.size.y >= full.size.x * full.size.y * 0.15:
			cropped = _cropped(item.icon, art)
	_icon_cache[key] = cropped
	return cropped


## The small prompt telling the player E is available while the inventory is open.
func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.name = "DeckPrompt"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_override("font", UI_FONT)
	_prompt.add_theme_font_size_override("font_size", PROMPT_FONT)
	_prompt.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.text = "[E]  Manage Deck"
	# Inside the interface's own footprint, along the bottom edge of the slot grid, rather
	# than floating over the crafting panel in the middle of it.
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.position = PROMPT_HOME
	_prompt.size = Vector2(312.0, 22.0)
	_root.add_child(_prompt)
	# Part of the inventory side, so it slides and scales along with the rest of it.
	_panels.append(_prompt)


func _build_deck_manager() -> void:
	_deck_panel = Control.new()
	_deck_panel.name = "DeckManager"
	# PASS rather than IGNORE, so the tiles and cards inside it can still be hovered.
	_deck_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_deck_panel.position = DECK_AT
	_deck_panel.size = DECK_REGION.size * DECK_SCALE
	_deck_panel.visible = false
	_root.add_child(_deck_panel)

	var atlas := AtlasTexture.new()
	atlas.atlas = DECK_TEX
	atlas.region = DECK_REGION
	var art := TextureRect.new()
	art.name = "DeckArt"
	art.texture = atlas
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = _deck_panel.size
	_deck_panel.add_child(art)

	_deck_items = _make_area("DeckItems", DECK_ITEM_ROW)
	_deck_strip = _make_area("DeckStrip", DECK_CARD_STRIP)
	_deck_active = _make_area("DeckActive", DECK_ACTIVE)
	# Keep the three interaction layers visually ordered even when the preview backing fills
	# its entire middle display area.
	_deck_strip.z_index = 1
	_deck_active.z_index = 2
	_deck_items.z_index = 3

	_card_icon = Control.new()
	_card_icon.name = "HeldCard"
	_card_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_icon.visible = false
	_deck_panel.add_child(_card_icon)

	# The panel follows the deck and the bag directly, so it can never drift from them.
	Inventory.changed.connect(_rebuild_deck_panel)
	Inventory.deck_changed.connect(_rebuild_deck_panel)
	_rebuild_deck_panel()


## One of the panel's three regions, positioned from the art's own pixels.
func _make_area(node_name: String, region: Rect2) -> Control:
	var area := Control.new()
	area.name = node_name
	# PASS, not IGNORE: a Control set to IGNORE takes its whole subtree out of mouse
	# picking, so the cards and item tiles inside these areas would never be hovered.
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	area.position = (region.position - DECK_REGION.position) * DECK_SCALE
	area.size = region.size * DECK_SCALE
	_deck_panel.add_child(area)
	return area


## The screen rect of the active deck: what a card is dropped onto, and out of.
func _deck_rect() -> Rect2:
	if _deck_active == null or _deck_panel == null:
		return Rect2()
	return Rect2(_deck_panel.position + _deck_active.position, _deck_active.size)


# --- Redrawing -------------------------------------------------------------------

## Rebuilds everything the panel shows from the live inventory state. Cheap enough to run
## on every change, which is what makes it impossible for the panel and the deck to
## disagree.
func _rebuild_deck_panel() -> void:
	if _deck_panel == null:
		return
	for area: Control in [_deck_items, _deck_strip, _deck_active]:
		if area == null:
			continue
		for child: Node in area.get_children():
			child.queue_free()

	var sources: Array = Inventory.card_sources()

	# Highlight the combat-capable items in the inventory itself.
	for i in _icons.size():
		var item: InventoryItem = Inventory.item_at(i)
		var lit: bool = _deck_mode and item != null and sources.has(item.item_name)
		# This tint highlights combat-capable inventory items, not deck cards.
		_icons[i].modulate = IN_DECK_TINT if lit else Color.WHITE

	# The sources occupy the actual 2x6 slot grid in the background. Their order remains
	# the inventory/source order; only the measured visual slot position changes.
	for source_index: int in sources.size():
		var source: String = sources[source_index]
		var row: int = int(floor(float(source_index) / float(DECK_ITEM_COLUMNS)))
		var column: int = source_index % DECK_ITEM_COLUMNS
		var art_position: Vector2 = DECK_ITEM_GRID_ORIGIN + Vector2(
			float(column) * DECK_ITEM_GRID_PITCH.x,
			float(row) * DECK_ITEM_GRID_PITCH.y)
		var button := _make_source_button(source)
		button.position = ((art_position - DECK_REGION.position) * DECK_SCALE
			- _deck_items.position).round()
		button.size = (DECK_ITEM_SLOT_SIZE * DECK_SCALE).round()
		_deck_items.add_child(button)
		_configure_source_button_icon(button, source)

	_rebuild_strip()

	# The active deck is a fixed two-row grid: ten columns on the first row and ten on the
	# second. Cards are compact enough that both rows remain inside the drawn lower panel.
	var deck_card: Vector2 = CARD_FACE_SIZE * DECK_CARD_SCALE
	var count: int = mini((Inventory.active_deck as Array).size(), DECK_COLUMNS * 2)
	var row_width: float = float(DECK_COLUMNS - 1) * DECK_CARD_STEP + deck_card.x
	var start: float = maxf(0.0, (_deck_active.size.x - row_width) * 0.5)
	for i in count:
		var entry: Dictionary = Inventory.active_deck[i]
		var card: CardData = Inventory.card_data_for_path(str(entry["path"]))
		if card == null:
			continue
		var button := _make_card_tile(card, str(entry["path"]), str(entry["item"]), true, i,
			DECK_CARD_SCALE, false)
		var row: int = int(floor(float(i) / float(DECK_COLUMNS)))
		var column: int = i % DECK_COLUMNS
		button.position = Vector2(roundf(start + float(column) * DECK_CARD_STEP),
			roundf(float(row) * DECK_ROW_STEP))
		_deck_active.add_child(button)


## Rebuilds the box of cards an item offers, hanging directly beneath that item. The box
## counts as part of the item for hover purposes, so moving the mouse from the item down to
## its cards never clears them.
func _rebuild_strip() -> void:
	if _deck_strip == null:
		return
	for child: Node in _deck_strip.get_children():
		child.queue_free()
	_deck_strip.visible = not _hovered_source.is_empty()
	if _hovered_source.is_empty():
		return
	# One node per card, lit PER COPY: the first copy of a path lights when one is in the
	# deck, the second when two are, and so on.
	var offered: Array[String] = Inventory.cards_offered_by(_hovered_source)
	var preview_scale: float = _preview_card_scale(offered.size())
	var card_width: float = CARD_FACE_SIZE.x * preview_scale
	var card_height: float = CARD_FACE_SIZE.y * preview_scale
	var total_width: float = float(offered.size()) * card_width
	if offered.size() > 1:
		total_width += float(offered.size() - 1) * PREVIEW_CARD_GAP
	# The tray grows with the cards, while the card scale remains identical for every source.
	_deck_strip.size = Vector2(
		total_width + PREVIEW_CARD_MARGIN * 2.0,
		card_height + PREVIEW_CARD_MARGIN * 2.0)
	var x: float = PREVIEW_CARD_MARGIN
	var y: float = PREVIEW_CARD_MARGIN
	var seen: Dictionary = {}
	for path: String in offered:
		var card: CardData = Inventory.card_data_for_path(path)
		if card == null:
			continue
		var copy_index: int = int(seen.get(path, 0))
		seen[path] = copy_index + 1
		var taken: bool = Inventory.deck_count(_hovered_source, path) > copy_index
		var button := _make_card_tile(card, path, _hovered_source, taken, -1,
			preview_scale, true)
		button.position = Vector2(x, y).round()
		_deck_strip.add_child(button)
		x += button.size.x + PREVIEW_CARD_GAP
	var back := ColorRect.new()
	back.name = "BoxBack"
	back.color = Color(0.08, 0.06, 0.05, 0.97)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = Vector2.ZERO
	back.size = _deck_strip.size
	_deck_strip.add_child(back)
	_deck_strip.move_child(back, 0)
	# Keep every tray centred in the Deck Management panel, regardless of its source item.
	var at_x: float = roundf((_deck_panel.size.x - _deck_strip.size.x) * 0.5)
	at_x = clampf(at_x, 6.0, maxf(6.0, _deck_panel.size.x - _deck_strip.size.x - 6.0))
	# Start just below the bottom edge of the combat-item slots, leaving no overlap with
	# the slot artwork while still keeping the preview close to its source.
	var item_at: Vector2 = _source_position(_hovered_source)
	var source_slot_size: Vector2 = DECK_ITEM_SLOT_SIZE * DECK_SCALE
	_deck_strip.position = Vector2(at_x, roundf(item_at.y + source_slot_size.y + 16.0))


## Preview cards keep one shared scale. The tray width, not the card size, flexes with the
## number of cards offered by the hovered item.
func _preview_card_scale(_card_count: int) -> float:
	return STRIP_CARD_SCALE


## Eases a card between its resting and hovered poses, so the lift reads as movement rather
## than a jump.
func _tween_card(node: Card, to_scale: Vector2, to_position: Vector2,
		to_colour: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", to_scale, CARD_HOVER_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", to_position, CARD_HOVER_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate", to_colour, CARD_HOVER_TIME)


## Where a source's tile sits, in the panel's own coordinates.
func _source_position(source: String) -> Vector2:
	for child: Node in _deck_items.get_children():
		if str(child.get_meta("source", "")) == source:
			return _deck_items.position + (child as Control).position
	return _deck_items.position


## Which item the pointer is over, treating its item slot, preview area, and the travel gap as
## one interaction. The grace window prevents a fast or slow mouse path from clearing the
## preview between the source slot and its cards.
func _update_hover() -> void:
	if not _deck_mode or _deck_panel == null or not _deck_panel.visible:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var found: String = ""
	for child: Node in _deck_items.get_children():
		var button := child as Control
		if button == null or button.is_queued_for_deletion():
			continue
		if Rect2(_deck_panel.position + _deck_items.position + button.position,
				button.size).has_point(mouse):
			found = str(button.get_meta("source", ""))
			break
	if found.is_empty() and _deck_strip.visible:
		# Include padding around the whole middle display, including the path from the item.
		var preview_rect := Rect2(_deck_panel.position + _deck_strip.position,
			_deck_strip.size + Vector2(20.0, 32.0))
		preview_rect.position.y -= 16.0
		if preview_rect.has_point(mouse):
			found = _hovered_source
	if not found.is_empty():
		_hover_grace_until = Time.get_ticks_msec() / 1000.0 + HOVER_GRACE_TIME
	elif not _held_card.is_empty():
		# Dragging owns the preview. Never clear or rebuild its source out from under the grab.
		return
	elif not _hovered_source.is_empty() \
			and Time.get_ticks_msec() / 1000.0 < _hover_grace_until:
		return
	if found != _hovered_source:
		_hovered_source = found
		_rebuild_strip()


## One source in the top row. Hovering it is what reveals its cards.
func _make_source_button(source: String) -> Button:
	var button := Button.new()
	button.name = "Source_" + source
	# The source is carried as METADATA rather than read back off the node's name. Godot
	# renames a node when a same-named one has not been freed yet, so mid-rebuild
	# "Source_Long Stick" can become "Source_Long Stick2" — and the name then resolves to
	# no cards at all, which is what left the hover box empty.
	button.set_meta("source", source)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _source_icon(source)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Every source uses the same inset rule: proportional KEEP_ASPECT_CENTERED artwork,
	# with a consistent margin relative to the measured slot Control, regardless of the
	# row or the source texture's original dimensions.
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = SOURCE_ICON_MARGIN
	icon.offset_top = SOURCE_ICON_MARGIN
	icon.offset_right = -SOURCE_ICON_MARGIN
	icon.offset_bottom = -SOURCE_ICON_MARGIN
	button.add_child(icon)
	# Hover is POLLED in _process rather than driven by enter/exit. The cards appear in a
	# box hanging below the item, and a mouse travelling from one to the other crosses a
	# gap — enter/exit would clear the hover and take the cards away mid-reach.
	return button


## A source's icon: the item's own artwork, or for an innate source the artwork of the
## card it offers.
func _source_icon(source: String) -> Texture2D:
	for item: InventoryItem in Inventory.slots:
		if item != null and item.item_name == source:
			return _icon_for(item)
	var paths: Array = Inventory.cards_offered_by(source)
	if not paths.is_empty():
		var card: CardData = Inventory.card_data_for_path(str(paths[0]))
		if card != null:
			return card.artwork
	return null


## One card in the strip or the deck: a real card from the project's own scene, so it
## carries its frame, artwork, name, description and energy cost exactly as it does in
## hand. Pressing it picks it up and releasing decides where it goes, which is the whole
## of the drag.
func _make_card_tile(card: CardData, path: String, source: String, taken: bool,
		from_deck: int, tile_scale: float, preview: bool) -> Button:
	var button := Button.new()
	button.name = "Card_" + card.card_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.size = CARD_FACE_SIZE * tile_scale

	var node: Card = CARD_SCENE.instantiate() as Card
	if node != null:
		# Set before it enters the tree: the card applies its data in _ready, which is
		# exactly the flow the scene was written for.
		node.card_data = card
		node.scale = Vector2(tile_scale, tile_scale)
		# Centre the card's FACE in the tile, since the scene's own origin sits up and to
		# the left of it.
		node.position = ((button.size - CARD_FACE_SIZE * tile_scale) * 0.5
			- CARD_FACE_AT * tile_scale).round()
		# Only available preview copies use the tinted treatment. YOUR DECK stays at the
		# card's original colour and opacity.
		node.modulate = IN_DECK_TINT if preview and taken else Color.WHITE
		_mouse_ignore(node)
		button.add_child(node)

	# Hovering lifts and brightens a card, the same read as the hand in combat. The scale
	# grows about the card's own origin, so its position is nudged back by half the growth
	# to keep the face centred on the tile.
	if node != null:
		var base := Vector2(tile_scale, tile_scale)
		var home: Vector2 = node.position
		var lit: Color = IN_DECK_TINT if preview and taken else Color.WHITE
		# z_index, NOT reordering the nodes. Raising a card by moving it in the child list
		# left the deck muddled whenever a restore failed, and a hover has no business
		# changing the order at all — only what is drawn on top while it lasts.
		var lift: float = DECK_CARD_LIFT if from_deck >= 0 else STRIP_CARD_LIFT
		var lifted: Vector2 = (home - CARD_FACE_SIZE * base * 0.09
			- Vector2(0.0, lift)).round()
		button.mouse_entered.connect(func() -> void:
			button.z_index = 1
			_tween_card(node, base * CARD_HOVER_GROW, lifted,
				lit * Color(1.35, 1.35, 1.35, 1.0)))
		button.mouse_exited.connect(func() -> void:
			button.z_index = 0
			_tween_card(node, base, home, lit))
	var card_modulate: Color = node.modulate if node != null else Color.WHITE
	button.button_down.connect(func() -> void:
		_held_card = {"item": source, "path": path, "card": card, "modulate": card_modulate}
		_held_from_deck = from_deck)
	button.button_up.connect(_on_card_released)
	return button


## Makes a node and everything under it mouse-transparent, so the tile's own button
## receives the press rather than one of the card's labels.
func _mouse_ignore(node: Node) -> void:
	var control := node as Control
	if control != null:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_mouse_ignore(child)


## A card was let go: dropped on the active deck it joins it, dropped anywhere else it
## leaves it. That one rule covers adding and removing without a second gesture.
func _on_card_released() -> void:
	if _held_card.is_empty():
		return
	var on_deck: bool = _deck_rect().has_point(get_viewport().get_mouse_position())
	var item_name: String = str(_held_card["item"])
	var path: String = str(_held_card["path"])
	if _held_from_deck >= 0:
		if not on_deck:
			Inventory.remove_card(item_name, path)
	elif on_deck:
		Inventory.add_card(item_name, path)
	_held_card = {}
	_held_from_deck = -1
	if _card_icon != null:
		_card_icon.visible = false
		_card_icon.set_meta("path", "")
	_rebuild_deck_panel()


# --- Keeping the display in step -------------------------------------------------

func _refresh() -> void:
	if _root != null and _grid_capacity != Inventory.inventory_capacity:
		_rebuild_inventory_grid()
	for i in _icons.size():
		var item: InventoryItem = Inventory.item_at(i)
		_icons[i].texture = _icon_for(item)
		_configure_item_icon(_icons[i], item.item_name if item != null else "")
	if _coin_label != null:
		# Just the number: the field it sits in already says what it is.
		_coin_label.text = str(Inventory.coin)
	if _health_fill != null:
		var full: float = HEALTH_FILL_WIDTH * ART_SCALE
		var ratio: float = clampf(float(Inventory.player_hp) / float(Inventory.PLAYER_MAX_HP), 0.0, 1.0)
		_health_fill.size = Vector2(roundf(full * ratio), _health_fill.size.y)
