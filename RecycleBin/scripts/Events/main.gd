@tool
extends Node

func _ready():
	var mesh_lib = load("res://mesh_library/cubes_mesh_lib.tres")
	var psx_mat = load("res://example/default_object.gdshader") # your crate shader material

	for id in mesh_lib.get_item_list():
		var mesh: Mesh = mesh_lib.get_item_mesh(id)
		if mesh:
			# Duplicate mesh so we don't overwrite shared resources
			var mesh_copy = mesh.duplicate(true)
			mesh_copy.surface_set_material(0, psx_mat)
			mesh_lib.set_item_mesh(id, mesh_copy)
			print("✅ Applied material to tile id:", id)
		else:
			print("⚠️ No mesh found for tile id:", id)

	ResourceSaver.save(mesh_lib, mesh_lib.resource_path)
	print("💾 Saved updated MeshLibrary to:", mesh_lib.resource_path)
