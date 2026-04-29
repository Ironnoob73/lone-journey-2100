class_name DemoTile extends Resource

@export var appearance: Texture2D
@export var weight: float = 1.0
@export_group("neighbor")
@export var up: Array[String]
@export var left: Array[String]
@export var right: Array[String]
@export var down: Array[String]
