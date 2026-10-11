class_name SelectionRing
extends Node3D
## A glowing ring on the ground under a combatant. Parent it to the combatant's body
## and it follows. CombatHUD uses one for the character you're commanding and one for
## their target.

@export var radius := 0.8
## Half the ring's tube width, in metres.
@export var thickness := 0.08
@export var color := Color(0.35, 0.9, 1.0)
@export var pulse_speed := 3.0
@export var pulse_amount := 0.15

var _time := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius + thickness
	torus.rings = 48
	torus.ring_segments = 8
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = color
	torus.material = _material
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.scale.y = 0.3  # flatten the tube so it reads as a ring painted on the floor
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + sin(_time * pulse_speed) * pulse_amount
	scale = Vector3(pulse, 1.0, pulse)


## Recolours the ring after it has been built (e.g. when it moves to another combatant).
func set_color(value: Color) -> void:
	color = value
	if _material != null:
		_material.albedo_color = value
