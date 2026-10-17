## Archived copy intentionally has no global class name.
extends Resource
## Data container for a single dialogue line or conversation node.

@export var speaker_name: String = ""          ## Who is speaking
@export var text: String = ""                  ## The dialogue line
@export var next_id: String = ""               ## ID of next line (for linear chains)
@export var choices: Array[String] = []        ## Choice texts for branching dialogue
@export var choice_targets: Array[String] = []  ## IDs to jump to for each choice
@export var condition_flag: String = ""        ## GameState flag required to show this line
@export var set_flag: String = ""              ## GameState flag to set when this line is shown
@export var quest_id: String = ""              ## Associated quest
@export var gives_item: String = ""            ## Unique ID of item to give player


func has_choices() -> bool:
	return choices.size() > 0


func get_next(choice_index: int = 0) -> String:
	if has_choices() and choice_index < choice_targets.size():
		return choice_targets[choice_index]
	return next_id
