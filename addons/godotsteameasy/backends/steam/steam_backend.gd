@icon("res://addons/godotsteameasy/gizmo/steam.png")
class_name SteamBackend extends Node

@export var max_recv_messages: int = 100

var channel: int = 0
var connected: bool = false

@onready var net: INet = self.get_parent()

# Connection states for debugging
const CONNECTION_STATE_NONE = 0
const CONNECTION_STATE_CONNECTING = 1
const CONNECTION_STATE_FINDING_ROUTE = 2
const CONNECTION_STATE_CONNECTED = 3
const CONNECTION_STATE_CLOSED_BY_PEER = 4
const CONNECTION_STATE_PROBLEM_DETECTED_LOCALLY = 5
const CONNECTION_STATE_WAIT = -1
const CONNECTION_STATE_LINGER = -2
const CONNECTION_STATE_DEAD = -3


func _ready() -> void:
	Steam.network_messages_session_request.connect(_on_nw_messages_session_request)
	Steam.network_messages_session_failed.connect(_on_nw_messages_session_failed)


func _process(delta):
	Steam.run_callbacks()

	if not connected:
		return
	# Receive messages on our channel using the new API
	var messages = Steam.receiveMessagesOnChannel(channel, max_recv_messages)

	for message in messages:
		if not message.has("payload") or not message.has("identity"):
			print("[SteamBackend] missing payload or identity. Error code: WTF?")
			continue

		# TODO: propagate is_reliable
		var was_reliable: bool = bool(message["flags"] & Steam.NETWORKING_SEND_RELIABLE)
		var remote_steam_id = message["identity"]
		var payload = message["payload"]

		net._recv_packet(
			message["identity"],
			message["message_number"],
			message["payload"],
			was_reliable
		)


func send(target: int, data: PackedByteArray, send_flags = null) -> bool:
	if not connected:
		return false

	var flags = Steam.NETWORKING_SEND_RELIABLE
	if send_flags:
		if send_flags.get("reliable"):
			if send_flags.get("nagle"):
				flags = Steam.NETWORKING_SEND_RELIABLE
			else:
				flags = Steam.NETWORKING_SEND_RELIABLE_NO_NAGLE
		else:
			if send_flags.get("nagle"):
				flags = Steam.NETWORKING_SEND_UNRELIABLE
			else:
				flags = Steam.NETWORKING_SEND_URELIABLE_NO_NAGLE

	# Use the new sendMessageToUser API
	var result = Steam.sendMessageToUser(target, data, flags, channel)

	# Check if the send was successful
	if result == Steam.RESULT_OK:
		return true
	elif result == Steam.RESULT_NO_CONNECTION:
		_chat_log("!! Failed to send message to %d: no connection (session not established yet?)" % target)
		return false
	elif result == Steam.RESULT_CONNECT_FAILED:
		_chat_log("!! Failed to send message to %d: connection failed" % target)
		return false
	elif result == Steam.RESULT_INVALID_PARAM:
		_chat_log("!! Failed to send message to %d: invalid parameter" % target)
		return false
	elif result == Steam.RESULT_LIMIT_EXCEEDED:
		_chat_log("!! Failed to send message to %d: rate limit exceeded" % target)
		return false
	else:
		_chat_log("!! Failed to send message to %d: error code %d" % [target, result])
		return false

func _on_nw_messages_session_request(uid: int):
	# If we're not a host, and someone is trying to communicate with us, we ignore them.
	#if not steam.net.is_server:
	#	return
	
	if Steam.acceptSessionWithUser(uid):
		print("[SteamBackend] new message session for %s" % uid)
		connected = true
	else:
		print("[SteamBackend] new message session for %s failed!" % [uid])


func _on_nw_messages_session_failed(reason: int, remote_steam_id: int, connection_state: int, debug_message: String) -> void:
	var reason_name = _get_connection_end_reason_name(reason)
	var state_name = _get_connection_state_name(connection_state)

	_chat_log("!! Session failed with %d" % remote_steam_id)
	_chat_log("   Reason: %s (%d)" % [reason_name, reason])
	_chat_log("   State: %s (%d)" % [state_name, connection_state])
	_chat_log("   Debug: %s" % debug_message)


func _get_connection_state_name(state: int) -> String:
	match state:
		CONNECTION_STATE_NONE: return "None"
		CONNECTION_STATE_CONNECTING: return "Connecting"
		CONNECTION_STATE_FINDING_ROUTE: return "Finding Route"
		CONNECTION_STATE_CONNECTED: return "Connected"
		CONNECTION_STATE_CLOSED_BY_PEER: return "Closed by Peer"
		CONNECTION_STATE_PROBLEM_DETECTED_LOCALLY: return "Problem Detected Locally"
		CONNECTION_STATE_WAIT: return "Wait"
		CONNECTION_STATE_LINGER: return "Linger"
		CONNECTION_STATE_DEAD: return "Dead"
		_: return "Unknown (%d)" % state

func _get_connection_end_reason_name(reason: int) -> String:
	# These are the most common reasons from the NetworkingConnectionEnd enum
	match reason:
		0: return "Invalid"
		1000: return "App Min"
		1999: return "App Max"
		2000: return "App Exception Min"
		2999: return "App Exception Max"
		3000: return "Local Min"
		3001: return "Local Offline Mode"
		3002: return "Local Many Relay Connectivity"
		3003: return "Local Hosted Server Primary Relay"
		3004: return "Local Network Config"
		3005: return "Local Rights"
		3999: return "Local Max"
		4000: return "Remote Min"
		4001: return "Remote Timeout"
		4002: return "Remote Bad Crypt"
		4003: return "Remote Bad Cert"
		4004: return "Remote Not Logged In"
		4005: return "Remote Not Running App"
		4006: return "Bad Protocol Version"
		4999: return "Remote Max"
		5000: return "Misc Min"
		5001: return "Misc Generic"
		5002: return "Misc Internal Error"
		5003: return "Misc Timeout"
		5004: return "Misc Relay Connectivity"
		5005: return "Misc Steam Connectivity"
		5006: return "Misc No Relay Sessions To Client"
		5999: return "Misc Max"
		_: return "Unknown (%d)" % reason

func _chat_log(s: String):
	print("[SteamBackend] " + s)
