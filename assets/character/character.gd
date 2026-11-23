class_name CharacterMesh
extends Node3D

@onready var head_mesh: HeadMesh = $Head/HeadMesh

@onready var face: MeshInstance3D = $Head/HeadMesh/Face

func set_head_cube_ratio(value: float) -> void:
	head_mesh.cube_ratio = value
	on_head_mesh_changed()


func set_head_bevel_width(value: float) -> void:
	head_mesh.bevel_width = value
	on_head_mesh_changed()


func on_head_mesh_changed() -> void:
	face.position.z = head_mesh.get_actual_radius() + 0.01
