@icon("res://addons/godotsteameasy/gizmo/nw.png")
extends Control

var lobby_list: Array = []


@export var steam: SteamManager
@export var net: INet

@export var handle_p2p: bool = false

const SPACEWAR_LOBBY_KEY = "is_geopoly_"
const SPACEWAR_LOBBY_VALUE = "gizmoka"


var packetid: int = 0
# ping & pong
var pacstarts: Dictionary[int, int] = {}

func _ready() -> void:
	#if steam == null:
		#steam = $NetBase/SteamBackend
	steam.lobby_error.connect(_on_lobby_error)
	steam.lobby_event.connect(_on_lobby_event)

	_chat_log("Steam initialized: %s" % steam.inited)

	# Lobbies list
	Steam.connect("lobby_match_list", _on_lobby_match_list)
	
	_chat_log("Debugger started! App ID: %s, User ID: %s " % [steam.steam_app_id, net.me.uid])

	# Display Steam App ID
	$VBoxContainer/HBoxContainer2/appid.text = str(steam.steam_app_id)
	$VBoxContainer/HBoxContainer2/username.text = net.me.username
	$VBoxContainer/HBoxContainer/List1Container/games_list.item_clicked.connect(_join_lobby)
	_update_lobby_list()


func _on_lobby_error(type: int, err: String, info: Dictionary):
	var err_type: String = ""
	match type:
		INet.EVENT_CREATE: err_type = "lobby create"
		INet.EVENT_UPDATE: err_type = "lobby create"
		INet.EVENT_JOIN: err_type = "lobby create"
		INet.EVENT_LEAVE: err_type = "lobby create"
		INet.EVENT_CHAT: err_type = "lobby create"
		INet.EVENT_STARTED_GAME: err_type = "lobby create"
		INet.EVENT_PAUSE_GAME: err_type = "lobby create"
		INet.EVENT_INIT_STEAM: err_type = "lobby create"
	_chat_log("!! %s error: %s" % [err_type, err])


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	match type:
		INet.EVENT_INIT_STEAM:
			_chat_log("steam initialized!!")
		INet.EVENT_CREATE:
			net.lobby_info.lobby_id = net.lobby_info.lobby_id
			#_ui_add_to_lobby_list(net.lobby_info)

			_update_lobby_list()
			_update_lobby_info()
			_update_players_list()
		INet.EVENT_UPDATE:
			_chat_log("lobby update %s (User: %s)" % [JSON.stringify(info), user.username])
			_update_lobby_info()
		INet.EVENT_JOIN:
			_chat_log("player %s join %s" % [user.username, JSON.stringify(info)])
			_update_players_list()
		INet.EVENT_LEAVE:
			_chat_log("player %s leave %s" % [user.username, JSON.stringify(info)])
			_update_players_list()
		INet.EVENT_CHAT:
			_chat_log("%s: %s [%s]" % [user.username, info["message"], info.get("type")])
		INet.EVENT_PAUSE_GAME:
			# TODO: implement @later
			_chat_log("paused game!")


func _on_refresh_pressed() -> void:
	_chat_log("_on_refresh_pressed called")
	_chat_log("INet.me? %s | INet.lobby_info? %s" % [net.me != null, net.lobby_info != null])

	# Request lobby list
	$VBoxContainer/HBoxContainer/List1Container/games_list.clear()

	_update_lobby_list()
	_update_lobby_info()
	_update_players_list()

func _on_lobby_match_list(lobbies: Array) -> void:
	$VBoxContainer/HBoxContainer/List1Container/games_list.clear()

	for lobby_id in lobbies:
		var lobby := steam.get_lobby_info(lobby_id)
		_ui_add_to_lobby_list(lobby)

func _ui_add_to_lobby_list(lobby: INet.LobbyInfo):
	$VBoxContainer/HBoxContainer/List1Container/games_list.add_item(lobby.name, null, false)
	lobby_list.append(lobby.lobby_id)

func _on_create_match_pressed() -> void:
	_chat_log("_on_create_match_pressed called")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4) # Max 4 players


func _join_lobby(index: int, at_position: Vector2, mouse_button_index: int):
	# request join
	var lobby_id = lobby_list[index]

	if lobby_id:
		_chat_log("@ Joining lobby: %s" % lobby_id)
		Steam.joinLobby(lobby_id)

func _update_lobby_info() -> void:
	if net.lobby_info == null or net.lobby_info.lobby_id == 0:
		return

	$VBoxContainer/HBoxContainer3/game_mode.text = net.lobby_info.mode
	$VBoxContainer/HBoxContainer3/owner_username.text = net.lobby_info.owner.username
	#var is_joinable = Steam.isLobbyJoinable(net.lobby_info.lobby_id)
	#$VBoxContainer/HBoxContainer/List1Container/HBoxContainer3/CheckBox.button_pressed = is_joinable
	

func _update_lobby_list():
	lobby_list.clear()
	$VBoxContainer/HBoxContainer/List1Container/games_list.clear()

	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter(SPACEWAR_LOBBY_KEY, SPACEWAR_LOBBY_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()


func _update_players_list() -> void:
	if net.lobby_info == null or net.lobby_info.lobby_id == 0:
		_chat_log("!! update players failed: not in lobby")
		return

	$VBoxContainer/HBoxContainer/List2Container/players_list.clear()
	for player in net.lobby_info.members.values():
		$VBoxContainer/HBoxContainer/List2Container/players_list.add_item(player.username)


func _on_set_game_mode_pressed() -> void:
	_chat_log("set game mode")

	var game_mode = $VBoxContainer/HBoxContainer3/game_mode.text
	if net.lobby_info.lobby_id != 0:
		Steam.setLobbyData(net.lobby_info.lobby_id, "game_mode", game_mode)
	else:
		_chat_log("!! set game mode failed: not in lobby")

func _on_start_game_pressed() -> void:
	_chat_log("starting game")

	Steam.setLobbyData(net.lobby_info.lobby_id, "status", "playing")


func _on_send_chat_pressed() -> void:
	_chat_log("_on_send_chat_pressed called")
	var message = $VBoxContainer/HBoxContainer/List3Container/chat/chat_message.text
	if net.lobby_info.lobby_id != 0 and not message.is_empty():
		Steam.sendLobbyChatMsg(net.lobby_info.lobby_id, message)
		$VBoxContainer/HBoxContainer/List3Container/chat/chat_message.text = ""

func _request_leave_lobby() -> void:

	# If in a lobby, leave it
	if net.lobby_info.lobby_id != 0:
		# Send leave request to Steam
		Steam.leaveLobby(net.lobby_info.lobby_id)

		# Wipe the Steam lobby ID then display the default lobby ID and player list title
		net.lobby_info.lobby_id = 0

		lobby_list.clear()
		# TODO: clear list


func _on_achi_btn_pressed() -> void:
	Steam.activateGameOverlay("Achievements")

func _on_store_btn_pressed() -> void:
	Steam.activateGameOverlay("Store")

func _on_steam_home_btn_pressed() -> void:
	Steam.activateGameOverlay("Overlay")


func _on_pingbtn_pressed() -> void:
	for player in net.lobby_info.members.values():
		if player.uid != net.me.uid:
			print("-- Sending PING to %s" % player.username)
			net.send(player.uid, 5, null)
			break


func _on_getstate_pressed() -> void:
	for player in net.lobby_info.members.values():
		if player.uid != net.me.uid:
			var state = Steam.getP2PSessionState(player.uid)
			_chat_log("P2P Sess State: %s" % player.uid)
			_chat_log("%s" % JSON.stringify(state))

func _on_establish_p2p_pressed() -> void:
	_chat_log("Manually establishing P2P sessions")
	for player in net.lobby_info.members.values():
		if player.uid != net.me.uid:
			_chat_log("Establishing P2P with %s (uid: %s)" % [player.username, player.uid])
			var accept_result = Steam.acceptP2PSessionWithUser(player.uid)
			_chat_log("Accept result: %s" % accept_result)
			
			# Check state after a short delay
			await get_tree().create_timer(0.2).timeout
			var state = Steam.getP2PSessionState(player.uid)
			_chat_log("Final state: %s" % JSON.stringify(state))


func _chat_log(s):
	print("[SteamDebug] "+s)
	var vsc: ItemList = $VBoxContainer/HBoxContainer/List3Container/logs_list
	vsc.add_item(s)

	vsc.select(vsc.item_count - 1)
	vsc.ensure_current_is_visible()
