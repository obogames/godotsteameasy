class_name SingleplayerBackend extends Node

var _msg_queue = []
@export var username: String = "Oboforty"
var connected: bool

@onready var net: INet = self.get_parent()

func _ready() -> void:
	print("[Singleplayer] disabling Steam & ENet")
	net.get_node("SteamBackend").queue_free()
	net.get_node("Steam").queue_free()

	connected = true

	net.me = INet.AuthInfo.new()
	net.me.uid = 1
	net.me.username = username
	net.me.logged_in = true

	net.lobby_info = INet.LobbyInfo.new()
	net.lobby_info.members[net.me.uid] = net.me
	net.lobby_info.owner = net.me

	# Other users are added by ai nodes


func send(target: int, data: PackedByteArray, send_flags = null) -> bool:
	
	return true

func _process(delta):
	# recv for player
	for message in _msg_queue:
		net._recv_packet(
			message["identity"],
			message["message_number"],
			message["payload"],
			message["is_reliable"]
		)
