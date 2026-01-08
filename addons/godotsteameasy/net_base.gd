@icon("res://addons/godotsteameasy/gizmo/nw.png")
class_name INet extends Node

# Children node
var backend: Node

var me: AuthInfo = AuthInfo.new()
var lobby_info: LobbyInfo

# TODO: make it possible to have multiple Syncer nodes in a scene and identify them somehow
var _syncers: Dictionary[int, Array] = {
	NWC_STATE_SYNC: [],
	NWC_VOIP_P: [],
	NWC_SIGNAL_P: [],
}


var is_server: bool:
	get:
		if me == null or lobby_info == null or lobby_info.owner == null:
			return false
		return me.uid == lobby_info.owner.uid


var is_online: bool:
	get:
		if not backend:
			return false
		elif me == null or lobby_info == null or lobby_info.owner == null:
			return false
		return backend.connected


var allowed_peers: Array[AuthInfo]:
	# returns the players i am allowed to send packets to
	get:
		if lobby_info == null:
			return []

		var valid: Array[AuthInfo] = []
		if is_server:
			for player in lobby_info.members.values():
				if player.uid != me.uid:
					valid.append(player)
		else:
			# clients only communicate to server
			valid.append(lobby_info.owner)

		return valid

# Custom events you can subscribe to TODO: refactor to enum?
const EVENT_CREATE = 1
const EVENT_UPDATE = 2
const EVENT_JOIN = 3
const EVENT_LEAVE = 4
const EVENT_CHAT = 5
const EVENT_STARTED_GAME = 6
const EVENT_PAUSE_GAME = 7
const EVENT_INIT_STEAM = 8

signal lobby_event(type: int, user: INet.AuthInfo, info: Dictionary)
signal lobby_error(type: int, err: String, info: Dictionary)


enum PacketFormat {
	FORMAT_JSON,	# JSON format defined by JSON.stringify() and str_to_var
	FORMAT_BINARY,	# BIN format, defined by var_to_bytes and bytes_to_var
	FORMAT_RAW,		# BIN raw format, no serialization, the bytes are forwarded to the handler class directly
	FORMAT_RESERVED # (no use-case)
}

enum PacketTransmit {
	TRANSMIT_PROPAGATE,		# Server propagates received packets to other clients
	TRANSMIT_SERVER_ONLY,	# Server does not propagate received packets
}


class AuthInfo:
	var uid: Variant
	var username: String
	var token: String
	var token_type: String

	var logged_in: bool = false

	# game data
	var iso: String
	var civ: String


class LobbyInfo:
	var lobby_id: int
	var owner: AuthInfo
	var members: Dictionary = {}#[int, AuthInfo]
	var name: String

	# game settings
	var mode: String
	var status: String = "lobby"


# Built-in network commands, user can extend these (1000-1100 are reserved)
const NWC_HANDSHAKE = 200
const NWC_START_GAME = 201
const NWC_PAUSE_GAME = 202
const NWC_SIGNAL_P = 205

const NWC_VOIP_P = 210

const NWC_STATE_SPAWN = 220
const NWC_STATE_SYNC = 221


func _ready():
	backend = get_child(0)

	register_syncers()
	get_tree().scene_changed.connect(register_syncers)


func uname(uid=true):
	## Utility function to get lobby member's username
	if uid == null:
		return "null"
	elif uid:
		uid = me.uid

	if uid not in lobby_info.members:
		return "#"+str(uid)
	return lobby_info.members[uid].username


func send(target: int, cmd: int, data: Variant, opts = {}) -> bool:
	if not backend.connected:
		return false
	var pac: PackedByteArray = _prepare_packet(cmd, data, opts)

	return backend.send(target, pac, opts)


func broadcast(cmd: int, data: Variant, opts = {}) -> bool:
	# real broadcast, can be used for fully p2p games (mesh)
	if not backend.connected:
		return false

	var was_ok = true
	var pac: PackedByteArray = _prepare_packet(cmd, data, opts)

	var except = []
	except = opts.get("except", [])
	opts.erase("except") # backend doesn't need this info:

	for player in lobby_info.members.values():
		if player.uid == me.uid or except.has(player.uid):
			continue
		if not backend.send(player.uid, pac, opts):
			was_ok = false
	return was_ok

func broadcast_to_peers(cmd: int, data: Variant, opts = {}) -> bool:
	# A direct alternative to signals, where clients only send packets to server, and server broadcasts it to other clients 
	if not backend.connected:
		return false

	if is_server:
		return broadcast(cmd, data, opts)
	else:
		return send(lobby_info.owner.uid, cmd, data, opts)


func _prepare_packet(cmd: int, data: Variant, opts={}) -> PackedByteArray:
	# overridable method
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(cmd)

	# control flags sent to the server
	# [0][1] 	packet format (0 JSON, 1 Binary, 2 Raw Binary, 3 ?)
	# [2][3]	transmit type (0 Propagate to clients, 1 Server Only, 2 ? 3 ?)
	# [4-7]		?
	var flags: int = 0
	#if opts.get("transmit"):
		#flags |= (int(opts.get("transmit")) << 2)
	#if opts.get("reliable"):
		#flags |= (1 << 4)

	var fmt = opts.get("format", PacketFormat.FORMAT_JSON)
	flags |= fmt
	buffer.put_u8(flags)

	if fmt == PacketFormat.FORMAT_JSON:
		buffer.put_string(JSON.stringify(data))
	elif fmt == PacketFormat.FORMAT_BINARY:
		buffer.put_var(data)
	elif fmt == PacketFormat.FORMAT_RAW:
		if opts.has("prepare_packet"):
			opts["prepare_packet"].call(data, buffer)
	else:
		_prepare_custom_packet(cmd, data, buffer)

	return buffer.get_data_array()

func _recv_packet(from: int, msgid: int, packet: PackedByteArray, is_reliable: bool):
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	buffer.seek(0)

	var cmd := buffer.get_u8()
	var flags = buffer.get_u8()
	var data: Variant = null
	var opts = {
		"format": 	flags & 0b0011,
		#"transmit": flags & 0b1100,
		"reliable": is_reliable # not part of the flags header byte, but steam.recv has this info
		# other 4 bits are open for future flags
	}

	if opts["format"] == PacketFormat.FORMAT_JSON:
		# JSON message
		# instead of JSON.parse_string, which ignores ints
		data = str_to_var(buffer.get_string())
	elif opts["format"] == PacketFormat.FORMAT_BINARY:
		# Binary message
		data = buffer.get_var()
	elif opts["format"] == PacketFormat.FORMAT_RAW:
		#buffer.get_data() ?
		data = buffer

	# TODO: refactor: include `frm` as part of the header and not the JSON (in opts["has_frm"]=true, bit 3)
	# TODO: and send propagation before it's handled

	if _syncers.has(cmd):
		# TODO: how to support multiple syncers, especially important for PhysicsSync
		_syncers[cmd][0]._on_data_received(from, data)
	elif cmd in [NWC_HANDSHAKE, NWC_START_GAME, NWC_PAUSE_GAME]:
		# TODO: tie to verbose option?
		print("[Net] handshake (%s): %s" % [cmd, data])
	else:
		_recv_custom_packet(cmd, msgid, from, buffer)

func _prepare_custom_packet(cmd: int, data: Variant, buffer: StreamPeerBuffer):
	# overridable method for sending custom commands
	push_error("[Net] NOT_IMPLEMENTED: _prepare_custom_packet")

func _recv_custom_packet(cmd: int, msgid: int, from: int, buffer: StreamPeerBuffer):
	# overridable method for receiving custom commands
	push_error("[Net] NOT_IMPLEMENTED: _recv_custom_packet")


func register_syncer(syncer: Node):
	if !syncer.is_in_group("net_syncer"):
		return

	if syncer is SignalSyncer:
		_syncers[NWC_SIGNAL_P].append(syncer)
	elif syncer is StateSyncerSimple:
		_syncers[NWC_STATE_SYNC].append(syncer)
	elif syncer is VoiceSyncer:
		_syncers[NWC_VOIP_P].append(syncer)

func register_syncers():
	var tree = get_tree()
	assert(tree.get_node_count_in_group("net_core") == 1)

	for sync_cmd in _syncers:
		_syncers[sync_cmd].clear()

	for syncer in tree.get_nodes_in_group("net_syncer"):
		register_syncer(syncer)
