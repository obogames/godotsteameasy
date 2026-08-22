extends Control
class_name MultiplayerChatUI

@onready var message: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Message
@onready var send: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Send
@onready var chat: TextEdit = $Panel/MarginContainer/VBoxContainer/Chat

signal message_sent(evt: Dictionary)


func _ready():
	send.pressed.connect(_on_send_pressed)
	message.text_submitted.connect(_on_text_submitted)
	clear_chat()
	#hide()

	set_process_input(true)
	
	message_sent.connect(_on_recv_message)

func _input(event):
	if event.is_action_pressed("enter"):
		toggle_chat()
	elif visible and message.has_focus():
		if event is InputEventKey and event.keycode == KEY_ENTER and event.pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()


func toggle_chat():
	if !visible:
		show()
		await get_tree().process_frame
		message.grab_focus()
	else:
		hide()
		message.text = ""
		get_viewport().set_input_as_handled()

func _on_text_submitted(text: String):
	if text == "":
		hide()
		return

	message_sent.emit({
		"text": text
	})

	message.text = ""
	message.grab_focus()

func _on_send_pressed():
	var text = message.text.strip_edges()
	if text.is_empty():
		return

	message_sent.emit({
		"text": text
	})

	message.text = ""
	message.grab_focus()

func _on_recv_message(evt: Dictionary):
	print("@@@ Chat ", evt)
	var username: String = "username"
	var time = Time.get_time_string_from_system()
	chat.text += "[%s] %s: %s\n" % [time, username, evt["text"]]
	chat.scroll_vertical = chat.get_line_count()
	_limit_chat_history()

func _limit_chat_history():
	var lines = chat.text.split("\n")
	if lines.size() > 100:
		var start_index = lines.size() - 100
		chat.text = "\n".join(lines.slice(start_index))

func clear_chat():
	chat.text = ""
