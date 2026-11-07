@icon("res://addons/godotsteameasy/gizmo/voice.png")
class_name VoiceNwNode extends Node

## If set to true, it'll monitor net_component nodes being added and removed to the scene
@export_group("Component Group")
@export var enabled: bool = true
@export var verbose: bool = false
@export var voice_component_group: String = "net_voice"
@export var monitor_components: bool = true

## The AudioStreamPlayer node, from which your player sends VOIP packets. Player spawner can automatically set its authority
@export var my_speaker: NodePath

@export_group("Push to Talk")
@export var push_to_talk: bool = false
@export var voice_key : String = "push_to_talk"

@export_group("Playback")
## (local debugging) If enabled, sound played back to the client instead of networking
@export var loopback_enabled : bool = false
## If enabled, it uses Steam's recommended PCM rate
@export var use_optimal_sample_rate: bool = false

const DEFAULT_SAMPLE_RATE = 48000
var sample_rate: int = DEFAULT_SAMPLE_RATE

# TODO: add more modulate optinos like echo, reverb, delay...

@onready var net: INet = get_tree().get_first_node_in_group("net_core")

## Registered speakers, keyed by node path relative to the current scene ("//loopback" for the loopback)
var _node_cache: Dictionary[String, Node] = {}


func _ready() -> void:
	if not enabled:
		return
	var tree = get_tree()

	if monitor_components:
		tree.node_added.connect(register_voice_node)
		tree.node_removed.connect(unregister_voice_node)
		#tree.node_renamed.connect(_on_net_cmp_renamed)

	for node in tree.get_nodes_in_group(voice_component_group):
		register_voice_node(node)

	# Start recording
	if push_to_talk:
		Steam.setInGameVoiceSpeaking(net.me.uid, false)
		Steam.stopVoiceRecording()
		set_process_input(true)
	else:
		Steam.setInGameVoiceSpeaking(net.me.uid, true)
		Steam.startVoiceRecording()
		set_process_input(false)

	if !loopback_enabled:
		if has_node("Loopback"):
			$Loopback.queue_free()
	else:
		# Debug voice through looping the voice back to the speaker
		var loopback = get_node_or_null("Loopback")
		if not loopback is VoiceSpeaker:
			push_error("[VoiceNwNode] loopback voice was enabled, but VoiceNwNode node `%s` lacks a `Loopback` child with a VoiceSpeaker script!" % name)
		elif loopback.setup_playback(sample_rate):
			_node_cache["//loopback"] = loopback


func _process(dt):
	# GodotSteam states that they use 8MB buffer, 
	# but they are not sure, neither is the steam docs
	# so fuck it 16 should du

	# check for voice
	var voice_data: Dictionary = Steam.getVoice()
	if voice_data['result'] == Steam.VOICE_RESULT_OK:# and voice_data['written']:
		var speaker = _node_cache.get(str(my_speaker))
		if my_speaker.is_empty() or not is_instance_valid(speaker):
			print("[VoiceNwNode] Voice message has data: %s / %s, but Syncer found no node with multiplayer authority! Set the `steam_id` meta for an AudioStreamPlayer node which belongs to a player object!" % [voice_data['result'], voice_data['written']])
			return

		# own voice never comes back from the network: tell our own speaker directly.
		# the buffer is still compressed here, so the level is unknown (1.0)
		speaker._on_voice_packet(1.0)

		# If loopback is enable, play it back at this point
		if !loopback_enabled:
			#"sc": _scene,
			#"uid": net.me.uid,
			net.broadcast_to_peers(
				INet.NWC_VOIP_P,
				[{"cm": my_speaker}, voice_data["buffer"]], 
				{"reliable": false, "format": INet.PacketFormat.FORMAT_RAW, "prepare_packet": _prepare_packet}
			)
		else:
			process_voice(voice_data["buffer"], "//loopback")

	if push_to_talk:
		if Input.is_action_pressed(voice_key):
			Steam.setInGameVoiceSpeaking(net.me.uid, true)
			Steam.startVoiceRecording()

		if Input.is_action_just_released(voice_key):
			Steam.setInGameVoiceSpeaking(net.me.uid, false)
			Steam.stopVoiceRecording()


func process_voice(buffer: PackedByteArray, node_path: String):
	# SpaceWar uses 11000 for sample rate?!
	# If are using Steam's "optimal" rate, set it; otherwise we default to 48000
	if use_optimal_sample_rate:
		sample_rate = Steam.getVoiceOptimalSampleRate()
	else:
		sample_rate = DEFAULT_SAMPLE_RATE

	var speaker = _node_cache.get(node_path)
	if not is_instance_valid(speaker):
		if verbose:
			print("[VoiceNwNode] voice packet for unknown speaker: %s" % node_path)
		return

	speaker.apply_sample_rate(sample_rate, DEFAULT_SAMPLE_RATE)

	var decompressed_voice: Dictionary = Steam.decompressVoice(buffer, sample_rate)
	if (not decompressed_voice['result'] == Steam.VOICE_RESULT_OK):
		return

	var local_voice_buffer = decompressed_voice['uncompressed']
	local_voice_buffer.resize(decompressed_voice['size'])

	# push as many frames as fit, but measure the loudness over the whole packet:
	# a full playback buffer must not make the speaker look silent
	var playback: AudioStreamGeneratorPlayback = speaker.playback
	var frames_free: int = playback.get_frames_available()
	var sum_sq := 0.0
	var n := 0
	for i: int in range(0, local_voice_buffer.size() - 1, 2):
		# Steam's audio data is represented as 16-bit single channel PCM audio, so we need to convert it to amplitudes
		# Combine the low and high bits to get full 16-bit value
		var raw_value = local_voice_buffer.decode_s16(i)
		# Convert the 16-bit integer to a float on from -1 to 1
		var amplitude: float = float(raw_value) / 32768.0
		if n < frames_free:
			playback.push_frame(Vector2(amplitude, amplitude))
		sum_sq += amplitude * amplitude
		n += 1

	# voice activity: the speaker decides when talking starts / stops and updates its UI
	speaker._on_voice_packet(sqrt(sum_sq / n) if n > 0 else 0.0)


func _prepare_packet(dat, buffer: StreamPeerBuffer):
	buffer.put_string(JSON.stringify(dat[0]))
	buffer.put_data(dat[1])


func _on_data_received(from: int, buffer: StreamPeerBuffer):
	# redistribute to other clients
	if net.is_server:
		var opts = {"except": from, "reliable": false, "format": INet.PacketFormat.FORMAT_RAW}
		if !net.broadcast(INet.NWC_VOIP_P, buffer.data_array, opts):
			push_error("[Voice] propagate from recv failed (uid: %d) %s \n###@" % [from, buffer.get_size()])

	# deserialize packet
	var voip_sig = str_to_var(buffer.get_string())
	var voip_dat = buffer.data_array.slice(buffer.get_position())

	# Find the node
	process_voice(voip_dat, voip_sig["cm"])


func register_voice_node(audio_node: Node):
	if !audio_node.is_in_group(voice_component_group):
		return
	elif not audio_node is VoiceSpeaker:
		push_error("[VoiceNwNode] node %s in group `%s` needs the VoiceSpeaker script (on an AudioStreamPlayer/2D/3D)!" % [audio_node.get_path(), voice_component_group])
		return
	# setup playback
	if not audio_node.setup_playback(sample_rate):
		return

	var _path = _node_path(audio_node)
	print("[VoiceNwNode] registered %s node: %s (pitch: %s, sample rate: %s)" % [audio_node.get_class(), _path, audio_node.pitch_scale, sample_rate])

	if is_net_authority(audio_node):
		# Player speaking into the mike is going to be played back for other clients on this node
		print("[VoiceNwNode] registered multiplayer authority (steam id: %s) %s." % [audio_node.get_meta("steam_id"), _path])
		my_speaker = _path

	_node_cache[_path] = audio_node

func unregister_voice_node(audio_node: Node):
	if !audio_node.is_in_group(voice_component_group):
		return

	# only erase if this exact node is cached there (a new node may have taken over the same path)
	var _path = _node_path(audio_node)
	if _node_cache.get(_path) == audio_node:
		_node_cache.erase(_path)

func _node_path(node: Node) -> String:
	var scene = get_tree().current_scene
	if scene == null:
		# during a scene change
		return str(node.get_path())
	return str(node.get_path()).trim_prefix("/root/" + scene.name + "/")

func is_net_authority(node: Node) -> bool:
	if !node.has_meta("steam_id"):
		return false
	return node.get_meta("steam_id") == net.me.uid
