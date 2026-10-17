extends Control
## Main menu with parallax-scrolling cozy background.
## Layers: sky (static), mid (village→dungeon→forest, slow scroll), fg (hills, faster scroll).

var play_button: Button
var fade_rect: ColorRect

# Parallax layers
var _bg_sky: TextureRect
var _bg_mid: TextureRect
var _bg_mid2: TextureRect
var _bg_fg: TextureRect
var _bg_fg2: TextureRect

const SKY_SCROLL: float = 0.0
const MID_SCROLL: float = 15.0
const FG_SCROLL: float = 35.0


func _ready() -> void:
	# Hide any in-game HUD elements
	_hide_game_hud()
	_build_ui()
	_fade_in()


func _hide_game_hud() -> void:
	var hud: CanvasLayer = get_tree().root.get_node_or_null("GoldHUDCanvas") as CanvasLayer
	if hud:
		hud.visible = false


func _build_ui() -> void:
	# --- Sky background (static) ---
	_bg_sky = _make_layer("res://assets/generated/menu_bg_sky.png", true)
	add_child(_bg_sky)

	# --- Mid layer (village → dungeon → forest, slow scroll) ---
	_bg_mid = _make_layer("res://assets/generated/menu_bg_mid.png", false)
	_bg_mid2 = _make_layer("res://assets/generated/menu_bg_mid.png", false)
	add_child(_bg_mid)
	add_child(_bg_mid2)

	# --- Foreground layer (hills, faster scroll) ---
	_bg_fg = _make_layer("res://assets/generated/menu_bg_fg.png", false)
	_bg_fg2 = _make_layer("res://assets/generated/menu_bg_fg.png", false)
	add_child(_bg_fg)
	add_child(_bg_fg2)

	# --- Dark overlay for readability ---
	var overlay := ColorRect.new()
	overlay.name = "DarkOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.01, 0.0, 0.02, 0.55)
	add_child(overlay)

	# --- Fade rect ---
	fade_rect = ColorRect.new()
	fade_rect.name = "FadeRect"
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color.BLACK
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

	# --- Center VBox ---
	var vbox := VBoxContainer.new()
	vbox.name = "MenuVBox"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(400, 200)
	vbox.position = -vbox.size / 2
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	add_child(vbox)

	# --- Title ---
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "The Shopkeeper\nof Navaria"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55, 1))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)

	# --- Subtitle ---
	var subtitle := Label.new()
	subtitle.name = "SubtitleLabel"
	subtitle.text = "A Tale of Trade & Treasure"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5, 1))
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	subtitle.add_theme_constant_override("shadow_offset_x", 1)
	subtitle.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(subtitle)

	# --- Spacer ---
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# --- Play Button ---
	play_button = Button.new()
	play_button.name = "PlayButton"
	play_button.text = "Begin"
	play_button.custom_minimum_size = Vector2(150, 44)
	play_button.add_theme_font_size_override("font_size", 20)
	play_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 1))

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.45, 0.28, 0.1, 0.9)
	btn_normal.corner_radius_top_left = 10
	btn_normal.corner_radius_top_right = 10
	btn_normal.corner_radius_bottom_left = 10
	btn_normal.corner_radius_bottom_right = 10
	btn_normal.border_width_left = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_bottom = 2
	btn_normal.border_color = Color(0.8, 0.55, 0.2, 1)
	btn_normal.content_margin_left = 28
	btn_normal.content_margin_top = 10
	btn_normal.content_margin_right = 28
	btn_normal.content_margin_bottom = 10
	play_button.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.6, 0.38, 0.14, 1)
	btn_hover.corner_radius_top_left = 10
	btn_hover.corner_radius_top_right = 10
	btn_hover.corner_radius_bottom_left = 10
	btn_hover.corner_radius_bottom_right = 10
	btn_hover.border_width_left = 2
	btn_hover.border_width_top = 2
	btn_hover.border_width_right = 2
	btn_hover.border_width_bottom = 2
	btn_hover.border_color = Color(1.0, 0.7, 0.3, 1)
	btn_hover.content_margin_left = 28
	btn_hover.content_margin_top = 10
	btn_hover.content_margin_right = 28
	btn_hover.content_margin_bottom = 10
	play_button.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.3, 0.18, 0.05, 1)
	btn_pressed.corner_radius_top_left = 10
	btn_pressed.corner_radius_top_right = 10
	btn_pressed.corner_radius_bottom_left = 10
	btn_pressed.corner_radius_bottom_right = 10
	btn_pressed.border_width_left = 2
	btn_pressed.border_width_top = 2
	btn_pressed.border_width_right = 2
	btn_pressed.border_width_bottom = 2
	btn_pressed.border_color = Color(0.6, 0.35, 0.12, 1)
	btn_pressed.content_margin_left = 28
	btn_pressed.content_margin_top = 10
	btn_pressed.content_margin_right = 28
	btn_pressed.content_margin_bottom = 10
	play_button.add_theme_stylebox_override("pressed", btn_pressed)

	play_button.pressed.connect(_on_play_pressed)
	vbox.add_child(play_button)


func _make_layer(path: String, stretch: bool) -> TextureRect:
	var rect := TextureRect.new()
	var tex: Texture2D = load(path)
	if tex:
		rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if stretch:
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		# Scrolling layer: full width, anchored to bottom
		rect.anchor_left = 0.0
		rect.anchor_right = 1.0
		rect.anchor_top = 1.0
		rect.anchor_bottom = 1.0
		rect.offset_top = -216.0
		rect.offset_bottom = 0.0
		rect.offset_left = 0.0
		rect.offset_right = 0.0
		rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect


func _process(delta: float) -> void:
	_scroll_layer(_bg_mid, _bg_mid2, MID_SCROLL, delta)
	_scroll_layer(_bg_fg, _bg_fg2, FG_SCROLL, delta)


func _scroll_layer(a: TextureRect, b: TextureRect, speed: float, delta: float) -> void:
	if not a or not b:
		return
	var tex_width: float = float(a.texture.get_width()) if a.texture else 384.0

	a.offset_left -= speed * delta
	b.offset_left = a.offset_left + tex_width - 1.0  # -1px overlap to avoid seam

	# Wrap around
	if a.offset_left <= -tex_width:
		a.offset_left += tex_width * 2.0
	if b.offset_left <= -tex_width:
		b.offset_left += tex_width * 2.0


func _fade_in() -> void:
	if fade_rect:
		fade_rect.color = Color.BLACK
		var tween: Tween = create_tween()
		tween.tween_property(fade_rect, "color", Color(0, 0, 0, 0), 0.6)
	play_button.grab_focus()


func _on_play_pressed() -> void:
	play_button.disabled = true
	_start_game()


func _start_game() -> void:
	if fade_rect:
		var tween: Tween = create_tween()
		tween.tween_property(fade_rect, "color", Color.BLACK, 0.5)
		await tween.finished

	get_tree().change_scene_to_file("res://scenes/game.tscn")
