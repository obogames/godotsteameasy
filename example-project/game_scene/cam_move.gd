extends Camera3D

@export var enabled: bool = true
@export var move_speed: float = 6.0
@export var mouse_sensitivity: float = 0.002

var yaw := 0.0
var pitch := 0.0

func _ready() -> void:
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if enabled and event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
		rotation = Vector3(pitch, yaw, 0)

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var dir := Vector3.ZERO

	if Input.is_action_pressed("ui_up"):
		dir -= transform.basis.z
	if Input.is_action_pressed("ui_down"):
		dir += transform.basis.z
	if Input.is_action_pressed("ui_left"):
		dir -= transform.basis.x
	if Input.is_action_pressed("ui_right"):
		dir += transform.basis.x

	if dir != Vector3.ZERO:
		global_position += dir.normalized() * move_speed * delta
