@icon("res://addons/godotsteameasy/gizmo/steam.png")
class_name SteamAvatarLoader extends Node

## Control Node that lists Steam profiles of players in lobby
@export var players_list: Node

@onready var lobby_user_prefab = preload("res://addons/godotsteameasy/ui/user.tscn")
@onready var net: INet = get_tree().get_first_node_in_group("net_core")

func _ready() -> void:
	if players_list == null:
		players_list = self

	Steam.avatar_loaded.connect(_loaded_Avatar)
	net.lobby_event.connect(_on_lobby_event)

	# Lobby may have been joined in a previous scene (e.g. menu -> game scene)
	if net.lobby_info != null:
		reload_all()


func _on_lobby_event(type: int, user: INet.AuthInfo, info: Dictionary):
	if user == null:
		return

	if type == INet.EVENT_JOIN:
		if user.uid == net.me.uid:
			# I joined: list everyone already in the lobby
			reload_all()
		else:
			reload_pfp(user.uid)
	elif type == INet.EVENT_LEAVE:
		if user.uid == net.me.uid:
			clear()
		else:
			remove_user(user.uid)


func _on_ping_event(_event: Variant):
	# PingNwNode connects its own handlers on lobby join, i.e. after this (scene) connection,
	# so defer until it has stored the new value in INet
	_copy_pings.call_deferred()


func _copy_pings():
	# copy pings stored in INet (LobbyInfo members' AuthInfo) into the UI
	if net.lobby_info == null:
		return
	for user in players_list.get_children():
		var member: INet.AuthInfo = net.lobby_info.members.get(user.uid)
		if member != null:
			user.set_ping(member.ping)


func clear():
	for user in players_list.get_children():
		#user.hide()
		user.queue_free()
	await get_tree().process_frame


func reload_all():
	for uid in net.lobby_info.members.keys():
		reload_pfp(uid)


func remove_user(uid: int):
	if players_list.has_node(str(uid)):
		players_list.get_node(str(uid)).queue_free()


func reload_pfp(uid: int):
	if net.lobby_info == null or not net.lobby_info.members.has(uid):
		return
	var member: INet.AuthInfo = net.lobby_info.members[uid]

	var player: Node
	if players_list.has_node(str(uid)):
		player = players_list.get_node(str(uid))
	else:
		player = lobby_user_prefab.instantiate()
		player.set_data(member)
		players_list.add_child(player)

	player.set_ping(member.ping)
	player.reload_pfp()

func _loaded_Avatar(uid: int, this_size: int, buffer: PackedByteArray):
	var steam_pfp = Image.create_from_data(this_size, this_size, false, Image.FORMAT_RGBA8, buffer)
	var texture: ImageTexture = ImageTexture.create_from_image(steam_pfp)

	if players_list.has_node(str(uid)):
		var node = players_list.get_node(str(uid))

		node.cached_pfp = texture
		node.reload_pfp()
