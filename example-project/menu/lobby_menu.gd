@icon("res://addons/godotsteameasy/gizmo/nw.png")
extends Control

@export var lobby_metadata: Dictionary = {
	"name": "New Geo Lobby",
	"mode": "normal",

	"max_players": 6,

	# unique value so that we can test using SpaceWar and filter out our lobbies
	"is_geopoly_": "gizmoka",
}

func _ready() -> void:
	Globals.net.lobby_event.connect(_on_lobby_event)
	Globals.net.lobby_error.connect(_on_lobby_error)
	#hide()

func _on_create_presesd():
	Globals.steam.create_lobby(lobby_metadata)

func _on_exit():
	# TODO: dispose shit? emit global event?
	get_tree().quit()

func _on_settings_pressed():
	print("@@ settings pressed @@")

func _on_join_btn_pressed() -> void:
	Globals.steam.open_hud("friends")

func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if user.uid == Globals.net.me.uid:
		if type in [INet.EVENT_CREATE, INet.EVENT_JOIN]:
			hide()
		elif type == INet.EVENT_LEAVE:
			show()

func _on_lobby_error(type: int, err: String, info: Dictionary):
	if type == INet.EVENT_INIT_STEAM:
		# Exit game and warn user if they haven't started Steam (or it fails for other reasons)
		Globals.SceneMgr.on_fatal_error(err, info)
