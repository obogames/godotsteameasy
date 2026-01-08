@icon("res://addons/godotsteameasy/gizmo/sync.png")
class_name StateSyncerSimple extends Node

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
	var sent_packet_idx: int = 0
	# This is the largest packet received from the server
	#var recv_packet_idx: int = 0
	# This is the latest packet, whose value was applied to the node's property
	# also guarantees that packets are not applied twice
	var applied_packet_idx: int = 0


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

	net.lobby_event.connect(_on_lobby_event)

	# Resolve NodeType complex rules into PhysicsAttributes
	if sync_node_type != null:
		_attributes.append_array(sync_node_type.replace_attribute_representation())
	_attributes.append_array(sync_attributes)


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
		var sync: PacketSyncDescriptor = _syncables[node_path][1]
		var jitter_buffer: SlidingBuffer = _syncables[node_path][2]
		# get latest value of jitter buffer:
		var target_state = jitter_buffer.latest

		if not target_state or sync.applied_packet_idx >= target_state["id"]:
			# only apply messages that are newer than the most recently applied packet!
			continue
		sync.applied_packet_idx = target_state["id"]

		var node: Node = _syncables[node_path][0]

		for attr in _attributes:
			if !target_state.has(attr.attribute_name):
				continue

			# TODO: interpolation type
			match attr.apply_value_type:
				PhysicsAttribute.ApplyValueType.SNAP:
					# e.g.: node.linear_velocity = target_linear_velocity
					node.set(attr.attribute_name, target_state.get(attr.attribute_name))
				PhysicsAttribute.ApplyValueType.DAMP:
					# e.g.: node.position = lerp(node.position, target_position, 0.1)
					node.set(attr.attribute_name, 
						lerp(node.get(attr.attribute_name), target_state.get(attr.attribute_name), attr.damp_value)
					)
				PhysicsAttribute.ApplyValueType.INTERPOLATE_LINEAR:
					# TODO: implement interpolation
					push_error("Unimplemented interpolation!")
				PhysicsAttribute.ApplyValueType.INTERPOLATE_ANGLE:
					# TODO: implement interpolation
					push_error("Unimplemented interpolation!")
				PhysicsAttribute.ApplyValueType.INTERPOLATE_SLERP:
					# TODO: implement interpolation
					push_error("Unimplemented interpolation!")


func _on_tick():
	# TODO: Check if game is paused

	for node_path in _syncables.keys():
		var node: Node = _syncables[node_path][0]
		if !is_net_authority(node):
			# only send state info for player's owned objects!
			continue

		var sync: PacketSyncDescriptor = _syncables[node_path][1]

		sync.sent_packet_idx += 1

		# only include attributes whose value did change
		if serialization == StateSerialization.JSON_FORMAT:
			var data = {"id": sync.sent_packet_idx, "cm": node_path}
	
			var changing_attributes = 0
			for attr in _attributes:
				var value = node.get(attr.attribute_name)

				# TODO: because of this logic, unreliable packet is only sent once. this is not gud
				if attr.last_sent_value == null or attr.last_sent_value != value:
					attr.last_sent_value = value
					data[attr.attribute_name] = _to_repr(value)
					changing_attributes += 1

			if changing_attributes > 0:
				net.broadcast_to_peers(INet.NWC_STATE_SYNC, data, {"reliable": false})
		elif serialization == StateSerialization.BINARY_FORMAT:
			# TODO: itt
			pass
		else:
			push_error("Not implemented State Serialization format!")

			#net.broadcast_to_peers(INet.NWC_STATE_SYNC, data, {"reliable": false, "raw": true}) # see _prepare_packet


# net_core calls this
# TODO: bug -- "cm" identifies the node, not the StateSyncer Node!!
# 		so we can only have one syncer node per scene, which is wrong
#		TODO: identify SyncerNode by unique ID, so that net_core can call _recv_packet for the right syncer!
func _on_data_received(from, data):
	# redistribute to other clients
	if net.is_server:
		var opts = {"except": from, "reliable": false, "format": INet.PacketFormat.FORMAT_JSON}
		if !net.broadcast(INet.NWC_VOIP_P, data, opts):
			push_error("[StateSync] propagate from recv failed (uid: %d) %s" % [from, data])
			print("###@ DON'T DISS IT LIKE MY PEOPLE WANNA")

	var scene = get_tree().current_scene
	var node = scene.get_node(data["cm"])
	if not node or !node.is_in_group(physics_component_group):
		return
	var node_path = _node_path(node)

	var sync: PacketSyncDescriptor = _syncables[node_path][1]
	var jitter_buffer: SlidingBuffer = _syncables[node_path][2]

	if serialization == StateSerialization.JSON_FORMAT:
		for attr in data:
			data[attr] = _to_native(data[attr], typeof(node.get(attr)))
	else:
		push_error("Not implemented State Deserialization format!")

	jitter_buffer.add(data)
	#sync.recv_packet_idx = data["id"]


func register_component(node: Node):
	if !node.is_in_group(physics_component_group):
		return

	var path = _node_path(node)
	print("[StateSync] registered %s node: %s" % [type_string(typeof(node)), path])

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
	return node.get_meta("steam_id") == net.me.uid

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
		return _repr_basis(value.basis)
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
		# Serialized as basis only (same as Basis)
		return Transform3D(_to_native_basis(repr))
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
