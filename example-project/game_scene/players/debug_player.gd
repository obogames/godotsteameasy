extends PlayerObject

@export var steam_id: String


func _ready() -> void:
	super._ready()
	set_meta("steam_id", int(steam_id))

	var member: INet.AuthInfo
	for m in Globals.net.lobby_info.members.values():
		if m.uid == steam_id:
			member = m
			break

	self.set_data(member)
