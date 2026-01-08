@icon("res://addons/godotsteameasy/gizmo/voice.png")
class_name VoiceSyncer extends Node

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
## If enabled, sound played back to the client instead of networking
@export var loopback_enabled : bool = false
## If enabled, it uses Steam's recommended PCM rate
@export var use_optimal_sample_rate: bool = false

const DEFAULT_SAMPLE_RATE = 48000
var sample_rate: int = DEFAULT_SAMPLE_RATE

# TODO: add more modulate optinos like echo, reverb, delay...

@onready var net: INet = get_tree().get_first_node_in_group("net_core")

var _node_cache: Dictionary[String, Dictionary] = {}


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
		if not has_node("Loopback"):
			push_error("[VoiceSync] loopback voice was enabled, but VoiceSync node `%s` lacks a `LocalVoice` child!")

		$Loopback.stream.mix_rate = sample_rate
		$Loopback.play()
		_node_cache["//loopback"] = {
			"node": $Loopback,
			"playback": $Loopback.get_stream_playback(),
			"original_pitch": $Loopback.pitch_scale
		}


func _process(dt):
	# GodotSteam states that they use 8MB buffer, 
	# but they are not sure, neither is the steam docs
	# so fuck it 16 should du

	# check for voice
	var voice_data: Dictionary = Steam.getVoice()
	if voice_data['result'] == Steam.VOICE_RESULT_OK and voice_data['written']:
		var audio_node = _node_cache[str(my_speaker)]
		if my_speaker == null:
			print("[VoiceSync] Voice message has data: %s / %s, but Syncer found no node with multiplayer authority! Set the `steam_id` meta for an AudioStreamPlayer node which belongs to a player object!" % [voice_data['result'], voice_data['written']])
			return

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

	var dat = _node_cache.get(node_path)
	var audio_node = dat["node"]
	var playback: AudioStreamGeneratorPlayback = dat["playback"]

	var pitch : float = (float(sample_rate)/DEFAULT_SAMPLE_RATE) * dat["original_pitch"]
	audio_node.set_pitch_scale(pitch)

	var decompressed_voice: Dictionary = Steam.decompressVoice(buffer, sample_rate)
	if (not decompressed_voice['result'] == Steam.VOICE_RESULT_OK):
		return
	elif playback.get_frames_available() <= 0:
		return

	var local_voice_buffer = decompressed_voice['uncompressed']
	local_voice_buffer.resize(decompressed_voice['size'])
	
	for i: int in range(0, mini(playback.get_frames_available() * 2, local_voice_buffer.size()), 2):
		# Steam's audio data is represented as 16-bit single channel PCM audio, so we need to convert it to amplitudes
		# Combine the low and high bits to get full 16-bit value
		var raw_value = local_voice_buffer.decode_s16(i)
		# Convert the 16-bit integer to a float on from -1 to 1
		var amplitude: float = float(raw_value) / 32768.0
		playback.push_frame(Vector2(amplitude, amplitude))


func _prepare_packet(dat, buffer: StreamPeerBuffer):
	buffer.put_string(JSON.stringify(dat[0]))
	buffer.put_data(dat[1])


func _on_data_received(from: int, buffer: StreamPeerBuffer):
	# redistribute to other clients
	if net.is_server:
		var opts = {"except": from, "reliable": false, "format": INet.PacketFormat.FORMAT_RAW}
		if !net.broadcast(INet.NWC_VOIP_P, buffer.data_array, opts):
			push_error("[Voice] propagate from recv failed (uid: %d) %s" % [from, buffer.get_size()])
			print("###@ DON'T DISS IT LIKE MY PEOPLE WANNA")

	# deserialize packet
	var voip_sig = str_to_var(buffer.get_string())
	var voip_dat = buffer.data_array.slice(buffer.get_position())

	# Find the node
	process_voice(voip_dat, voip_sig["cm"])


func register_voice_node(audio_node: Node):
	if !audio_node.is_in_group(voice_component_group):
		return
	elif not (audio_node is AudioStreamPlayer3D or audio_node is AudioStreamPlayer2D or audio_node is AudioStreamPlayer):
		push_error("[VoiceSync] audio_node of group: `%s` must be of either type: AudioStreamPlayer/3D/2D!" % voice_component_group)
		return
	# setup playback
	audio_node.stream.mix_rate = sample_rate
	audio_node.play()

	var _path = _node_path(audio_node)
	print("[VoiceSync] registered %s node: %s (pitch: %s, sample rate: %s)" % [audio_node.get_class(), _path, audio_node.pitch_scale, sample_rate])

	if is_net_authority(audio_node):
		# Player speaking into the mike is going to be played back for other clients on this node
		print("[VoiceSync] registered multiplayer authority (steam id: %s) %s." % [audio_node.get_meta("steam_id"), _path])
		my_speaker = _path

	_node_cache[_path] = {
		"node": audio_node,
		"playback": audio_node.get_stream_playback(),
		"original_pitch": audio_node.pitch_scale,
	}

func unregister_voice_node(audio_node: Node):
	if !audio_node.is_in_group(voice_component_group):
		return

	#audio_node.stop()
	#_node_cache.erase(_node_path(audio_node))

func _node_path(node: Node) -> String:
	var scene_name = get_tree().current_scene.name
	return str(node.get_path()).trim_prefix("/root/" + scene_name + "/")

func is_net_authority(node: Node) -> bool:
	if !node.has_meta("steam_id"):
		return false
	return node.get_meta("steam_id") == net.me.uid
