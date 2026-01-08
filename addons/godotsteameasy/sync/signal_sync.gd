@icon("res://addons/godotsteameasy/gizmo/sync.png")
class_name SignalSyncer extends Node

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
		return
	elif net.is_server and is_server_only(event):
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
		else:
			# server broadcasts to all clients
			# no need for "except" option, as server initiates the event
			net.broadcast(INet.NWC_SIGNAL_P, event)
	else:
		net.send(net.lobby_info.owner.uid, INet.NWC_SIGNAL_P, event)


func _on_data_received(from: int, event: Dictionary):
	if verbose:
		print("[Signal] received event from %s: %s" % [from, event])

	if net.is_server:
		if from != get_client_uid(event):
			# only server can override the _frm meta
			push_error("[Signal] received packet but from != _frm (%s != %s) in event: " % [from, event.get("_frm")])
			print("###@ DON'T DISS IT LIKE MY PEOPLE WANNA")

		# Propagate to other clients
		if !is_server_only(event):
			event["_frm"] = from
			if !net.broadcast(INet.NWC_SIGNAL_P, event, {"except": [from]}):
				push_error("[Signal] propagate from recv failed (uid: %d) %s" % [from, event])
				print("###@ DON'T DISS IT LIKE MY PEOPLE WANNA")

	# append metadata to event
	if !event.has("_frm"):
		event["_frm"] = from
		event["_to"] = null # avoids retransmission

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
		if not sig["args"] and len(sig["args"]) == 1:
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
		if not sig["args"] and len(sig["args"]) == 1:
			continue

		print("[Signal] unregistered net event: %s.%s" % [component.name, sig["name"]])
		var signal_ = component.get(sig["name"])
		signal_.disconnect(_send_signal_to_lobby)

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

static func is_server_only(evt: Dictionary):
	var to = evt.get("_to")
	if to:
		if typeof(to) == TYPE_STRING:
			return to == "server_only"
	return false
