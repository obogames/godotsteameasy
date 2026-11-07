extends Node3D
class_name Tank

## Simple 3D tank controller
## WASD for movement, mouse for turret aiming, Space to shoot

@export var move_speed: float = 5.0
@export var turn_speed: float = 2.0
@export var turret_rotation_speed: float = 5.0
@export var shoot_range: float = 100.0

@export var shoot_cooldown: float = 0.25
@export var laser_color: Color = Color(1.0, 0.15, 0.1)
@export var laser_duration: float = 0.15

@export var respawn_time: float = 3.0

const MAX_HP: int = 10

@export_category("Multiplayer")
@export var my_player: bool = false


## Net signals (relayed by SignalNwNode, the tank is in the "net_signal" group)
## client -> server: "I pressed fire"; handled only on the server
signal net_shoot_request(event)
## server -> everyone: result of the server-side raycast (+ damage / kill info and updated stats)
signal net_shot_fired(event)
## server -> everyone: a dead tank came back to life
signal net_respawned(event)


@onready var body: MeshInstance3D = $Body
@onready var turret: MeshInstance3D = $Turret
@onready var barrel: MeshInstance3D = $Turret/Barrel
@onready var raycast: RayCast3D = $Turret/Barrel/RayCast3D

@onready var viewport = get_viewport()
@onready var camera = get_viewport().get_camera_3d()


var move_direction: Vector3 = Vector3.ZERO
var turn_input: float = 0.0
var _shoot_cooldown_left: float = 0.0
## Mirrors game_data.hp > 0 on every peer (driven by net_shot_fired / net_respawned)
var is_alive: bool = true

# https://www.instagram.com/reels/DfYUF-RR2ST/
func _ready():
	# shooting uses a direct space-state raycast (see _server_raycast)
	raycast.enabled = false

	$voice_icon.visible = false

	# Shooting: only the server resolves shots, everyone displays/logs the result.
	# (net signals are also emitted locally, so the server's own requests land here too)
	if Globals.net.is_server:
		net_shoot_request.connect(_on_shoot_server_request)
	net_shot_fired.connect(_on_shot_fired)
	net_respawned.connect(_on_respawned)

	# My Player (=client's player node) and other players 
	# can have entirely different scenes and sub-nodes,
	# however this means that StateSync node will not work!
	#    In this demo game, my player lacks a Camera, a username label and voice input, 
	#    otherwise they're equivalent nodes
	if my_player:
		#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Set as speaker for Voice Sync
		# TODO: handle multiple syncers? they shouldn't exist, no?
		var syncers = Globals.net._syncers[INet.NWC_VOIP_P]
		if len(syncers) > 0:
			var voice_sync = syncers[0]
			voice_sync.my_speaker = voice_sync._node_path($voice)
			print("[Player] %s set voice authority" % self.name)
			$voice.queue_free()


func _process(delta):
	_shoot_cooldown_left = max(0.0, _shoot_cooldown_left - delta)
	if my_player and is_alive:
		_handle_input()
		_update_movement(delta)
		_update_turret_rotation(delta)


## Set multiplayer authority, this function should normally be called before _ready!
## and change the node depending the authority (other players VS my client's player node)
func set_data(info: INet.AuthInfo):
	set_meta("steam_id", info.uid)
	my_player = (info.uid == Globals.net.me.uid)

	# Set node name
	var uidstr = str(info.uid)
	name = "%s#%s" % [info.username, uidstr.substr(len(uidstr)-4)]
	$username.text = info.username

	call_deferred("set_children_data", info)

## State sync on other physics bodyparts:
func set_children_data(info: INet.AuthInfo):
	# turret's rotation is also broadcasted to other players
	turret.set_meta("steam_id", info.uid)
	#barrel.set_meta("steam_id", info.uid)

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

	# Input is polled directly (not via events), so GUI focus doesn't block it on its own:
	# ignore the keyboard while the player is typing into a text field (e.g. the chat)
	if _is_typing():
		return

	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_direction = transform.basis.x
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_direction = -transform.basis.x
	if Input.is_key_pressed(KEY_A):
		turn_input = 1.0
	if Input.is_key_pressed(KEY_D):
		turn_input = -1.0
	
	# Shooting
	if Input.is_action_just_pressed("ui_select"):
		_shoot()

func _is_typing() -> bool:
	var focus := viewport.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

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

#endregion


#region Shooting

func _shoot():
	if _shoot_cooldown_left > 0.0:
		return
	_shoot_cooldown_left = shoot_cooldown

	# The turret isn't state-synced (only the root transform is), so send our aim along.
	# Server: the signal is handled locally right away (SignalNwNode doesn't transmit server_only from the server)
	# Client: SignalNwNode sends it to the server
	# TODO: make Turret node part of net_state
	net_shoot_request.emit({
		"turret_yaw": turret.rotation.y,
		"_to": "server_only",
	})


func _on_shoot_server_request(event: Dictionary):
	# Server only: resolve the shot on the server's copy of this tank
	var shooter_uid: int = SignalNwNode.get_client_uid(event)
	if shooter_uid != get_meta("steam_id", -1):
		push_error("[Tank] %s: shoot request from %s, who doesn't own this tank" % [name, shooter_uid])
		return

	var shooter_data = _game_data(shooter_uid)
	if shooter_data == null or shooter_data.hp <= 0:
		# dead tanks can't shoot
		return

	if event.has("turret_yaw"):
		turret.rotation.y = float(event["turret_yaw"])

	var origin: Vector3 = barrel.global_position
	var direction: Vector3 = -turret.global_basis.z.normalized()
	var end: Vector3 = origin + direction * shoot_range
	var hit := _server_raycast(origin, end)

	var result := {
		"shooter": shooter_uid,
		"from": [origin.x, origin.y, origin.z],
		"hit": not hit.is_empty(),
		"_to": "broadcast",
	}
	
	if hit:
		var p: Vector3 = hit["position"]
		result["to"] = [p.x, p.y, p.z]
		result["target"] = _describe_collider(hit["collider"])

		# handle game stats & death respawn logic
		var victim := _tank_of_collider(hit["collider"])
		if victim != null and victim != self:
			var victim_uid: int = victim.get_meta("steam_id", -1)
			var victim_data = _game_data(victim_uid)
			if victim_data != null and victim_data.hp > 0:
				victim_data.hp = max(0, victim_data.hp - shooter_data.dmg)
				result["victim"] = victim_uid
				result["damage"] = shooter_data.dmg
				result["killed"] = victim_data.hp <= 0

				if result["killed"]:
					victim_data.deaths += 1
					victim_data.streak = 0

					shooter_data.kills += 1
					shooter_data.streak += 1
					shooter_data.max_streak = max(shooter_data.max_streak, shooter_data.streak)

					victim._schedule_respawn()

				result["victim_stats"] = _stats_to_dict(victim_data)
	else:
		result["to"] = [end.x, end.y, end.z]

	result["shooter_stats"] = _stats_to_dict(shooter_data)

	# Broadcast to all clients; also emitted locally, so the server logs it too
	net_shot_fired.emit(result)


func _schedule_respawn():
	# Server only: called on the victim tank
	get_tree().create_timer(respawn_time).timeout.connect(_server_respawn)


func _server_respawn():
	var uid: int = get_meta("steam_id", -1)
	var data = _game_data(uid)
	if data == null:
		return
	data.hp = MAX_HP
	data.streak = 0

	net_respawned.emit({
		"uid": uid,
		"stats": _stats_to_dict(data),
		"_to": "broadcast",
	})


func _on_respawned(event: Dictionary):
	# Everyone (server + clients)
	var stats: Dictionary = event.get("stats", {})
	_apply_stats(event.get("uid"), stats)
	_set_alive(true)
	print("[Tank] %s respawned with %s HP" % [name, stats.get("hp")])


func _set_alive(alive: bool):
	is_alive = alive
	visible = alive
	# dead tanks shouldn't block shots
	$Hitbox/CollisionShape3D.set_deferred("disabled", not alive)


func _tank_of_collider(collider: Object) -> Tank:
	if collider is Node and collider.name == "Hitbox":
		return collider.get_parent() as Tank
	return null


func _find_tank(uid: int) -> Tank:
	for t in get_parent().get_children():
		if t is Tank and t.get_meta("steam_id", -1) == uid:
			return t
	return null


func _game_data(uid: int):
	if Globals.net.lobby_info == null or not Globals.net.lobby_info.members.has(uid):
		return null
	return Globals.net.lobby_info.members[uid].game_data


func _stats_to_dict(data) -> Dictionary:
	return {
		"hp": data.hp,
		"kills": data.kills,
		"deaths": data.deaths,
		"streak": data.streak,
		"max_streak": data.max_streak,
	}


func _apply_stats(uid, stats: Dictionary):
	# Mirror the server's authoritative game_data on clients (no-op on the server)
	if uid == null or stats.is_empty():
		return
	var data = _game_data(int(uid))
	if data == null:
		return
	for key in stats:
		data.set(key, int(stats[key]))


func _server_raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)

	# don't hit our own hull
	var exclude: Array[RID] = []
	for child in find_children("*", "CollisionObject3D", true, false):
		exclude.append(child.get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)


func _describe_collider(collider: Object) -> String:
	# "Hitbox" bodies report their owner (e.g. the tank) instead of themselves
	if collider is Node:
		var node: Node = collider
		if node.name == "Hitbox" and node.get_parent() != null:
			return str(node.get_parent().name)
		return str(node.name)
	return str(collider)


func _on_shot_fired(event: Dictionary):
	# Everyone (server + clients)
	var shooter = event.get("shooter")
	var victim = event.get("victim")
	var ss: Dictionary = event.get("shooter_stats", {})
	var vs: Dictionary = event.get("victim_stats", {})
	_apply_stats(shooter, ss)
	_apply_stats(victim, vs)

	if event.get("hit"):
		print("[Tank] %s (uid %s) fired: HIT %s at %s" % [name, shooter, event.get("target"), event.get("to")])
	else:
		print("[Tank] %s (uid %s) fired: missed" % [name, shooter])

	if victim != null:
		var victim_tank := _find_tank(int(victim))
		var victim_name = victim_tank.name if victim_tank != null else str(victim)
		print("    -> %s took %s dmg, hp left: %s" % [victim_name, event.get("damage"), vs.get("hp")])
		if event.get("killed"):
			print("    -> %s was KILLED (deaths: %s), respawning in %ss" % [victim_name, vs.get("deaths"), respawn_time])
			if victim_tank != null:
				victim_tank._set_alive(false)

	if not ss.is_empty():
		print("    -> shooter stats: hp %s, kills %s, deaths %s, streak %s, max_streak %s" % [ss.get("hp"), ss.get("kills"), ss.get("deaths"), ss.get("streak"), ss.get("max_streak")])

	var f: Array = event.get("from", [])
	var t: Array = event.get("to", [])
	if f.size() == 3 and t.size() == 3:
		_draw_laser(Vector3(f[0], f[1], f[2]), Vector3(t[0], t[1], t[2]))


func _draw_laser(from: Vector3, to: Vector3):
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = laser_color

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.top_level = true # vertices are in world space
	add_child(line)
	line.global_transform = Transform3D.IDENTITY
	get_tree().create_timer(laser_duration).timeout.connect(line.queue_free)

#endregion
