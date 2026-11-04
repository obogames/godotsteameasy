extends Label

@export var output_interval: float = 0.5
@export var ping_component: PingNwNode

var time := 0.0

func _process(delta: float) -> void:
	time+= delta
	if time > output_interval:
		time = 0
		var fps := Engine.get_frames_per_second()

		text = "FPS: " + str(fps)
