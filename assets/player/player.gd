class_name Player
extends CharacterBody3D

@onready var cam_viewport: SubViewport = $SubViewport
@onready var player_camera: Camera3D = $SubViewport/Marker3D/Camera3D
@onready var camera_marker: Marker3D = $SubViewport/Marker3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

@export var camera_height: float = 0.0
@export var camera_rotation: float = 0.0

var move_velocity: Vector2

var perspective_in_rotate: bool = false
var perspective_rad: float = 0
var perspective_size: float = 10
var perspective_from: Vector2

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
	elif move_velocity:
		direction = (transform.basis * Vector3(move_velocity.x, 0, move_velocity.y))
		if move_velocity.length() > 1:
			direction = direction.normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	

func tird_person_setup(pos:Vector2, not_init:bool = true) -> void:
	if perspective_in_rotate:
		rotation.y = perspective_rad - deg_to_rad((pos.x if not_init else 0.0) - perspective_from.x)
		player_camera.size = clamp(perspective_size + ((pos.y if not_init else 0.0) - perspective_from.y) * 0.1,5,50)
