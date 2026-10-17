extends Control
## Letter overlay that appears on first play.
## Shows the inheritance letter from the player's great grandfather.

signal letter_accepted()

@onready var letter_text: RichTextLabel = %LetterText
@onready var accept_button: Button = %AcceptButton
@onready var parchment: TextureRect = %Parchment


func _ready() -> void:
	if parchment:
		var tex: Texture2D = load("res://assets/generated/letter_parchment_frame_0.png")
		if tex:
			parchment.texture = tex

	if accept_button:
		accept_button.pressed.connect(_on_accept_pressed)
		accept_button.visible = false  # Hidden until text finishes


func show_letter() -> void:
	visible = true

	# Animate letter appearing
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.8, 0.8)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color.WHITE, 0.6)
	tween.tween_property(self, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tween.finished

	# Type out the letter text
	if letter_text:
		await _type_text(letter_text, _get_letter_content())
		accept_button.visible = true


func _get_letter_content() -> String:
	return """[center][font_size=22]To My Dear Grandchild,[/font_size][/center]

[font_size=16]If you're reading this, I've gone on my final adventure. Don't mourn — I've had a wonderful life, and I leave you something precious.

In the far-out town of [b]Navaria[/b], nestled between the Whispering Woods and the Silver Mountains, sits my old shop — [b]The Adventurer's Emporium[/b]. It's yours now.

I've enclosed the keys with this letter. The shop has been locked up since I left, but I've no doubt you'll breathe new life into it. The villagers are good folk — warm, hardworking, the kind of people worth knowing.

Navaria may seem quiet at first glance, but there's more to this place than meets the eye. Trust your instincts. Be kind to the locals. And whatever you do — [i]keep exploring[/i].

With all my love,
Your Great Grandfather,
[b]Eldric Thornwood[/b][/font_size]

[i][font_size=12]P.S. — There's a special blend of tea in the back room. Save it for when you need to see things... differently.[/font_size][/i]"""


func _type_text(label: RichTextLabel, full_text: String) -> void:
	label.text = ""
	var visible_chars: int = 0
	var total_chars: int = full_text.length()

	while visible_chars < total_chars:
		visible_chars += 2
		label.text = full_text.substr(0, visible_chars)
		await get_tree().create_timer(0.01).timeout

	label.text = full_text


func _on_accept_pressed() -> void:
	# Mark as read and add keys
	GameState.letter_read = true
	GameState.has_shop_keys = true

	# Animate out
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.4)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.4)
	await tween.finished

	letter_accepted.emit()
	queue_free()
