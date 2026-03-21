extends Node3D
# WorldSpacePanel — thin root script attached to WorldSpacePanel in each bactor.
# Finds child panel scenes (HpDisplay, WillRing, AmmoStaff) and calls setup(actor).
# Does NOT billboard itself — each child panel handles its own billboarding.


func setup(actor) -> void:
	for child in get_children():
		if child.has_method("setup"):
			child.setup(actor)
