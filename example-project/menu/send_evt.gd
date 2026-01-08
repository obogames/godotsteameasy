extends Node

signal net_custom_event(event: Dictionary)


func _ready() -> void:
	net_custom_event.connect(_on_event)


func _on_pressed():
	net_custom_event.emit({"hello": "asd"})


func _on_event(event: Dictionary):
	print("Custom event received! ", event)
