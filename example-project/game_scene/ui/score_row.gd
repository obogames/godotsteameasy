class_name ScoreRow extends VBoxContainer

## One scoreboard entry:
##   line 1: "username  KILLS / DEATHS"
##   line 2: streak_icon_prefab repeated N times (N = game_data.streak)

## Scene instantiated once per streak point (any Control, e.g. a TextureRect)
@export var streak_icon_prefab: PackedScene

@onready var label: Label = $Label
@onready var icons: HBoxContainer = $StreakIcons


func set_member(member: INet.AuthInfo) -> void:
	var data = member.game_data
	label.text = "%s  %d / %d" % [member.username, _stat(data, "kills"), _stat(data, "deaths")]
	_set_icon_count(_stat(data, "streak"))


func _set_icon_count(n: int) -> void:
	while icons.get_child_count() < n:
		icons.add_child(streak_icon_prefab.instantiate())
	while icons.get_child_count() > n:
		var icon := icons.get_child(icons.get_child_count() - 1)
		icons.remove_child(icon) # remove now, so the child count drops immediately
		icon.queue_free()


## game_data is a plain {} until the spawner assigns TankData; both support .get()
static func _stat(data, key: String) -> int:
	var v = data.get(key) if data != null else null
	return int(v) if v != null else 0
