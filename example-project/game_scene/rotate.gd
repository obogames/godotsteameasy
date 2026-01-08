extends Node3D

@export var speed: float = 0.1

func _process(delta: float) -> void:
	rotation.y += speed * delta
