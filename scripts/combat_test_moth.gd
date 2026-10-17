extends Control
## Moth Flight combat test scene.
##
## A standalone combat test in the same spirit as card_hand_test.tscn: it hosts the
## normal combat scene and configures that instance with the moth's fight — Flight,
## its multi-hit moveset and its artwork — through the same public encounter interface
## the overworld uses.
##
## The configuration is NOT duplicated here: it comes from WorldMoth.combat_setup(),
## which is exactly what the overworld moth hands the EncounterManager. The regular
## fight is untouched — opening combat_test.tscn directly still boots an ordinary
## ground-spider battle with no Flight at all.

const COMBAT_SCENE: PackedScene = preload("res://combat_test.tscn")

@onready var combat: Node = $CombatTest


func _ready() -> void:
	# The instanced combat scene has already run its own _ready by the time this runs,
	# which is exactly the order the overworld encounter flow relies on.
	combat.begin_encounter(WorldMoth.combat_setup())