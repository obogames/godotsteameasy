extends Node

# Child nodes
@onready var SceneMgr: SceneManager = $SceneManager

@onready var net: INet = $Net
@onready var steam: SteamManager = $Net/Steam


func _ready():
	if get_tree().current_scene and get_tree().current_scene.name == "Global":
		push_error("[Global] You can't start the Global scene!!!!!!")
		get_tree().call_deferred("quit")
