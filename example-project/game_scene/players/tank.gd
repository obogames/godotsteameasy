extends Node3D
class_name Tank

## Simple 3D tank controller
## WASD for movement, mouse for turret aiming, Space to shoot

@export var move_speed: float = 5.0
@export var turn_speed: float = 2.0
@export var turret_rotation_speed: float = 5.0
@export var shoot_range: float = 100.0

@export_category("Multiplayer")
@export var my_player: bool = false


@onready var body: MeshInstance3D = $Body
@onready var turret: MeshInstance3D = $Turret
@onready var barrel: MeshInstance3D = $Turret/Barrel
@onready var raycast: RayCast3D = $Turret/Barrel/RayCast3D

@onready var viewport = get_viewport()
@onready var camera = get_viewport().get_camera_3d()


#@export_flags_3d_render var my_player_render_layer: int = 0

var move_direction: Vector3 = Vector3.ZERO
var turn_input: float = 0.0


var net_info: INet.AuthInfo:
	get:
		if !has_meta("steam_id"):
			return null
		return Globals.net.lobby_info.members.get(get_meta("steam_id"))


func _ready():
	raycast.target_position = Vector3(0, 0, -shoot_range)
	raycast.enabled = true

	$voice_icon.visible = false

	# My Player (=client's player node) and other players 
	# can have entirely different scenes and sub-nodes,
	# however this means that StateSync node will not work!
	#    In this demo game, my player lacks a Camera, a username label and voice input, 
	#    otherwise they're equivalent nodes
	if my_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		# Set as speaker for Voice Sync
		# TODO: make it an easier call?
		# TODO: $ITT: 
		var voice_sync = Globals.net._syncers[INet.NWC_VOIP_P][0]
		voice_sync.my_speaker = voice_sync._node_path($voice)
		print("[Player] %s set voice authority" % self.name)
		$voice.queue_free()

	# uncomment, if it's an first-person camera game
	#if my_player:
		#$username.queue_free()
		#$voice_icon.queue_free()

		#camera.current = true
		#camera.visible = true
		## this is how you could opt-out from rendering the client's player node for first-person camera:
		#sub_mesh.layers = my_player_render_layer
	#else:
		## disable Camera for other players
		#camera.current = false
		#camera.queue_free()



func _process(delta):
	if my_player:
		_handle_input()
		_update_movement(delta)
		_update_turret_rotation(delta)


func set_data(info: INet.AuthInfo):
	# Set multiplayer authority, this function should normally be called before _ready!
	# and change the node depending the authority (other players VS my client's player node)

	set_meta("steam_id", info.uid)
	my_player = (info.uid == Globals.net.me.uid)

	# Set node name
	var uidstr = str(net_info.uid)
	name = "%s#%s" % [net_info.username, uidstr.substr(len(uidstr)-4)]

func toggle_voice(is_on: bool):
	$voice_icon.visible = is_on


func is_net_authority() -> bool:
	if !has_meta("steam_id") or Globals.net.me == null:
		return false
	return get_meta("steam_id") == Globals.net.me.uid


#region Movement

func _handle_input():
	# Movement input
	move_direction = Vector3.ZERO
	turn_input = 0.0
	
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_direction = transform.basis.x
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_direction = -transform.basis.x
	if Input.is_key_pressed(KEY_A):
		turn_input = 1.0
	if Input.is_key_pressed(KEY_D):
		turn_input = -1.0
	
	# Shooting
	if Input.is_action_just_pressed("ui_select") or Input.is_key_pressed(KEY_SPACE):
		_shoot()

func _update_movement(delta):
	# Apply turning
	if turn_input != 0.0:
		rotate_y(turn_input * turn_speed * delta)
	
	# Apply movement
	if move_direction != Vector3.ZERO:
		global_position += move_direction * move_speed * delta

func _update_turret_rotation(delta):
	var mouse_pos = viewport.get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0

	# Find intersection with a plane at turret height
	var turret_global_pos = turret.global_position
	var plane = Plane(Vector3.UP, turret_global_pos.y)
	var intersection = plane.intersects_ray(from, to)

	if intersection:
		var world_direction = (intersection - turret_global_pos).normalized()
		
		var local_direction = transform.basis.inverse() * world_direction
		
		var target_rotation = atan2(local_direction.x, local_direction.z) + PI
		var current_rotation = turret.rotation.y

		# Smooth rotation
		var lerp_factor = min(1.0, turret_rotation_speed * delta)
		turret.rotation.y = lerp_angle(current_rotation, target_rotation, lerp_factor)

func _shoot():
	# Update raycast to match barrel direction
	# The raycast is already positioned at the barrel tip and pointing forward
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		var hit_object = raycast.get_collider()
		
		print("Shot hit: ", hit_object, " at ", hit_point, " normal: ", hit_normal)
		# You can add visual effects here (particles, decal, etc.)
#endregion
