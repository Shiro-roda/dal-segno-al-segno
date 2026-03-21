extends RefCounted
## DeathAnimator — plays the technicolor static dissolve on a BattleActor,
## then calls a completion callback.
##
## Usage (from battle_manager):
##   await DeathAnimator.play(actor)
##   actor.queue_free()

const SHADER_PATH := "res://Shaders/death_dissolve.gdshader"
const DURATION    := 0.6   # longer to let all 5 split stages breathe


static func play(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return

	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return

	# Collect every MeshInstance3D on the actor
	var meshes : Array[MeshInstance3D] = []
	_collect_meshes(actor, meshes)
	if meshes.is_empty():
		await actor.get_tree().create_timer(0.1).timeout
		return

	# Build one shared material so all meshes dissolve in sync
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("dissolve",    0.0)
	mat.set_shader_parameter("time_offset", randf() * 100.0)

	# Swap all mesh materials to the dissolve mat
	for mi in meshes:
		if is_instance_valid(mi):
			for s in mi.get_surface_override_material_count():
				mi.set_surface_override_material(s, mat)
			# Also override the mesh's own material
			if mi.mesh != null:
				mi.mesh = mi.mesh  # keep mesh, overrides handle it

	# Hide the WorldSpacePanel so HP display vanishes immediately
	var panel := actor.get_node_or_null("WorldSpacePanel")
	if panel:
		panel.visible = false

	# Tween dissolve 0 -> 1
	var tw := actor.create_tween()
	tw.tween_method(
		func(v: float): mat.set_shader_parameter("dissolve", v),
		0.0, 1.0, DURATION
	).set_trans(Tween.TRANS_LINEAR)
	await tw.finished


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)
