extends Node

var cached_pfp: ImageTexture
var uid: int = -1


func set_data(player: INet.AuthInfo):
	uid = player.uid
	name = str(uid)

	var username_lbl: Label = $"MarginContainer/HBoxContainer/ScrollContainer/UsernameLbl"
	username_lbl.text = player.username


func reload_pfp():
	if cached_pfp:
		var pfp = $"MarginContainer/HBoxContainer/Avatar"
		pfp.set_texture(cached_pfp)
	else:
		Steam.getPlayerAvatar(Steam.AVATAR_MEDIUM, uid)


func set_ping(rtt: int):
	var ping_label = $MarginContainer/HBoxContainer/PingLbl
	ping_label.text = "%d ms" % rtt


func open_hud():
	if uid != -1:
		Steam.activateGameOverlayToUser("steamid", uid)
