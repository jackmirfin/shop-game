class_name ShopLetter
extends Interactable

const LETTER_TEXT: String = "If you're reading this, I suppose the shop is yours now.\n\nThere's storage downstairs for anything you don't want to carry. Anything worth selling can be placed on the shop shelves.\n\nThe woods around Namura have always provided more than enough stock, if you're willing to go looking.\n\nDon't work yourself into the ground. The bed downstairs is yours.\n\nWhat you do with the place is up to you."

func _ready() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and bool(state.get("shop_letter_read")):
		queue_free()
		return
	interaction_type = InteractionType.TEXT
	super._ready()

func interact() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state != null:
		state.set("shop_letter_read", true)
	var manager: Node = get_node_or_null("/root/DialogueManager")
	if manager != null and manager.has_method("show_system_message"):
		manager.show_system_message(LETTER_TEXT, 30.0, Callable(), 2.0, 20,
			"res://assets/Fonts/Handpixies-Gzdm.ttf",
			"res://assets/Dialogue/UI/letter-backdrop.png", Color.BLACK)
	else:
		super.interact()
	call_deferred("queue_free")
