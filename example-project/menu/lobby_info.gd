@icon("res://addons/godotsteameasy/gizmo/nw.png")
extends Control

@export_file_path("*.tscn") var game_start_scene: String = "res://example_game/game_scene/game.tscn"
@export var direct_invite: bool = false

@export var avatar_loader: SteamAvatarLoader


func _ready() -> void:
	#Globals.steam.lobby_error.connect(_on_lobby_error)
	Globals.net.lobby_event.connect(_on_lobby_event)

func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	#print("##LOBBY INFO by %s type %s" % [user.username, type])
	if type == INet.EVENT_STARTED_GAME:
		Globals.SceneMgr.change_scene(game_start_scene)
		return

	if type == INet.EVENT_JOIN:
		# TODO: does this run for all joined members?
		print("@ JOIN ", user.uid, " ", Globals.net.me.uid, " - ", Globals.net.lobby_info.owner.uid)

	if user.uid == Globals.net.me.uid:
		if type == INet.EVENT_CREATE:
			show()
			if Globals.net.lobby_info != null:
				$HBoxContainer/VBoxContainer/LobbyName.text = Globals.net.lobby_info.name
		elif type == INet.EVENT_JOIN:
			show()
			if Globals.net.lobby_info != null:
				$HBoxContainer/VBoxContainer/LobbyName.text = Globals.net.lobby_info.name

			# Send handshake to server, this shall trigger network message session request
			# Wait a frame to allow Steam to establish the session first
			if not Globals.net.is_server:
				await get_tree().process_frame
				var success = Globals.net.send(
					Globals.net.lobby_info.owner.uid,
					INet.NWC_HANDSHAKE,
					{"uid": Globals.net.me.uid}
				)
				print("[LobbyInfo] Handshake: %s" % success)
		elif type == INet.EVENT_LEAVE:
			avatar_loader.clear()
			hide()

	for uid in Globals.net.lobby_info.members.keys():
		avatar_loader.reload_pfp(uid)

func _on_start_pressed() -> void:
	Globals.steam.start_game({})

func _on_leave_pressed() -> void:
	# TODO: doesnt work wtf
	hide()
	Globals.steam.leave_lobby()

func _on_invite_btn_pressed() -> void:
	if direct_invite:
		Globals.steam.open_hud("invite")
	else:
		Globals.steam.open_hud("friends")
