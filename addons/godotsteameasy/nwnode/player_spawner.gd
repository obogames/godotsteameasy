@icon("res://addons/godotsteameasy/gizmo/spawner.png")
class_name SpawnerNwNode extends Node3D

## Default player scene to instantiate. Its script must have a `set_data` function, with an INet.AuthInfo parameter
@export var player_prefab: PackedScene

## Player scene to instantiate for the client's local player (controller). If this is left empty, `player_prefab` is used for the local player as well.
@export var my_player_prefab: PackedScene


@onready var net: INet = get_tree().get_first_node_in_group("net_core")

## Spawned player nodes, keyed by Steam uid
var players: Dictionary = {}


func _ready() -> void:
	if not visible:
		return

	# Always listen, so players joining/leaving later are spawned/despawned too
	net.lobby_event.connect(_on_lobby_event)

	if net.lobby_info != null:
		# Lobby was already joined in a previous scene (e.g. lobby menu -> game scene)
		spawn_players()


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if user == null:
		return

	if type == INet.EVENT_JOIN:
		if user.uid == net.me.uid:
			# I joined: spawn everyone already in the lobby (incl. me)
			spawn_players()
		else:
			# Someone else joined after me
			spawn_player(user.uid)
	elif type == INet.EVENT_LEAVE:
		despawn_player(user.uid)


func spawn_players():
	for uid in net.lobby_info.members.keys():
		spawn_player(uid)


func spawn_player(uid: int):
	if players.has(uid) or not net.lobby_info.members.has(uid):
		return

	var member = net.lobby_info.members[uid]
	var player: Node

	if uid == net.me.uid and my_player_prefab != null:
		player = my_player_prefab.instantiate()
	else:
		player = player_prefab.instantiate()

	player.set_data(member)
	players[uid] = player
	add_child(player)


func despawn_player(uid: int):
	var player: Node = players.get(uid)
	players.erase(uid)
	if is_instance_valid(player):
		player.queue_free()
