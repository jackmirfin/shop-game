class_name Card
extends Control
## Displays a CardData resource on the card's child nodes.
## Populates Artwork, Name, Description and EnergyCost when the card enters
## the scene. The Frame child is never touched.

@export var card_data: CardData:
	set(value):
		card_data = value
		_apply_card_data()

@onready var artwork: TextureRect = $Artwork
@onready var sword_overlay: TextureRect = $Artwork/SwordOverlay
@onready var name_label: Label = $Name
@onready var description_label: Label = $Description
@onready var energy_cost_label: Label = $EnergyCost

const TITLE_FONT_SIZE: int = 7
const DESCRIPTION_FONT_SIZE: int = 7
const TITLE_MIN_FONT_SIZE: int = 5
const DESCRIPTION_MIN_FONT_SIZE: int = 7

## The Artwork node's authored position, captured once so repeated updates can
## never accumulate the horizontal offset.
var _artwork_origin: Vector2 = Vector2.ZERO
var _artwork_origin_captured: bool = false
var _keyword_tooltip: PanelContainer = null
var _keyword_tooltip_label: Label = null


func _ready() -> void:
	var card_font: FontFile = name_label.get_theme_font("font") as FontFile
	if card_font != null:
		card_font.multichannel_signed_distance_field = true
	card_font.msdf_pixel_range = 16
	card_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	card_font.oversampling = 0.0
	card_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	for label: Label in [name_label, description_label, energy_cost_label]:
		label.position = label.position.round()
		label.size = label.size.round()
	_create_keyword_tooltip()
	mouse_entered.connect(_on_card_mouse_entered)
	mouse_exited.connect(_on_card_mouse_exited)
	_apply_card_data()


func _create_keyword_tooltip() -> void:
	_keyword_tooltip = PanelContainer.new()
	_keyword_tooltip.name = "KeywordTooltip"
	_keyword_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyword_tooltip.visible = false
	_keyword_tooltip.z_index = 100
	_keyword_tooltip.scale = Vector2.ONE / maxf(scale.x, 0.001)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.04, 0.98)
	style.border_color = Color(0.75, 0.62, 0.32, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_keyword_tooltip.add_theme_stylebox_override("panel", style)
	_keyword_tooltip_label = Label.new()
	_keyword_tooltip_label.name = "Text"
	_keyword_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyword_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keyword_tooltip_label.add_theme_font_override("font", name_label.get_theme_font("font"))
	_keyword_tooltip_label.add_theme_font_size_override("font_size", 8)
	_keyword_tooltip_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	_keyword_tooltip_label.custom_minimum_size = Vector2(210.0, 0.0)
	_keyword_tooltip.add_child(_keyword_tooltip_label)
	add_child(_keyword_tooltip)


func _on_card_mouse_entered() -> void:
	if card_data == null or (card_data.keyword_ids.is_empty() and card_data.keyword_tooltip.is_empty()):
		return
	if _keyword_tooltip_label == null or _keyword_tooltip == null:
		return
	var lines: Array[String] = []
	for keyword_id: String in card_data.keyword_ids:
		lines.append(KeywordRegistry.description(keyword_id))
	if not card_data.keyword_tooltip.is_empty():
		lines.append("\nCard effect:\n" + card_data.keyword_tooltip)
	_keyword_tooltip_label.text = "\n".join(lines)
	_keyword_tooltip.size = Vector2(226.0, _keyword_tooltip_label.get_combined_minimum_size().y + 12.0)
	var tooltip_height: float = _keyword_tooltip.size.y
	var view: Vector2 = get_viewport_rect().size
	var right_x: float = global_position.x + size.x + 8.0
	var tooltip_x: float = size.x + 8.0 if right_x + 226.0 <= view.x else -234.0
	var tooltip_y: float = -4.0
	if global_position.y + tooltip_y + tooltip_height > view.y:
		tooltip_y = -tooltip_height + size.y
	_keyword_tooltip.position = Vector2(tooltip_x, tooltip_y)
	_keyword_tooltip.visible = true


func _on_card_mouse_exited() -> void:
	if _keyword_tooltip != null:
		_keyword_tooltip.visible = false


func _apply_card_data() -> void:
	# Guard: the exported value is assigned during scene instantiation, before
	# the node is in the tree and before the @onready references exist.
	if not is_inside_tree():
		return
	# Capture the authored position once, BEFORE any offset is applied.
	if artwork and not _artwork_origin_captured:
		_artwork_origin = artwork.position
		_artwork_origin_captured = true
	if card_data == null:
		return
	if artwork:
		artwork.texture = card_data.artwork
		# Absolute position from the stored origin, so switching cards always
		# restores the correct offset instead of accumulating.
		artwork.position = Vector2(
			_artwork_origin.x + float(card_data.artwork_offset_x),
			_artwork_origin.y)
		_apply_sword_overlay()
	if name_label:
		name_label.text = card_data.card_name
		_fit_label(name_label, card_data.card_name.to_upper(), TITLE_FONT_SIZE, TITLE_MIN_FONT_SIZE)
	if description_label:
		description_label.text = card_data.description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fit_label(description_label, card_data.description, DESCRIPTION_FONT_SIZE,
			DESCRIPTION_MIN_FONT_SIZE)
	if energy_cost_label:
		energy_cost_label.text = str(card_data.energy_cost)


## Cards with artwork overlays use the supplied backdrop as Artwork and layer the
## item sprite above it. Existing cards keep their authored single-texture path.
func _apply_sword_overlay() -> void:
	if sword_overlay == null or artwork == null or card_data == null:
		return
	var overlay_texture: Texture2D = card_data.artwork_overlay
	if overlay_texture == null:
		sword_overlay.visible = false
		sword_overlay.texture = null
		return
	sword_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sword_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sword_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sword_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sword_overlay.texture = overlay_texture
	var overlay_scale: float = card_data.artwork_overlay_scale
	if card_data.card_name == "Minor Healing Potion":
		overlay_scale = 0.35
	sword_overlay.size = (overlay_texture.get_size() * overlay_scale).round()
	sword_overlay.position = ((artwork.size - sword_overlay.size) * 0.5).round()
	sword_overlay.visible = true


## Uses the largest integer font size that fits this card's authored text region. The
## generated card descriptions use explicit lines and word wrapping, so this check is
## deterministic and does not change existing card layout.
func _fit_label(label: Label, text: String, standard_size: int, minimum_size: int) -> void:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return
	var chosen: int = minimum_size
	for font_size: int in range(standard_size, minimum_size - 1, -1):
		if _text_fits(font, text, label.size, font_size):
			chosen = font_size
			break
	label.add_theme_font_size_override("font_size", chosen)
	label.set_meta("fitted_font_size", chosen)


func _text_fits(font: Font, text: String, bounds: Vector2, font_size: int) -> bool:
	var line_count: int = 0
	for paragraph: String in text.split("\n"): 
		var words: PackedStringArray = paragraph.split(" ", false)
		if words.is_empty():
			line_count += 1
			continue
		var current: String = ""
		for word: String in words:
			var candidate: String = word if current.is_empty() else current + " " + word
			var width: float = font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				font_size).x
			if not current.is_empty() and width > bounds.x:
				line_count += 1
				current = word
			else:
				current = candidate
		if not current.is_empty():
			line_count += 1
	var line_height: float = font.get_height(font_size)
	return line_count * line_height <= bounds.y + 0.01
