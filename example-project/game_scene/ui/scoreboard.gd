class_name Scoreboard extends VBoxContainer

## Lists every lobby member's game_data using row_prefab (one row per player).
## Polls the lobby, so it needs no hooks in the player/tank code.

## Scene with a `set_member(member: INet.AuthInfo)` function, e.g. score_row.tscn
@export var row_prefab: PackedScene
@export var refresh_interval: float = 0.2

## Row nodes, keyed by Steam uid
var _rows: Dictionary = {}
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	if _time < refresh_interval:
		return
	_time = 0.0
	_refresh()


func _refresh() -> void:
	var lobby: INet.LobbyInfo = Globals.net.lobby_info
	var members: Dictionary = lobby.members if lobby != null else {}

	# players who left
	for uid in _rows.keys():
		if not members.has(uid):
			_rows[uid].queue_free()
			_rows.erase(uid)

	# new + existing players
	for uid in members:
		var row: Node = _rows.get(uid)
		if row == null:
			row = row_prefab.instantiate()
			add_child(row)
			_rows[uid] = row
		row.set_member(members[uid])
