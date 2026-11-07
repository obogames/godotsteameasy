@icon("res://addons/godotsteameasy/gizmo/sync.png")
class_name StateSyncNwNode extends Node
## Syncs 2D/3D node state (position, velocity, custom properties...) between peers.
##
## - Tracks every node in [member physics_component_group] and identifies it by its scene-relative path.
## - Sending: every [member sync_interval], the owning peer (node meta "steam_id" == local uid)
##   broadcasts the changed [PhysicsAttribute]s as an unreliable NWC_STATE_SYNC packet (JSON or binary).
## - Receiving: packets are stored in a small per-node jitter buffer ordered by packet id. The server
##   also relays them to the other clients.
## - Applying: in _physics_process, the newest unapplied snapshot is applied to the node per attribute
##   (snap, damp, or linear lerp).

@export_group("Component Group")
@export var enabled: bool = true
@export var physics_component_group: String = "net_state"
@export var monitor_components: bool = true

@export_group("Synced Attributes")
## Type of the nodes in physics component group.
@export var sync_node_type: PhysicsNodeType
## List of custom attributes to sync. Users can also add transform fields, but can't control sub-fields like if they added sync_node_type
@export var sync_attributes: Array[PhysicsAttribute]
@export var interpolation_value = 0.1
@export var sync_interval: float = 0.1
@export var server_fps: int = 30
## Every N-th tick all attributes are sent, even unchanged ones (0 = only send changes)
@export var full_sync_every_n_ticks: int = 10

@export_group("Serialization")
# TODO: custom formats? gzip? etc
enum StateSerialization {JSON_FORMAT, BINARY_FORMAT}
@export var serialization = StateSerialization.JSON_FORMAT


@onready var net: INet = get_tree().get_first_node_in_group("net_core")
var inited: bool = false

# Caches the nodes belonging to this Sync's sub group
# they must have all the attributes defined in `sync_attributes` or `sync_node_types`
# TODO: hash keys of `node_path`
var _syncables: Dictionary[String, Array] = {}

# union of sync_node_types & sync_attributes
var _attributes: Array[PhysicsAttribute] = []

# network packet -- TODO: move this to a file?
class SlidingBuffer:
	var max_size: int = 5
	var arr: Array[Dictionary] = []

	func _init(s) -> void:
		max_size = s

	func add(item):
		if len(arr) >= max_size:
			arr.pop_front()
		arr.append(item)

		# make sure they are in order of sending
		arr.sort_custom(_sliding_buffer_cmp)

	var latest:
		get:
			if len(arr) == 0:
				return null
			return arr[len(arr)-1]

	func _sliding_buffer_cmp(a, b) -> bool:
		return a["id"] < b["id"]

class PacketSyncDescriptor:
	# This keeps an incrementing ID of the packets sent
	var sync_tick: int = 0
	# This is the largest packet received from the server
	#var recv_packet_idx: int = 0
	# This is the latest packet, whose value was applied to the node's property
	# also guarantees that packets are not applied twice
	var applied_packet_idx: int = 0


	# Last value sent across the network, per attribute name
	var last_sent_values: Dictionary = {}

	# Interpolation state, per attribute name: value at snapshot arrival -> snapshot value
	var interp_from: Dictionary = {}
	var interp_to: Dictionary = {}
	# Seconds elapsed since the last snapshot was applied
	var interp_elapsed: float = 0.0

	# Last time of receiving (msec)
	var recv_time = 0

	# Time between the last two state snapshots (seconds), by default 200ms
	var lerp_time = 0.2
	const MIN_LERP_TIME = 0.001
	const MAX_LERP_TIME = 0.5


	func snapshot_received():
		var now = Time.get_ticks_msec()
		if recv_time > 0:
			lerp_time = clampf((now - recv_time) / 1000.0, MIN_LERP_TIME, MAX_LERP_TIME)
		recv_time = now


func _ready() -> void:
	if not enabled:
		return
	var tree = get_tree()

	if monitor_components:
		tree.node_added.connect(register_component)
		tree.node_removed.connect(unregister_component)
		#tree.node_renamed.connect(_on_net_cmp_renamed)

	for node in tree.get_nodes_in_group(physics_component_group):
		register_component(node)

	# Resolve NodeType complex rules into PhysicsAttributes
	if sync_node_type != null:
		_attributes.append_array(sync_node_type.replace_attribute_representation())
	_attributes.append_array(sync_attributes)

	# Lobby may have been joined in a previous scene
	net.lobby_event.connect(_on_lobby_event)
	if net.lobby_info != null:
		inited = true


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if type == INet.EVENT_JOIN and user.uid == net.me.uid:
		inited = true

var _t = sync_interval

func _physics_process(delta: float) -> void:
	if not enabled or not inited:
		return

	_t -= delta
	if _t <= 0:
		_t = sync_interval
		_on_tick()

	#if TODO and game started
	#	return
	# TODO: filter out where node.multiplayer_autority() == Globals.net.me.uid ?
	#		cause that's like hacking

	for node_path in _syncables:
		var node: Node = _syncables[node_path][0]
		var synced: PacketSyncDescriptor = _syncables[node_path][1]
		var jitter_buffer: SlidingBuffer = _syncables[node_path][2]
		# get latest value of jitter buffer:
		var target_state = jitter_buffer.latest

		# only take snapshots that are newer than the most recently applied packet!
		if target_state and target_state["id"] > synced.applied_packet_idx:
			synced.applied_packet_idx = target_state["id"]
			synced.interp_elapsed = 0.0

			for attr in _attributes:
				var attr_name := attr.attribute_name
				if !target_state.has(attr_name):
					continue

				if attr.apply_value_type == PhysicsAttribute.ApplyValueType.SNAP:
					# e.g.: node.linear_velocity = target_linear_velocity
					node.set(attr_name, target_state[attr_name])
					synced.interp_to.erase(attr_name)
				else:
					# applied gradually below, over the following frames
					synced.interp_from[attr_name] = node.get(attr_name)
					synced.interp_to[attr_name] = target_state[attr_name]

		if synced.interp_to.is_empty():
			continue

		synced.interp_elapsed += delta
		# 0..1 progress towards the latest snapshot, spread over the measured snapshot interval
		var weight := clampf(synced.interp_elapsed / synced.lerp_time, 0.0, 1.0)

		for attr in _attributes:
			var attr_name := attr.attribute_name
			if !synced.interp_to.has(attr_name):
				continue
			var from = synced.interp_from[attr_name]
			var to = synced.interp_to[attr_name]

			match attr.apply_value_type:
				PhysicsAttribute.ApplyValueType.DAMP:
					# e.g.: node.position = lerp(node.position, target_position, 0.1), every frame
					node.set(attr_name, lerp(node.get(attr_name), to, attr.damp_value))
				PhysicsAttribute.ApplyValueType.INTERPOLATE_LINEAR:
					node.set(attr_name, lerp(from, to, weight))
				PhysicsAttribute.ApplyValueType.INTERPOLATE_ANGLE:
					node.set(attr_name, _interpolate_angle(from, to, weight))
				PhysicsAttribute.ApplyValueType.INTERPOLATE_SLERP:
					node.set(attr_name, _interpolate_slerp(from, to, weight))

			# interpolations are done once they reach the snapshot value; damping keeps going
			if weight >= 1.0 and attr.apply_value_type != PhysicsAttribute.ApplyValueType.DAMP:
				synced.interp_to.erase(attr_name)
				synced.interp_from.erase(attr_name)


func _on_tick():
	# TODO: Check if game is paused

	for node_path in _syncables.keys():
		var node: Node = _syncables[node_path][0]
		var synced: PacketSyncDescriptor = _syncables[node_path][1]

		# TODO: is this line really needed for StateSync? what do i want to achieve here
		if !is_net_authority(node):
			# only send state info for player's owned objects!
			continue

		synced.sync_tick += 1

		# Packets are unreliable, so every N-th tick resend all attributes,
		# otherwise a single lost packet would leave peers stale until the value changes again
		var full_sync := full_sync_every_n_ticks > 0 and synced.sync_tick % full_sync_every_n_ticks == 0

		var data = {"id": synced.sync_tick, "cm": node_path}
		var changing_attributes = 0
		for attr in _attributes:
			var attr_name := attr.attribute_name
			var value = node.get(attr_name)

			# only include attributes whose value did change
			if full_sync or !synced.last_sent_values.has(attr_name) or synced.last_sent_values[attr_name] != value:
				synced.last_sent_values[attr_name] = value
				data[attr_name] = _to_repr(value) if serialization == StateSerialization.JSON_FORMAT else value
				changing_attributes += 1

		if changing_attributes == 0:
			continue

		if serialization == StateSerialization.JSON_FORMAT:
			net.broadcast_to_peers(INet.NWC_STATE_SYNC, data, {"reliable": false})
		elif serialization == StateSerialization.BINARY_FORMAT:
			net.broadcast_to_peers(INet.NWC_STATE_SYNC, data, {"reliable": false, "format": INet.PacketFormat.FORMAT_BINARY})
		else:
			push_error("Not implemented State Serialization format!")
			#net.broadcast_to_peers(INet.NWC_STATE_SYNC, data, {"reliable": false, "raw": true}) # see _prepare_packet


# net_core calls this
# TODO: bug -- "cm" identifies the node, not the StateSyncNwNodeer Node!!
# 		so we can only have one syncer node per scene, which is wrong
#		TODO: identify SyncerNode by unique ID, so that net_core can call _recv_packet for the right syncer!
func _on_data_received(from, data):
	# redistribute to other clients
	if net.is_server:
		var format = INet.PacketFormat.FORMAT_BINARY if serialization == StateSerialization.BINARY_FORMAT else INet.PacketFormat.FORMAT_JSON
		var opts = {"except": from, "reliable": false, "format": format}
		if !net.broadcast(INet.NWC_STATE_SYNC, data, opts):
			push_error("[StateSyncNwNode] propagate from recv failed (uid: %d) %s" % [from, data])
			print("###@ DON'T DISS IT LIKE MY PEOPLE WANNA")

	var scene = get_tree().current_scene
	var node = scene.get_node_or_null(data["cm"])
	if not node or !node.is_in_group(physics_component_group):
		return
	var node_path = _node_path(node)
	if !_syncables.has(node_path):
		return

	var synced: PacketSyncDescriptor = _syncables[node_path][1]
	var jitter_buffer: SlidingBuffer = _syncables[node_path][2]

	if serialization == StateSerialization.JSON_FORMAT:
		for attr in data:
			if attr == "id" or attr == "cm":
				continue
			data[attr] = _to_native(data[attr], typeof(node.get(attr)))
	elif serialization != StateSerialization.BINARY_FORMAT:
		# binary format is already deserialized to native types by net_base
		push_error("Not implemented State Deserialization format!")

	synced.snapshot_received()
	jitter_buffer.add(data)
	#sync.recv_packet_idx = data["id"]


func register_component(node: Node):
	if !node.is_in_group(physics_component_group):
		return

	var path = _node_path(node)
	print("[StateSyncNwNode] registered %s node: %s" % [type_string(typeof(node)), path])

	var sliding_buffer_max_size = int(server_fps / 12.0)
	_syncables[path] = [node, PacketSyncDescriptor.new(), SlidingBuffer.new(sliding_buffer_max_size)]

func unregister_component(node: Node):
	if !node.is_in_group(physics_component_group):
		return
	_syncables.erase(_node_path(node))

func _node_path(node: Node) -> String:
	var scene_name = get_tree().current_scene.name
	return str(node.get_path()).trim_prefix("/root/" + scene_name + "/")

func is_net_authority(node: Node) -> bool:
	return node.get_meta("steam_id", null) == net.me.uid

static func _interpolate_angle(from, to, weight: float):
	# shortest-path interpolation of angles in radians (e.g. rotation, Node3D.rotation)
	if from is float:
		return lerp_angle(from, to, weight)
	elif from is Vector2:
		return Vector2(lerp_angle(from.x, to.x, weight), lerp_angle(from.y, to.y, weight))
	elif from is Vector3:
		return Vector3(
			lerp_angle(from.x, to.x, weight),
			lerp_angle(from.y, to.y, weight),
			lerp_angle(from.z, to.z, weight)
		)
	return lerp(from, to, weight)

static func _interpolate_slerp(from, to, weight: float):
	# spherical interpolation of rotations / directions
	if from is Quaternion:
		return from.slerp(to, weight)
	elif from is Basis:
		return from.slerp(to, weight)
	elif from is Transform2D or from is Transform3D:
		return from.interpolate_with(to, weight)
	elif from is Vector2 or from is Vector3:
		return from.slerp(to, weight)
	return lerp(from, to, weight)

static func _to_repr(value):
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	elif value is Vector3 or value is Vector3i:
		return [value.x, value.y, value.z]
	elif value is Vector4 or value is Vector4i or value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	elif value is Color:
		# TODO: quantisize color r8 b8 g8 a8
		return [value.r, value.g, value.b, value.a]
	elif value is Transform2D:
		return [
			value.x.x, value.x.y,
			value.y.x, value.y.y,
			value.origin.x, value.origin.y
		]
	elif value is Transform3D:
		return _repr_basis(value.basis) + [value.origin.x, value.origin.y, value.origin.z]
	elif value is Basis:
		return _repr_basis(value)
	return value

static func _to_native(repr, typ: int):
	if typ == TYPE_VECTOR2:
		return Vector2(repr[0], repr[1])
	elif typ == TYPE_VECTOR2I:
		return Vector2i(repr[0], repr[1])
	elif typ == TYPE_VECTOR3:
		return Vector3(repr[0], repr[1], repr[2])
	elif typ == TYPE_VECTOR3I:
		return Vector3i(repr[0], repr[1], repr[2])
	elif typ == TYPE_VECTOR4:
		return Vector4(repr[0], repr[1], repr[2], repr[3])
	elif typ == TYPE_VECTOR4I:
		return Vector4i(repr[0], repr[1], repr[2], repr[3])
	elif typ == TYPE_QUATERNION:
		return Quaternion(repr[0], repr[1], repr[2], repr[3])
	elif typ == TYPE_COLOR:
		return Color(repr[0], repr[1], repr[2], repr[3])
	elif typ == TYPE_TRANSFORM2D:
		return Transform2D(
			Vector2(repr[0], repr[1]),
			Vector2(repr[2], repr[3]),
			Vector2(repr[4], repr[5])
		)
	elif typ == TYPE_TRANSFORM3D:
		# Serialized as flattened basis + origin
		return Transform3D(_to_native_basis(repr), Vector3(repr[9], repr[10], repr[11]))
	elif typ == TYPE_BASIS:
		return _to_native_basis(repr)

	return repr

static func _repr_basis(b: Basis):
	# Represents basis as a 3×3 basis flattened to flat matrix
	return [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z
	]

static func _to_native_basis(arr) -> Basis:
	# inverses _repr_basis output
	return Basis(
		Vector3(arr[0], arr[1], arr[2]),
		Vector3(arr[3], arr[4], arr[5]),
		Vector3(arr[6], arr[7], arr[8])
	)
