class_name NetAuthority extends Node


var username: String:
	get:
		return get_meta("username", null)


func set_data(info: INet.AuthInfo):
	# Set multiplayer authority, this function should normally be called before _ready!
	# and change the node depending the authority (other players VS my client's player node)

	set_meta("steam_id", info.uid)
	set_meta("username", info.username)
	#var my_player = (info.uid == Globals.net.me.uid)
	# Set node name
	#var uidstr = str(info.uid)
	#name = "%s#%s" % [info.username, uidstr.substr(len(uidstr)-4)]
