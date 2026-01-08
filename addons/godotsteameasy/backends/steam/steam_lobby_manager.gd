@icon("res://addons/godotsteameasy/gizmo/steam.png")
class_name SteamManager extends Node

@export var steam_app_id: int = 480
@export var auto_accept_invite: bool = true
@export var quit_without_steam: bool = true

var net: INet

var inited: bool = false


func _ready() -> void:
	# Initialize steam
	if steam_app_id == -1:
		print("[Steam] Initializing skipped for debugging purposes!")
		return

	net = get_parent()

	OS.set_environment("SteamAppId", str(steam_app_id))
	OS.set_environment("SteamGameId", str(steam_app_id))
	var initialize_response: Dictionary = Steam.steamInitEx()
	#Steam.allowP2PPacketRelay(true)

	if initialize_response['status'] > 0:
		var reason: String = initialize_response.get('verbal')
		if not reason:
			reason = "Error code: " + str(reason)
		elif "probably not running" in reason:
			reason = "Check whether it's running!"

		var errmsg = "Failed to initialize Steam! Reason: %s (App ID: %s)" % [reason, steam_app_id]
		# TODO: nodes subscribe too late to catch this 
		net.lobby_error.emit(INet.EVENT_INIT_STEAM, errmsg)

		if quit_without_steam:
			handle_steam_fatal_error(errmsg)
		return
	# TODO: adjustable variable to check if subscribed
	elif not Steam.isSubscribed() and quit_without_steam:
		handle_steam_fatal_error("User does not own game! (App ID: %s)" % steam_app_id)
		return

	# TODO: nodes subscribe too late to catch this 
	print("[Steam] Initializing Steam (App ID: %s)" % steam_app_id)
	net.lobby_event.emit(INet.EVENT_INIT_STEAM, null, {"app_id": steam_app_id})

	inited = true
	#TODO: this hard-codes tree layout, how can we make the backend listen to an init event?
	var backend = get_parent().get_node("SteamBackend")
	backend.connected = true

	# TODO: token?

	Steam.lobby_created.connect(_on_lobby_created)
	# Lobby chat
	Steam.lobby_message.connect(_on_chat_message)
	# User's data change
	Steam.lobby_data_update.connect(_on_lobby_data_update)

	# Join / Invite
	Steam.lobby_chat_update.connect(_on_player_join)
	Steam.lobby_joined.connect(_on_lobby_join_attempt)
	Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.join_requested.connect(_on_join_requested)

	net.me.uid = Steam.getSteamID()
	net.me.username = Steam.getPersonaName()
	net.me.logged_in = true

	print("[Steam] Succesfully initialized! %s" % net.me.username)

func ensure_ok():
	if inited:
		return
	elif steam_app_id == -1:
		net.lobby_error.emit(INet.EVENT_INIT_STEAM, "Steam initialization was skipped! You're in dev mode!", {})
	else:
		net.lobby_error.emit(INet.EVENT_INIT_STEAM, "Steam initialization was never called!", {})


func get_updates_lobby_info(lobby: INet.LobbyInfo) -> Dictionary:
	var new_mode = Steam.getLobbyData(lobby.lobby_id, "game_mode")
	if new_mode != lobby.mode:
		lobby.mode = new_mode
		return {"attr": "mode", "value": new_mode}

	var new_status = Steam.getLobbyData(lobby.lobby_id, "status")
	if new_status != lobby.status:
		lobby.status = new_status
		return {"attr": "status", "value": new_status}

	var new_name = Steam.getLobbyData(lobby.lobby_id, "name")
	if new_name != lobby.name:
		lobby.name = new_name
		return {"attr": "name", "value": new_name}

	var new_owner = get_player_info(Steam.getLobbyOwner(lobby.lobby_id))
	if new_owner.uid != lobby.owner.uid:
		lobby.owner = new_owner
		return {"attr": "owner", "value": new_owner}

	return {}

func get_lobby_info(lobby_id) -> INet.LobbyInfo:
	if net.lobby_info != null and net.lobby_info.lobby_id == lobby_id:
		return net.lobby_info

	var li = INet.LobbyInfo.new()
	li.lobby_id = lobby_id
	li.mode = Steam.getLobbyData(li.lobby_id, "game_mode")
	li.status = Steam.getLobbyData(li.lobby_id, "status")
	li.name = Steam.getLobbyData(li.lobby_id, "name")
	li.owner = get_player_info(Steam.getLobbyOwner(li.lobby_id))

	return li

func get_player_info(uid: int) -> INet.AuthInfo:
	if net.lobby_info != null and net.lobby_info.members.has(uid):
		# caching from current lobby
		return net.lobby_info.members[uid]

	var pi = INet.AuthInfo.new()
	pi.uid = uid
	pi.username = Steam.getFriendPersonaName(uid)

	return pi

var _lobby_metadata: Dictionary
func create_lobby(metadata: Dictionary):
	_lobby_metadata = metadata

	var max_players: int = _lobby_metadata.get("max_players", 4)
	var lobby_type: int = Steam.LOBBY_TYPE_PUBLIC
	match _lobby_metadata.get("lobby_type"):
		"public":
			lobby_type = Steam.LOBBY_TYPE_PUBLIC
		"private":
			lobby_type = Steam.LOBBY_TYPE_PRIVATE
		"friends", "friends_only":
			lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
		"invisible":
			lobby_type = Steam.LOBBY_TYPE_INVISIBLE
		"private_unique":
			lobby_type = Steam.LOBBY_TYPE_PRIVATE_UNIQUE

	_lobby_metadata.erase("max_players")
	_lobby_metadata.erase("public")

	Steam.createLobby(lobby_type, max_players)

func leave_lobby():
	if net.lobby_info:
		Steam.leaveLobby(net.lobby_info.lobby_id)

func start_game(metadata: Dictionary):
	if !metadata.has("status"):
		metadata["status"] = "playing"

	set_metadata(net.lobby_info.lobby_id, metadata)
	Steam.setLobbyJoinable(net.lobby_info.lobby_id, true)

func set_metadata(lobby_id, metadata: Dictionary):
	if metadata.has("joinable"):
		# set metadata & information	
		var joinable: bool = metadata["joinable"]
		metadata.erase("joinable")
		Steam.setLobbyJoinable(net.lobby_info.lobby_id, joinable)

	for field_name in metadata.keys():
		Steam.setLobbyData(lobby_id, field_name, metadata[field_name])
	if "status" not in metadata:
		Steam.setLobbyData(lobby_id, "status", "lobby")


func open_hud(type: String, id = null):
	print("[Steam] open HUD %s (id=%s)" % [type, id])
	if type == "lobby_chat":
		Steam.activateGameOverlayToUser("chat", net.lobby_info.lobby_id)
	elif type == "friend_chat":
		Steam.activateGameOverlayToUser("chat", id)
	elif type == "user":
		Steam.activateGameOverlayToUser("steamid", id)
	elif type == "friends":
		Steam.activateGameOverlay("friends")
	elif type == "invite":
		Steam.activateGameOverlayInviteDialog(net.lobby_info.lobby_id)

	#Steam.activateGameOverlay("Friends")

	# TODO: add more steam overlays?
	#Steam.activateGameOverlayToUser("chat", net.lobby_info.lobby_id)
	#Steam.activateGameOverlayToStore(app_id)
	#Steam.activateGameOverlayToUser(type, steam_id)
	#Steam.activateGameOverlayToWebPage(url, webpage_mode)


func _on_lobby_created(connect: int, lobby_id: int) -> void:
	print("[Steam] @lobby_created %s (ID: %s)" % [connect, lobby_id])

	if connect != Steam.RESULT_OK:
		net.lobby_error.emit(INet.EVENT_CREATE, "differing lobby_id: %s != %s " % [lobby_id, net.lobby_info.lobby_id], {"lobby_id": lobby_id})
		return

	set_metadata(lobby_id, _lobby_metadata)
	Steam.allowP2PPacketRelay(true)

	# Fetch users' auth info in lobby
	# TODO: include metadata?
	net.lobby_info = get_lobby_info(lobby_id)

	net.lobby_event.emit(INet.EVENT_CREATE, net.me, {"lobby_id": lobby_id})

func _on_lobby_join_attempt(lobby_id: int, perms: int, locked: bool, response: int) -> void:
	print("[Steam] @lobby_joined - resp: %s perms: %s (ID: %s)" % [response, perms, lobby_id])

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# Get the failure reason
		var FAIL_REASON: String = "Unknown error: " + str(response) 
		match response:
			Steam.RESULT_FAIL:	FAIL_REASON = "This lobby no longer exists."
			Steam.RESULT_ACCESS_DENIED:	FAIL_REASON = "You don't have permission to join this lobby."
			4:	FAIL_REASON = "The lobby is now full."
			5:	FAIL_REASON = "Uh... something unexpected happened!"
			6:	FAIL_REASON = "You are banned from this lobby."
			7:	FAIL_REASON = "You cannot join due to having a limited account."
			8:	FAIL_REASON = "This lobby is locked or disabled."
			9:	FAIL_REASON = "This lobby is community locked."
			10: FAIL_REASON = "A user in the lobby has blocked you from joining."
			11: FAIL_REASON = "A user you have blocked is in the lobby."

		net.lobby_error.emit(INet.EVENT_JOIN, FAIL_REASON, {"lobby_id": lobby_id})
		return

	net.lobby_info = get_lobby_info(lobby_id)

	# list players
	for i in range(Steam.getNumLobbyMembers(lobby_id)):
		var player_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		net.lobby_info.members[player_id] = get_player_info(player_id)

	#if net.lobby_info.owner.uid == me.uid:
		#print("Player is the owner of lobby")

	net.lobby_event.emit(INet.EVENT_JOIN, net.me, {"lobby_id": lobby_id, "is_me": true})

func _on_lobby_data_update(success: Variant, lobby_id: int, member_or_room_id: int) -> void:
	if lobby_id != net.lobby_info.lobby_id:
		net.lobby_error.emit(INet.EVENT_UPDATE, "differing lobby_id: %s != %s " % [lobby_id, net.lobby_info.lobby_id], {"lobby_id": lobby_id})
		return

	var changes := get_updates_lobby_info(net.lobby_info)

	var editor: INet.AuthInfo
	if member_or_room_id != lobby_id:
		editor = net.lobby_info.members[member_or_room_id]
	else:
		editor = net.lobby_info.owner
		# Lobby is the auth info
		#editor = INet.AuthInfo.new()
		#editor.username = "Lobby"
		#editor.uid = member_or_room_id

	var attr = changes.get("attr")
	if attr:
		var value = changes.get("value")
		print("[Steam] @lobby %s=%s (ID: %s) -- success: %s, member_id: %s" % [attr, value, lobby_id, success, member_or_room_id])

		if attr == "status":
			if value == "playing":
				# Establish connection between allowed peers
				#for player in net.allowed_peers:
					#net.backend.setup_connection(player.uid)
					# Send START GAME signal
				#	net.send(player.uid, INet.NWC_START_GAME, {"uid": net.me.uid})

				net.lobby_event.emit(INet.EVENT_STARTED_GAME, editor, {
					"lobby_id": lobby_id,
					"success": success
				})
			elif value == "paused":
				net.lobby_event.emit(INet.EVENT_PAUSE_GAME, editor, {
					"lobby_id": lobby_id,
					"success": success
				})
			return

		net.lobby_event.emit(INet.EVENT_UPDATE, editor, {
			"lobby_id": lobby_id,
			"success": success,
			"attr": changes.get("attr"),
			"value": changes.get("value")
		})

func _on_player_join(lobby_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	if lobby_id != net.lobby_info.lobby_id:
		net.lobby_error.emit(INet.EVENT_JOIN, "differing lobby_id: %s != %s " % [lobby_id, net.lobby_info.lobby_id], {"lobby_id": lobby_id})
		return

	var isme = changed_id == net.me.uid
	print("[Steam] @lobby_chat_update %s, state: %s (ID: %s)" % [changed_id, lobby_id, chat_state])

	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		# Player joined
		var player = get_player_info(changed_id)
		#var kicker = null
		#if change_id != making_change_id:
			#kicker = get_player_info(making_change_id)

		net.lobby_info.members[changed_id] = player
		net.lobby_event.emit(INet.EVENT_JOIN, player, {"lobby_id": lobby_id, "me": isme})
	else:
		# Player left (or kicked)
		var player = net.lobby_info.members.get(changed_id)
		var reason = ""
		if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			reason = "Player left."
		else:
			reason = "Player was kicked."

		if player:
			net.lobby_info.members.erase(changed_id)
		net.lobby_event.emit(INet.EVENT_LEAVE, player, {"lobby_id": lobby_id, "me": isme, "reason": reason})

func _on_lobby_invite(friend_id: int, lobby_id: int, game_id: int):
	if auto_accept_invite:
		print("[Steam] %s auto joining lobby %s (_on_lobby_invite, game_id: %s)" % [friend_id, lobby_id, game_id])

		Steam.joinLobby(lobby_id)
	else:
		print("[Steam] @@ @_@ _on_lobby_invite called friend id: %s, lobby id: %s, game_id: %s" % [friend_id, lobby_id, game_id])

func _on_join_requested(lobby_id: int, friend_id: int):

	if auto_accept_invite:
		print("[Steam] %s auto joining lobby %s (_on_join_requested)" % [friend_id, lobby_id])
		Steam.joinLobby(lobby_id)
	else:
		print("[Steam] @@ @_@ _on_join_requested %s friend ID: %s" % [lobby_id, friend_id])

func _on_chat_message(lobby_id: int, user_id: int, message: String, chat_type: int):
	print("[Steam] @lobby_message: %s said: %s (ID: %s)" % [user_id, message, lobby_id])

	var player = net.lobby_info.members[user_id]
	var isme = player.uid == net.me.uid
	net.lobby_event.emit(INet.EVENT_CHAT, player, {"lobby_id": lobby_id, "message": message, "me": isme, "type": chat_type})


func handle_steam_fatal_error(err, ctx=null):
	await get_tree().process_frame

	var diag := AcceptDialog.new()
	diag.name = "_fatal_err"
	diag.dialog_text = err
	diag.confirmed.connect(fatal_error_diag_ok)
	diag.canceled.connect(fatal_error_diag_ok)
	get_tree().current_scene.add_child(diag)
	diag.popup_centered()


func fatal_error_diag_ok():
	var tree = get_tree()
	if tree != null:
		tree.quit()
