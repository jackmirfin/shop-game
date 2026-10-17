extends Control
## Bear combat test scene.
##
## A standalone combat test in the same spirit as combat_test_moth.tscn: it hosts the
## normal combat scene and configures that instance with the bear's fight — its own
## moveset and its own health — through the same public encounter interface the
## overworld uses.
##
## The configuration is NOT duplicated here: it comes from WorldBear.combat_setup(),
## which is exactly what the placed overworld bear hands the EncounterManager. The
## regular fight is untouched — opening combat_test.tscn directly still boots an
## ordinary ground-spider battle with none of this.

const COMBAT_SCENE: PackedScene = preload("res://combat_test.tscn")

@onready var combat: Node = $CombatTest


func _ready() -> void:
	# The instanced combat scene has already run its own _ready by the time this runs,
	# which is exactly the order the overworld encounter flow relies on.
	combat.begin_encounter(WorldBear.combat_setup())
