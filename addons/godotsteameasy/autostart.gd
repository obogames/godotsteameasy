@icon("res://addons/godotsteameasy/gizmo/spanner.png")
extends Node

# TODO: later: provide metadata from CMD line arguments


## 
@export var enabled: bool = true

@export_file_path("*.tscn") var game_start_scene: String = "res://example_game/game_scene/game.tscn"
## make `name` unique so that autostart connects the right lobby!
@export var lobby_metadata: Dictionary = {
	"name": "New Geo Lobby",

	"mode": "normal",
	"status": "lobby",
	"max_players": 6,
	# unique value so that we can test using SpaceWar and filter out our lobbies
	"is_geopoly_": "gizmoka",
}
@export var metadata_after_start: Dictionary = {
	"status": "playing"
}

## Wait for this amount of players before lobby starts
@export var lobby_host: String
@export var players_to_start: int = 2

@onready var net: INet = get_tree().get_first_node_in_group("net_core")
@onready var steam: SteamManager = net.get_node("Steam")

func _ready() -> void:
	if not enabled:
		return
	net.lobby_event.connect(_on_lobby_event)
	net.lobby_error.connect(_on_lobby_error)

	if net.me.username == lobby_host:
		steam.create_lobby(lobby_metadata)
	else:
		Steam.connect("lobby_match_list", _on_lobby_match_list)

		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		Steam.addRequestLobbyListStringFilter("name", lobby_metadata["name"], Steam.LOBBY_COMPARISON_EQUAL)
		Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array):
	# TODO: keep polling until 0->1?
	if len(lobbies) > 1:
		push_error("[Autostart] more than 1 lobby returned in list! %s " % lobbies)
		return
	# TODO: later: filter by host's ID not username and match ID in this function to connect
	Steam.joinLobby(lobbies[0])


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	print("LOBBY EVENT ", type, user.uid)
	var tree = get_tree()

	if type == INet.EVENT_CREATE:
		print("[Autostart] %s created" % net.lobby_info.name)
	elif type == INet.EVENT_JOIN:
		print("[Autostart] %s joined" % user.username)

		if user.uid == net.me.uid:
			if not net.is_server:
				await tree.process_frame
				var success = net.send(
					net.lobby_info.owner.uid,
					INet.NWC_HANDSHAKE,
					{"uid": net.me.uid}
				)

				# wait a bit
				await tree.create_timer(0.4).timeout

		if len(net.lobby_info.members) >= players_to_start:
			var str0 = ""
			for member in net.lobby_info.members.values():
				str0 += member.username + ", "
			print("[Autostart] lobby started with members: %s" % str0)

			steam.start_game(metadata_after_start)

	elif type == INet.EVENT_STARTED_GAME:
		print("[Autostart] game started")

		if game_start_scene:
			tree.change_scene_to_file(game_start_scene)


func _on_lobby_error(type: int, err: String, info: Dictionary):
	push_error("[Autostart] lobby error: %s (%s) -- %s" % [err, type, info])
	get_tree().quit()

func get_args():
	var args = OS.get_cmdline_args()

	var tests = []

	var current_arg = ""
	for arg in args:
		if arg.begins_with("--"):
			current_arg = arg
		elif current_arg == "--t":
			tests.append(arg)
	
	# if len(tests) > 0:
	# 	push_error("Please do not specify tests to run (--t) if you provide multiple test cases.")
	# 	return []

	return tests
