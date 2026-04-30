extends Node3D
# WorldSpacePanel — thin root script attached to WorldSpacePanel in each bactor.
# Finds child panel scenes (HpDisplay, WillRing, AmmoStaff) and calls setup(actor).
# Also spawns TempoMetronome at runtime so it doesn't need to be in every bactor scene.
# Does NOT billboard itself — each child panel handles its own billboarding.

const TEMPO_METRONOME_SCENE := preload("res://UI/3D/BattleDisplay/Scenes/tempo_metronome.tscn")

func setup(actor) -> void:
	# Call setup on any pre-placed children (HpDisplay, WillRing, AmmoStaff, etc.)
	for child in get_children():
		if child.has_method("setup"):
			child.setup(actor)
	# Spawn the metronome dynamically — shared across all bactors without editing each scene.
	var metronome : Node3D = TEMPO_METRONOME_SCENE.instantiate()
	metronome.name = "TempoMetronome"
	add_child(metronome)
	if metronome.has_method("setup"):
		metronome.setup(actor)
