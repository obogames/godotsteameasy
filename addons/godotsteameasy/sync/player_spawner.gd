@icon("res://addons/godotsteameasy/gizmo/spawner.png")
extends Node3D

## Default player scene to instantiate. Its script must have a `set_data` function, with an INet.AuthInfo parameter
@export var player_prefab: PackedScene

## Player scene to instantiate for the client's local player (controller). If this is left empty, `player_prefab` is used for the local player as well.
@export var my_player_prefab: PackedScene


@onready var net: INet = get_tree().get_first_node_in_group("net_core")
var inited = false


func _ready() -> void:
	if not visible:
		return

	if Globals.net.me != null and Globals.net.lobby_info != null:
		# _on_lobby_event was already called from a different scene
		spawn_players()
	else:
		net.lobby_event.connect(_on_lobby_event)


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if not inited and user.uid == Globals.net.me.uid and type == INet.EVENT_JOIN:
		# TODO: ITT: net is not ready yet, how can we handle this
		spawn_players()
		inited = true


func spawn_players():
	for uid in net.lobby_info.members.keys():
		spawn_player(uid)


func spawn_player(uid: int):
	var member = net.lobby_info.members[uid]
	var player: Node

	if uid == net.me.uid and my_player_prefab != null:
		player = my_player_prefab.instantiate()
	else:
		player = player_prefab.instantiate()

	player.set_data(member)
	add_child(player)
