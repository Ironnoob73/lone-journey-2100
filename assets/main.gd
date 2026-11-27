extends Node3D

@onready var player: Player = $Player
@onready var interface: PlayerController

func _ready() -> void:
	match OS.get_name():
		"Android", "iOS":
			interface = preload("res://assets/interface/touch_screen_vertical/controller.tscn").instantiate()
		_:
			interface = preload("res://assets/interface/desktop/window.tscn").instantiate()
	add_child(interface)
	interface.set_player(player)
			
