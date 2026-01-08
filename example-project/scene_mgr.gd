class_name SceneManager
extends Node

signal fatal_error

var prev_scene: String = ""

func _init(_sd: int = 1337):
	var dirs = [
		"user://games", # online saved games
		"user://cache",
	]

	for dir in dirs:
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)

	fatal_error.connect(handle_log_fatal_error)


func on_fatal_error(err: String, ctx=null):
	call_deferred("handle_log_fatal_error", err, ctx)


func handle_log_fatal_error(err, ctx=null):
	print(err)
	push_error(err)

	var parent = get_tree().root
	for child in parent.get_children():
		if child != self:
			child.queue_free()

	var diag := AcceptDialog.new()
	diag.dialog_text = err
	diag.connect("confirmed", fatal_error_diag_ok)
	add_child(diag)
	diag.popup_centered()

func fatal_error_diag_ok():
	var tree = get_tree()
	if tree != null:
		tree.quit()


func change_scene(scene_path: String, follow_history = true) -> void:
	if not scene_path:
		return

	call_deferred("_request_scene_change", scene_path, follow_history)


func _request_scene_change(scene_path: String, follow_history):
	# store prev scene
	var tree = get_tree()
	if follow_history and tree.current_scene != null:
		prev_scene = tree.current_scene.scene_file_path.trim_prefix("res://").trim_suffix(".tscn")

	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	var err = tree.change_scene_to_file(scene_path)

	if err != OK:
		print("[GameManager] Error loading %s: %s " % [scene_path, err])
