extends Node
class_name MultiplayerBackend

@export var net: INet
const backend_type := "enet"

signal on_connected

var channel: int
var connected: bool = false
var _empty = PackedByteArray()

# Multiplayer API components
var peer: MultiplayerPeer
var server_info: Dictionary = {}
var client_info: Dictionary = {}

func _ready() -> void:
	# TODO: do we need config? or just use consol?
	#channel = int(Cfg.core_config("ch", 0))
	#var port = int(Cfg.core_config("port", 9001))
	#var host = Cfg.core_config("host", "127.0.0.1")
	var port = 9801
	var host = "127.0.0.1"

	if OS.has_feature("connect_host"):
		_setup_host(port)
	elif OS.has_feature("connect_client"):
		_setup_client(host, port)


func recv():
	if not connected or not peer:
		return null

	# Process incoming packets
	peer.poll()

	# Check for available packets
	if peer.get_available_packet_count() > 0:
		var packet_size = peer.get_available_packet_count()
		if packet_size <= 0:
			return null

		var packet_data = peer.get_packet()
		var sender_id = peer.get_packet_peer()
		
		return [sender_id, packet_data]


func send(target: int, data: PackedByteArray) -> bool:
	if not connected or not peer:
		return false

	# Send to specific peer
	peer.set_target_peer(target)
	return peer.put_packet(data) == OK
	#elif target == 0:
		## Broadcast to all peers
		#peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
		#return peer.put_packet(data) == OK

func setup_connection(target: int):
	pass

func _setup_host(port: int):
	# Create ENetMultiplayerPeer for hosting
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 4)

	if error != OK:
		print("Failed to create server: ", error)
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	connected = true
	print("Server started on port: ", port)

	net.lobby_info = _get_lobby_info(port, 1)
	net.me = _get_auth_info(multiplayer.get_unique_id())
	_on_peer_connected(1)

func _setup_client(host: String, port: int):
	# Create ENetMultiplayerPeer for client
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(host, port)
	
	if error != OK:
		print("Failed to create client: ", error)
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	print("Connecting to server: ", host, ":", port)
	net.lobby_info = _get_lobby_info(port, 1)
	net.me = _get_auth_info(multiplayer.get_unique_id())

func _get_lobby_info(lobby_id, owner_id) -> INet.LobbyInfo:
	var li = INet.LobbyInfo.new()
	li.lobby_id = lobby_id
	#li.mode = "defau"
	#li.status = Steam.getLobbyData(li.lobby_id, "status")
	li.name = "Local Lobby"
	li.owner = _get_auth_info(owner_id)
	return li

func _get_auth_info(id) -> INet.AuthInfo:
	var ai = INet.AuthInfo.new()
	ai.uid = id
	ai.username = "Player %d" % id
	
	# TODO: rest...

	return ai

func _on_peer_connected(id: int):
	connected = true
	net.lobby_info.members[id] = _get_auth_info(id)

	on_connected.emit(id)

func _on_peer_disconnected(id: int):
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		connected = false
	
	if net.lobby_info.members.has(id):
		net.lobby_info.members.erase(id)

func _on_connected_to_server():
	connected = true

func _on_connection_failed():
	print("Connection failed")
	connected = false

func _on_server_disconnected():
	print("Server disconnected")
	connected = false

func disconnect_peer():
	if peer:
		peer.close()
	connected = false
	print("Disconnected from multiplayer session")
