class_name CardRewardOverlay
extends CanvasLayer
## Three-card standalone reward selection overlay.

signal closed
const CARD_SCENE: PackedScene = preload("res://card.tscn")
const UI_FONT: Font = preload("res://assets/Fonts/cardfont.ttf")
var _cards: Array[CardData] = []
var _root: Control = null

func setup(cards: Array[CardData]) -> void:
	_cards = cards
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var title: Label = Label.new()
	title.text = "CHOOSE A CARD REWARD"
	title.position = Vector2(390.0, 48.0)
	title.size = Vector2(500.0, 50.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 28)
	_root.add_child(title)
	for index: int in range(_cards.size()):
		_add_reward_card(_cards[index], index)
	var skip: Button = Button.new()
	skip.text = "Skip"
	skip.position = Vector2(570.0, 650.0)
	skip.size = Vector2(140.0, 42.0)
	skip.add_theme_font_override("font", UI_FONT)
	skip.pressed.connect(_close)
	_root.add_child(skip)

func _add_reward_card(data: CardData, index: int) -> void:
	var card: Card = CARD_SCENE.instantiate() as Card
	card.card_data = data
	card.scale = Vector2(1.35, 1.35)
	card.position = Vector2(210.0 + float(index) * 300.0, 160.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(card)
	var choose: Button = Button.new()
	choose.text = "Choose"
	choose.position = Vector2(205.0 + float(index) * 300.0, 560.0)
	choose.size = Vector2(150.0, 42.0)
	choose.add_theme_font_override("font", UI_FONT)
	choose.pressed.connect(_choose.bind(index))
	_root.add_child(choose)

func _choose(index: int) -> void:
	if index >= 0 and index < _cards.size():
		var card_id: String = StandaloneCardFactory.card_id(_card_key(_cards[index].card_name))
		Inventory.add_standalone_card(card_id)
	_close()

func _card_key(card_name: String) -> String:
	return card_name.to_snake_case()

func _close() -> void:
	closed.emit()
	queue_free()
