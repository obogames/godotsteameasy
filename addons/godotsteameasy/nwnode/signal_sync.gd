@icon("res://addons/godotsteameasy/gizmo/sync.png")
class_name SignalNwNode extends Node
## Turns signals into network events (star topology: lobby owner = server).
##
## Every script signal with a single Dictionary argument on nodes [member signal_component_group] is a net signal if it contains a "_to" key.
## Clients only ever send to the server, and the server relays the event according to the "_to" key:
## - [code]"server_only"[/code]: event is sent to the server only.
## - [code]"broadcast"[/code] sends the event to all clients. Only the server can send this.
## - [code]int[/code] if emitted by clients, event is sent to the server, which then propagates to user id = "_to". If emitted by the server, then it sends the event to the "_to" user id only. 
## 
## The [code]_cm[/code] (node path relative to the current scene) and [code]_fn[/code] (signal name) are added to the packet and used internally to identify the receiving component on the other side.
## The scene must have the same layout on every peer.
##
## The receiving client node can use the [code]_frm[/code] user id to check which other client sent this event originally.
## Also on the receiving node will find that [code]_to[/code] is set to null, this is done so that the event won't be retransmitted by the Signal Syncer. 


@export_group("Component Group")
@export var enabled: bool = true
@export var verbose: bool = false
@export var signal_component_group: String = "net_signal"
## If set to true, it'll monitor net_component nodes being added and removed to the scene
@export var monitor_components: bool = true


@onready var net: INet = get_tree().get_first_node_in_group("net_core")


func _ready() -> void:
	if not enabled:
		return

	var tree = get_tree()
	if monitor_components:
		tree.node_added.connect(register_component)
		tree.node_removed.connect(unregister_component)
		#tree.node_renamed.connect(_on_net_cmp_renamed)

	for component in tree.get_nodes_in_group(signal_component_group):
		register_component(component)


func _send_signal_to_lobby(event: Dictionary, component: Node, signal_name: String):
	# TODO: message queue? send queue on a scheduled basis?
	#		game events aren't that often, even in a low-latency game like Lego Piratepoly, but idk... maybe it's worth it
	if event.get("_to") == null:
	 	# events without a "_to" are not valid net_events
		return
	elif net.is_server and is_server_only(event):
		# if the server is the emitter, it will not send the event.
		return
	elif not net.is_online:
		push_error("[Signal] error: _send_signal_to_lobby while net backend is offline!")
		return

	var _scene: String = get_tree().current_scene.name
	var _component = str(component.get_path()).trim_prefix("/root/" + _scene + "/")

	#"sc": _scene
	event["_cm"] = _component
	event["_fn"] = str(signal_name)

	if verbose:
		print("[Signal] transmitting evt: %s.%s -- %s" % [component.name, signal_name, event])

	if net.is_server:
		var send_to = event.get("_to")
		if typeof(send_to) == TYPE_INT:
			# server states that it only sends the signal to a specific client
			net.send(send_to, INet.NWC_SIGNAL_P, event)
		elif send_to == "broadcast":
			# server broadcasts to all clients
			# no need for "except" option, as server initiates the event
			net.broadcast(INet.NWC_SIGNAL_P, event)
		else:
			print("[Signal] invalid '_to' key in event: %s" % send_to)
	else:
		# if game client does not act as a server, it can only send messages to the server!
		# which then will propagate the event to "_to" User ID.
		net.send(net.lobby_info.owner.uid, INet.NWC_SIGNAL_P, event)


func _on_data_received(from: int, event: Dictionary):
	if verbose:
		print("[Signal] received event from %s: %s" % [from, event])

	if net.is_server:
		# only server can set the _frm meta: reject clients pretending to be someone else
		if event.has("_frm") and from != get_client_uid(event):
			push_error("[Signal] received packet but from != _frm (%s != %s) in event: %s" % [from, event.get("_frm"), event])
			return
		# the original sender, so that receiving clients know who sent the relayed event
		event["_frm"] = from

		# Propagate to other clients according to "_to"
		var send_to = event.get("_to")
		var ok := true
		if typeof(send_to) == TYPE_INT:
			if send_to != net.me.uid:
				ok = net.send(send_to, INet.NWC_SIGNAL_P, event)
		elif send_to == "broadcast":
			ok = net.broadcast(INet.NWC_SIGNAL_P, event, {"except": [from]})
		if !ok:
			push_error("[Signal] propagate from recv failed (uid: %d) %s" % [from, event])

	# append metadata to event
	if !event.has("_frm"):
		# "_frm" is set on the receiving side, for the local event handler to access the sender's user ID
		event["_frm"] = from
	# "_to" set to null avoids retransmission when the signal is emitted locally below
	event["_to"] = null

	# TODO: assert correct group & scene & whitelist paths (cache nodes?) with HMAC verification
	var cmp_path = event["_cm"]
	var func_name = event["_fn"]
	var node = get_tree().current_scene.get_node(cmp_path)
	var handler_ = node.get(func_name)
	handler_.emit(event)


func register_component(component: Node):
	if !component.is_in_group(signal_component_group):
		return

	var script = component.get_script()
	if script == null:
		push_error("[Signal] node in %s group has no script attached." % signal_component_group)
		return

	for sig in script.get_script_signal_list(): # component.get_signal_list
		if not is_net_signal(sig):
			continue

		print("[Signal] registered net event: %s.%s" % [component.name, sig["name"]])
		var signal_ = component.get(sig["name"])
		signal_.connect(_send_signal_to_lobby.bind(component, sig["name"]))


func unregister_component(component: Node):
	if !component.is_in_group(signal_component_group):
		return

	var script = component.get_script()
	if script == null:
		return

	for sig in script.get_script_signal_list():
		if not is_net_signal(sig):
			continue

		print("[Signal] unregistered net event: %s.%s" % [component.name, sig["name"]])
		var signal_: Signal = component.get(sig["name"])
		# connected with .bind(), so the plain method callable wouldn't match: find the bound one
		for conn in signal_.get_connections():
			var cb: Callable = conn["callable"]
			if cb.get_object() == self and cb.get_method() == &"_send_signal_to_lobby":
				signal_.disconnect(cb)

## only script signals with exactly one argument can be net signals:
## either typed as Dictionary, or untyped (e.g. `signal foo(event)`, reported as TYPE_NIL)
static func is_net_signal(sig: Dictionary) -> bool:
	var args: Array = sig["args"]
	if args.size() != 1:
		return false
	var t = args[0]["type"]
	return t == TYPE_DICTIONARY or t == TYPE_NIL

#func is_net_authority(node: Node) -> bool:
	#return node.get_meta("steam_id") == net.me.uid


static func get_client_uid(evt: Dictionary):
	# TODO: make this into a Net Utils function? or signals utils?
	var frm = evt.get("_frm")
	if frm:
		if typeof(frm) == TYPE_STRING:
			return int(frm.trim_prefix("ai:"))
		return frm
	elif Globals.net.is_server:
		return Globals.net.me.uid
	else:
		push_error("[Server] event contained no `_frm` %s" % evt)
		return -1

## determines whether event is server only. this message is sent only to the server 
static func is_server_only(evt: Dictionary):
	var to = evt.get("_to")
	if to:
		if typeof(to) == TYPE_STRING:
			return to == "server_only"
	return false
