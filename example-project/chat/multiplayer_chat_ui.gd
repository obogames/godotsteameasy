extends Control
class_name MultiplayerChatUI

@onready var message: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Message
@onready var send: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Send
@onready var chat: TextEdit = $Panel/MarginContainer/VBoxContainer/Chat

## Net signal (relayed by SignalNwNode, this node is in the "net_signal" group)
signal message_sent(evt: Dictionary)


func _ready():
	send.pressed.connect(_on_send_pressed)
	message.text_submitted.connect(_on_text_submitted)
	clear_chat()
	#hide()

	set_process_input(true)

	# fires both for our own messages (local emit) and for remote ones (emitted by SignalNwNode)
	message_sent.connect(_on_recv_message)

func _input(event):
	# clicking anywhere outside the chat panel (e.g. on the game world) leaves the chat,
	# so the keyboard goes back to controlling the tank
	if event is InputEventMouseButton and event.pressed and message.has_focus():
		if not $Panel.get_global_rect().has_point(event.position):
			message.release_focus()
		return

	# while typing, Enter is handled by the LineEdit (text_submitted), don't toggle the chat here,
	# otherwise the event gets consumed and the message is never submitted
	if visible and message.has_focus():
		return
	if event.is_action_pressed("enter"):
		toggle_chat()


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
	if text.strip_edges().is_empty():
		hide()
		message.release_focus()
		return
	_send_message(text)

func _on_send_pressed():
	_send_message(message.text)

func _send_message(text: String):
	text = text.strip_edges()
	if text.is_empty():
		return

	message_sent.emit({
		"_to": "broadcast",
		"text": text
	})

	message.text = ""
	message.grab_focus()

func _on_recv_message(evt: Dictionary):
	# "_frm" is only present on events received from the network; locally emitted ones are ours
	var username: String = Globals.net.uname(evt.get("_frm", true))
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
