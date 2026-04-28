extends CharacterBody3D

@onready var cam_viewport: SubViewport = $SubViewport
@onready var player_camera: Camera3D = $SubViewport/Marker3D/Camera3D
@onready var camera_marker: Marker3D = $SubViewport/Marker3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@onready var interface: Control = $Interface

@export var camera_height: float = 0.0
@export var camera_rotation: float = 0.0

var perspective_in_rotate: bool = false
var perspective_rad: float = 0
var perspective_size: float = 10
var perspective_from: Vector2

@onready var TouchScreenCam: Control = $Interface/VBoxContainer/TouchScreenCam
@onready var TouchPosition: TextureRect = $Interface/TouchPosition
@onready var TouchScreenCamControl: TouchScreenButton = $Interface/VBoxContainer/TouchScreenCam/TouchScreenCamControl
var touch_cam_index: int = -1

@onready var Knob: TouchScreenButton = $Interface/VBoxContainer/BottomPanel/MovePad/Knob
var knob_finger_index: int = -1
var knob_drag_from: Vector2
var knob_drag_velocity: Vector2

func _ready() -> void:
	player_camera.size = 10

func _process(_delta: float) -> void:
	camera_marker.global_position = lerp(camera_marker.global_position, global_position, 0.1)
	camera_marker.global_rotation.y = lerp_angle(camera_marker.global_rotation.y, global_rotation.y, 0.1)
	player_camera.position.y = lerp(player_camera.position.y, player_camera.size, 0.1)
	player_camera.position.z = lerp(player_camera.position.z, player_camera.size, 0.1)
	
	camera_marker.rotation.x = lerp(camera_marker.rotation.x, deg_to_rad(camera_rotation), 0.1)
	player_camera.v_offset = lerp(player_camera.v_offset, camera_height, 0.1)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3
	if input_dir:
		direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	elif knob_drag_velocity:
		direction = (transform.basis * Vector3(knob_drag_velocity.x, 0, knob_drag_velocity.y))
		if knob_drag_velocity.length() > 1:
			direction = direction.normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
	cam_viewport.size = TouchScreenCam.size * (get_tree().root.size.x / TouchScreenCam.size.x)
	TouchScreenCamControl.global_position = TouchScreenCam.global_position + (TouchScreenCam.size / 2)
	var touch_cam_area: RectangleShape2D = TouchScreenCamControl.shape
	touch_cam_area.size = TouchScreenCam.size

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("perspective"):
		perspective_from = interface.get_global_mouse_position()
		perspective_in_rotate = true
	if event.is_action_released("perspective"):
		perspective_in_rotate = false
		perspective_rad = self.global_rotation.y
		perspective_size = player_camera.size
	if event is InputEventMouseMotion and Input.is_action_pressed("perspective"):
		tird_person_setup(interface.get_global_mouse_position())
		
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event
		if touch_event.is_pressed():
			if Knob.is_pressed() and knob_finger_index == -1:
				knob_finger_index = touch_event.index
				knob_drag_from = touch_event.position
			elif TouchScreenCamControl.is_pressed() and touch_cam_index == -1:
				touch_cam_index = touch_event.index
				perspective_from = touch_event.position
				perspective_in_rotate = true
				TouchPosition.show()
				TouchPosition.position = perspective_from - (TouchPosition.size / 2)
		else:
			if touch_event.index == knob_finger_index:
				knob_finger_index = -1
				knob_drag_from = Vector2.ZERO
				knob_drag_velocity = Vector2.ZERO
			elif touch_event.index == touch_cam_index:
				touch_cam_index = -1
				TouchPosition.hide()
				perspective_rad = self.global_rotation.y
				perspective_size = player_camera.size
				perspective_from = Vector2.ZERO
				perspective_in_rotate = false
	if event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event
		if drag_event.index == knob_finger_index:
			knob_drag_velocity = drag_event.position - knob_drag_from
		elif drag_event.index == touch_cam_index:
			tird_person_setup(drag_event.position)
			TouchPosition.position = drag_event.position - (TouchPosition.size / 2)
		

func tird_person_setup(pos:Vector2, not_init:bool = true) -> void:
	if perspective_in_rotate:
		rotation.y = perspective_rad - deg_to_rad((pos.x if not_init else 0.0) - perspective_from.x)
		player_camera.size = clamp(perspective_size + ((pos.y if not_init else 0.0) - perspective_from.y) * 0.1,5,50)
