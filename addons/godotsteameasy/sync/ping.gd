@icon("res://addons/godotsteameasy/gizmo/ping.png")
extends Timer

@export var enabled: bool = true

enum PingType {SERVER_TO_CLIENT, CLIENT_TO_SERVER}
@export var ping_type: PingType = PingType.CLIENT_TO_SERVER

@export var share_with_others: bool = true

@onready var net: INet = get_tree().get_first_node_in_group("net_core")

signal net_ping(event)
signal net_pong(event)

# Client
var _cli_packets_sent: Dictionary[int, int] = {}
var _cli_latest_pacid: int = 0

# Server - pings of all players
# Client - my ping
var _rtt_values: Dictionary = {}

var my_ping: Variant:
	get:
		return _rtt_values.get(str(net.me.uid))
	set(value):
		_rtt_values[str(net.me.uid)] = value

func _ready() -> void:
	if not is_stopped():
		stop()
	if not enabled:
		stop()
		return
	net.lobby_event.connect(_on_lobby_event)

func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if type == INet.EVENT_JOIN and user.uid == net.me.uid:
		if ping_type == PingType.CLIENT_TO_SERVER:
			if net.is_server:
				net_ping.connect(_on_ping)
			else:
				# Client - start sending pings & server RTT reply
				timeout.connect(_on_tick)
				net_pong.connect(_on_pong)
				start()


#if net.is_server == (ping_type == PingType.SERVER_TO_CLIENT):
func _on_tick():
	# Client - sends PING to server
	var now = Time.get_ticks_msec()
	_cli_latest_pacid += 1
	if _cli_latest_pacid > 4294967290:
		_cli_latest_pacid = 0
	_cli_packets_sent[_cli_latest_pacid] = now

	# client sends previous ping to server
	var ping = {"type": "ping", "pacid": _cli_latest_pacid, "rtt": my_ping}
	net_ping.emit(ping)


func _on_ping(ping):
	# Server - PING request received
	var packetid = ping["pacid"]
	var now = Time.get_ticks_msec()

	# cache list of pings 
	var client_uid = ping["_frm"]
	var rtt = ping.get("rtt")
	if rtt:
		_rtt_values[str(client_uid)] = rtt

	# send PONG back to client, also send other clients' RTTs
	var pong = {"type": "pong", "pacid": packetid, "halftime": now}
	if share_with_others:
		pong["rtts"] = _rtt_values.duplicate()

	net_pong.emit(pong)


func _on_pong(pong):
	# Client - PONG reply received, check ping RTT and save
	var packetid = pong["pacid"]
	if not _cli_packets_sent.has(packetid):
		push_error("[Ping] PONG received, but has no time start pair!")
		return

	var rtt: int = int(Time.get_ticks_msec() - _cli_packets_sent[packetid])
	if pong.get("rtts"):
		# cache RTT of other clients
		# TODO - this is unused, as other nodes listen to the event instead
		_rtt_values = pong["rtts"]
	else:
		# only save my RTT
		my_ping = rtt

	_cli_packets_sent.erase(packetid)
