extends Control

@onready var window_base: Panel = $OutBorder/WindowBase
@onready var title_string: Label = $OutBorder/WindowBase/Border/VBox/TitleBar/TitleString

@onready var title_drag_bar: Control = $OutBorder/WindowBase/VBox/TitleDragBar
@onready var resizer_left_up: Control = $ResizerH/ResizerVL/ResizerLU
@onready var resizer_left: Control = $ResizerH/ResizerVL/ResizerL
@onready var resizer_left_down: Control = $ResizerH/ResizerVL/ResizerLD
@onready var resizer_middle_down: Control = $ResizerH/ResizerM
@onready var resizer_right_up: Control = $ResizerH/ResizerVR/ResizerRU
@onready var resizer_right: Control = $ResizerH/ResizerVR/ResizerR
@onready var resizer_right_down: Control = $ResizerH/ResizerVR/ResizerRD
@onready var resizer_top_left: Control = $OutBorder/WindowBase/VBox/ResizerTop/ResizerTL
@onready var resizer_top_middle: Control = $OutBorder/WindowBase/VBox/ResizerTop/ResizerTM
@onready var resizer_top_right: Control = $OutBorder/WindowBase/VBox/ResizerTop/ResizerTR

var is_focus: bool
var is_dragging: Control
var start_drag_position: Vector2i
var mouse_start_drag_position: Vector2i

var windows_size_before: Vector2i

func _ready() -> void:
	get_window().borderless = true
	get_window().min_size = Vector2i(160, 90)
	
	resizer_left.add_to_group("resizer_left")
	resizer_right.add_to_group("resizer_right")
	resizer_middle_down.add_to_group("resizer_down")
	resizer_top_middle.add_to_group("resizer_up")
	
	resizer_left_up.add_to_group("resizer_left")
	resizer_left_up.add_to_group("resizer_up")
	resizer_left_down.add_to_group("resizer_left")
	resizer_left_down.add_to_group("resizer_down")
	resizer_right_up.add_to_group("resizer_right")
	resizer_right_up.add_to_group("resizer_up")
	resizer_right_down.add_to_group("resizer_right")
	resizer_right_down.add_to_group("resizer_down")
	resizer_top_left.add_to_group("resizer_left")
	resizer_top_left.add_to_group("resizer_up")
	resizer_top_right.add_to_group("resizer_right")
	resizer_top_right.add_to_group("resizer_up")

func _process(_delta: float) -> void:
	if is_dragging != null:
		if is_dragging == title_drag_bar:
			get_window().position = start_drag_position + (DisplayServer.mouse_get_position() - mouse_start_drag_position)
		if is_dragging.is_in_group("resizer_left"):
			get_window().size.x = windows_size_before.x - (DisplayServer.mouse_get_position().x - mouse_start_drag_position.x)
			if get_window().size.x > get_window().min_size.x:
				get_window().position.x = start_drag_position.x + (DisplayServer.mouse_get_position().x - mouse_start_drag_position.x)
		if is_dragging.is_in_group("resizer_right"):
			get_window().size.x = windows_size_before.x + (DisplayServer.mouse_get_position().x - mouse_start_drag_position.x)
		if is_dragging.is_in_group("resizer_up"):
			get_window().size.y = windows_size_before.y - (DisplayServer.mouse_get_position().y - mouse_start_drag_position.y)
			if get_window().size.y > get_window().min_size.y:
				get_window().position.y = start_drag_position.y + (DisplayServer.mouse_get_position().y - mouse_start_drag_position.y)
		if is_dragging.is_in_group("resizer_down"):
			get_window().size.y = windows_size_before.y + (DisplayServer.mouse_get_position().y - mouse_start_drag_position.y)
		
	title_string.text = get_window().title


func _on_title_bar_drag_input(event: InputEvent) -> void:
	drag_process(event, title_drag_bar)

func _on_left_up_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_left_up)
	
func _on_left_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_left)
	
func _on_left_down_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_left_down)

func _on_middle_down_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_middle_down)
	
func _on_right_up_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_right_up)
	
func _on_right_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_right)
	
func _on_right_down_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_right_down)
	
func _on_top_left_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_top_left)
	
func _on_top_middle_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_top_middle)
	
func _on_top_right_resizer_drag_input(event: InputEvent) -> void:
	drag_process(event, resizer_top_right)


func _on_close_button_pressed() -> void:
	get_tree().quit()


func drag_process(event: InputEvent, node: Control) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == 1: 
			if event.is_pressed():
				is_dragging = node
				start_drag_position = get_window().position
				windows_size_before = get_window().size
				mouse_start_drag_position = DisplayServer.mouse_get_position()
			else:
				is_dragging = null
