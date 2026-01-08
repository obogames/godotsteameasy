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

func clear():
	for user in players_list.get_children():
		#user.hide()
		user.queue_free()
	await get_tree().process_frame


func _on_pong(event: Variant):
	# hook this into the Ping node's signal
	if event.has("rtts"):
		for user in players_list.get_children():
			var rtt: int = event["rtts"].get(str(user.uid), -1)
			if rtt and rtt != -1:
				user.set_ping(rtt)


func _on_ping(event: Variant):
	if not event.has("_frm") or not event.get("rtt"):
		if net.is_server:
			# client always receives its own ping
			print("[Avatars] initial ping recv ", event)
		return

	var node = players_list.get_node(str(event["_frm"]))
	node.set_ping(event["rtt"])


func reload_pfp(uid: int):
	var member: INet.AuthInfo = net.lobby_info.members[uid]

	var player: Node
	if players_list.has_node(str(uid)):
		player = players_list.get_node(str(uid))
	else:
		player = lobby_user_prefab.instantiate()
		player.set_data(member)
		players_list.add_child(player)

	player.reload_pfp()

func _loaded_Avatar(uid: int, this_size: int, buffer: PackedByteArray):
	var steam_pfp = Image.create_from_data(this_size, this_size, false, Image.FORMAT_RGBA8, buffer)
	var texture: ImageTexture = ImageTexture.create_from_image(steam_pfp)

	if players_list.has_node(str(uid)):
		var node = players_list.get_node(str(uid))

		node.cached_pfp = texture
		node.reload_pfp()
