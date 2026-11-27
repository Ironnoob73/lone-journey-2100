extends Node3D

@onready var player: Player = $Player
@onready var interface: PlayerController = $Interface

func _ready() -> void:
	interface.set_player(player)
