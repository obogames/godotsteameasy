@icon("res://addons/godotsteameasy/gizmo/ping.png")
class_name PingNwNode extends Timer

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

## My own RTT to the server (-1 = unknown). Stored on the AuthInfo
var my_ping: int:
	get:
		return net.me.ping
	set(value):
		_set_ping(net.me.uid, value)


func get_ping(uid: int) -> int:
	if net.lobby_info == null or not net.lobby_info.members.has(uid):
		return -1
	return net.lobby_info.members[uid].ping


func _set_ping(uid: int, rtt: int):
	# net.me and lobby_info.members[me] can be different AuthInfo objects: keep both in sync
	if uid == net.me.uid:
		net.me.ping = rtt

	if net.lobby_info == null or not net.lobby_info.members.has(uid):
		return
	var member: INet.AuthInfo = net.lobby_info.members[uid]
	if member.ping == rtt:
		return
	member.ping = rtt


func _collect_pings() -> Dictionary:
	# wire format: {"<uid>": rtt}, string keys survive JSON serialization
	var rtts := {}
	for member in net.lobby_info.members.values():
		if member.ping >= 0:
			rtts[str(member.uid)] = member.ping
	return rtts

func _ready() -> void:
	if not is_stopped():
		stop()
	if not enabled:
		stop()
		return
	net.lobby_event.connect(_on_lobby_event)

	# Lobby may have been joined in a previous scene
	if net.lobby_info != null:
		_start_pinging()

func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if type == INet.EVENT_JOIN and user != null and user.uid == net.me.uid:
		_start_pinging()


var _started := false
func _start_pinging():
	if _started or ping_type != PingType.CLIENT_TO_SERVER:
		return
	_started = true

	if net.is_server:
		# server has no RTT to itself, but display it as 0 ms for everyone
		_set_ping(net.me.uid, 0)
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

	# client sends previous ping to server (null if not measured yet)
	# _to: SignalNwNode only transmits events that have a recipient
	var ping = {
		"type": "ping", "pacid": _cli_latest_pacid, "rtt": my_ping if my_ping >= 0 else null,
		"_to": "server_only",
	}
	net_ping.emit(ping)


func _on_ping(ping):
	# Server - PING request received
	var packetid = ping["pacid"]
	var now = Time.get_ticks_msec()

	# save the client's reported RTT on its AuthInfo
	if not ping.has("_frm"):
		return
	var client_uid := int(ping["_frm"])
	var rtt = ping.get("rtt")
	if rtt != null:
		_set_ping(client_uid, int(rtt))

	# send PONG back to the pinging client only (pacids are per-client), also send other clients' RTTs
	var pong = {"type": "pong", "pacid": packetid, "halftime": now, "_to": client_uid}
	if share_with_others:
		pong["rtts"] = _collect_pings()

	net_pong.emit(pong)


func _on_pong(pong):
	# Client - PONG reply received, check ping RTT and save
	var packetid = pong["pacid"]
	if not _cli_packets_sent.has(packetid):
		push_error("[Ping] PONG received, but has no time start pair!")
		return

	var rtt: int = int(Time.get_ticks_msec() - _cli_packets_sent[packetid])
	_cli_packets_sent.erase(packetid)

	# save other clients' RTTs shared by the server
	var rtts = pong.get("rtts")
	if rtts:
		for uid_str in rtts:
			var uid := int(uid_str)
			if uid != net.me.uid:
				_set_ping(uid, int(rtts[uid_str]))

	# always save my own freshly measured RTT
	my_ping = rtt
