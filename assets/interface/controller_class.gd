@abstract
class_name PlayerController
extends Control

var camera: TextureRect
var player: Player


func _physics_process(_delta: float) -> void:
	if player:
		player.cam_viewport.size = camera.size * (get_tree().root.size.x / camera.size.x)


func set_player(gived_player: Player) -> void:
	player = gived_player
	camera.texture = player.cam_viewport.get_texture()
