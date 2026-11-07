extends Node

@export var output_interval: float = 0.5
@export var fps_label: Label
@export var ping_label: Label

@onready var net: INet = get_tree().get_first_node_in_group("net_core")

var time := 0.0

func _process(delta: float) -> void:
	time+= delta
	if time > output_interval:
		time = 0

		# Display FPS
		if fps_label:
			var fps := Engine.get_frames_per_second()
			fps_label.text = "FPS: " + str(fps)

		# Display ping
		if ping_label:
			var ping := net.me.ping
			ping_label.text = "PING: " + str(ping)
