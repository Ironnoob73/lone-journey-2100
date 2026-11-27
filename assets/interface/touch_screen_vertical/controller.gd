class_name PlayerController
extends Control

var player: Player

@onready var touch_screen_cam: TextureRect = $VBoxContainer/TouchScreenCam
@onready var touch_position: TextureRect = $TouchPosition
@onready var touch_screen_cam_control: TouchScreenButton = $VBoxContainer/TouchScreenCam/TouchScreenCamControl
var touch_cam_index: int = -1

@onready var Knob: TouchScreenButton = $VBoxContainer/BottomPanel/MovePad/Knob
var knob_finger_index: int = -1
var knob_drag_from: Vector2

func set_player(gived_player: Player) -> void:
	player = gived_player
	touch_screen_cam.texture = player.cam_viewport.get_texture()
	
	get_window().borderless = false
	get_window().size = Vector2i(450, 800)
	get_window().content_scale_size = Vector2i(450, 800)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("perspective"):
		player.perspective_from = get_global_mouse_position()
		player.perspective_in_rotate = true
	if event.is_action_released("perspective"):
		player.perspective_in_rotate = false
		player.perspective_rad = self.global_rotation.y
		player.perspective_size = player.player_camera.size
	if event is InputEventMouseMotion and Input.is_action_pressed("perspective"):
		player.tird_person_setup(get_global_mouse_position())
		
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event
		if touch_event.is_pressed():
			if Knob.is_pressed() and knob_finger_index == -1:
				knob_finger_index = touch_event.index
				knob_drag_from = touch_event.position
			elif touch_screen_cam_control.is_pressed() and touch_cam_index == -1:
				touch_cam_index = touch_event.index
				player.perspective_from = touch_event.position
				player.perspective_in_rotate = true
				touch_position.show()
				touch_position.position = player.perspective_from - (touch_position.size / 2)
		else:
			if touch_event.index == knob_finger_index:
				knob_finger_index = -1
				knob_drag_from = Vector2.ZERO
				player.move_velocity = Vector2.ZERO
			elif touch_event.index == touch_cam_index:
				touch_cam_index = -1
				touch_position.hide()
				player.perspective_rad = self.global_rotation.y
				player.perspective_size = player.player_camera.size
				player.perspective_from = Vector2.ZERO
				player.perspective_in_rotate = false
	if event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event
		if drag_event.index == knob_finger_index:
			player.move_velocity = drag_event.position - knob_drag_from
		elif drag_event.index == touch_cam_index:
			player.tird_person_setup(drag_event.position)
			touch_position.position = drag_event.position - (touch_position.size / 2)
		
func _physics_process(_delta: float) -> void:
	player.cam_viewport.size = touch_screen_cam.size * (get_tree().root.size.x / touch_screen_cam.size.x)
	touch_screen_cam_control.global_position = touch_screen_cam.global_position + (touch_screen_cam.size / 2)
	var touch_cam_area: RectangleShape2D = touch_screen_cam_control.shape
	touch_cam_area.size = touch_screen_cam.size
