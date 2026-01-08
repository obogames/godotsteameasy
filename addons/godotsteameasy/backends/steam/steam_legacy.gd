extends Node
class_name SteamLegacyBackend

var channel: int
var connected: bool = false
var _empty = PackedByteArray()

@export var net_base: INet


# @export var steam: SteamManager

func _init() -> void:
	channel = 0

	Steam.connect("p2p_session_request", _on_p2p_session_request)
	Steam.connect("p2p_session_connect_fail", _on_p2p_connect_fail)


func recv():
	if not connected:
		return

	var packet_size: int = Steam.getAvailableP2PPacketSize(0)
	# No more packets
	if packet_size <= 0:
		return

	var this_packet: Dictionary = Steam.readP2PPacket(packet_size, 0)

	if not this_packet:
		_chat_log("!! Read an empty packet with non-zero size!")
		return
	
	return [this_packet['remote_steam_id'], this_packet['data']]


func send(target: int, data: PackedByteArray) -> bool:
	if not connected:
		return false

	return Steam.sendP2PPacket(
		target, data, Steam.P2P_SEND_UNRELIABLE, channel
	)

func setup_connection(target: int):
	var accept_result = Steam.acceptP2PSessionWithUser(target)
	await get_tree().create_timer(0.1).timeout
	var session_state = Steam.getP2PSessionState(target)
	_chat_log("-- P2P session state with %s: %s" % [target, JSON.stringify(session_state)])

	connected = true


func _on_p2p_session_request(remote_id: int) -> void:
	_chat_log("@@ _on_p2p_session_request from: %s" % remote_id)

	# Get the requester's name
	var requester_name: String = Steam.getFriendPersonaName(remote_id)
	_chat_log("-- P2P session request from: %s (%s)" % [requester_name, remote_id])

	# Accept the P2P session; can apply logic to deny this request if needed
	var accept_result = Steam.acceptP2PSessionWithUser(remote_id)
	if accept_result:
		_chat_log("-- Successfully accepted P2P session from: %s" % requester_name)
	else:
		_chat_log("!! Failed to accept P2P session from: %s (%s)" % [requester_name, remote_id])


func _on_p2p_connect_fail(steam_id: int, session_error: int) -> void:
	# If no error was given
	if session_error == 0:
		_chat_log("!! Session failure with %s [no error given]." % steam_id)
	# Else if target user was not running the same game
	elif session_error == 1:
		_chat_log("!! Session failure with %s [target user not running the same game]." % steam_id)
	# Else if local user doesn't own app / game
	elif session_error == 2:
		_chat_log("!! Session failure with %s [local user doesn't own app / game]." % steam_id)
	# Else if target user isn't connected to Steam
	elif session_error == 3:
		_chat_log("!! Session failure with %s [target user isn't connected to Steam]." % steam_id)
	# Else if connection timed out
	elif session_error == 4:
		_chat_log("!! Session failure with %s [connection timed out]." % steam_id)
	# Else if unused
	elif session_error == 5:
		_chat_log("!! Session failure with %s [unused]." % steam_id)
	# Else no known error
	else:
		_chat_log("!! Session failure with %s [unknown error %s]" % [steam_id, session_error])


func _chat_log(s):
	print("[SteamDebug] "+s)
