extends Node
## Small persistent-in-session progression store used by scene-level tutorials.
var opening_message_seen: bool = false
var opening_message_seen_v2: bool = false
var first_spider_tutorial_seen: bool = false
var has_been_to_namura: bool = false
var blacksmith_intro_done: bool = false
var shop_letter_read: bool = false
var chest_contents: Dictionary = {}

func get_chest_contents(chest_id: String) -> Variant:
    return chest_contents.get(chest_id, null)

func set_chest_contents(chest_id: String, contents: Array) -> void:
    chest_contents[chest_id] = contents

func reset_run() -> void:
    opening_message_seen = false
    opening_message_seen_v2 = false
    first_spider_tutorial_seen = false
    has_been_to_namura = false
    blacksmith_intro_done = false
    shop_letter_read = false
