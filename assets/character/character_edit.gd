extends Node3D

@onready var character: CharacterMesh = $Character

@onready var head_cube_ratio_slider: HSlider = $VBoxContainer/HeadCubeRatioSlider
@onready var head_bevel_width_slider: HSlider = $VBoxContainer/HeadBevelWidthSlider
@onready var rotation_slider: HSlider = $VBoxContainer/RotationSlider

func _ready() -> void:
	head_cube_ratio_slider.value = character.head_mesh.cube_ratio
	head_bevel_width_slider.value = character.head_mesh.bevel_width

func _on_head_cube_ratio_value_changed(value: float) -> void:
	character.set_head_cube_ratio(value)


func _on_head_bevel_width_value_changed(value: float) -> void:
	character.set_head_bevel_width(value)


func _on_rotation_changed(value: float) -> void:
	character.rotation_degrees.y = value
