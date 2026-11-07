@icon("res://addons/godotsteameasy/gizmo/voice_speaker.png")
class_name VoiceSpeaker extends NetAuthority
## Voice playback node for VoiceNwNode. Attach it to an AudioStreamPlayer, AudioStreamPlayer2D or
## AudioStreamPlayer3D that has an AudioStreamGenerator stream.
##
## It also detects when its player is talking: VoiceNwNode calls [method _on_voice_packet] for every
## voice packet that belongs to this node (packets received from the network, and the local
## player's own recorded voice). Steam stops sending packets while the player is silent, so
## "talking" ends after [member release_time] without packets.
##
## On every change it emits [signal speaking_changed] and calls [code]toggle_ui(is_on: bool)[/code]
## on [member ui_node].

## Group VoiceNwNode looks for (its default `voice_component_group`)
const VOICE_GROUP := &"net_voice"

## Emitted when the player starts (true) or stops (false) talking
signal speaking_changed(is_speaking: bool)

## Node with a `toggle_ui(is_on: bool)` method, called when the player starts / stops talking
@export var ui_node: Node

@export_group("Voice Activity")
## Seconds without a voice packet before the player counts as silent.
## Voice packets are unreliable and bursty: too low and the UI flickers mid-sentence.
@export var release_time: float = 0.3
## Packets quieter than this (RMS, 0..1) don't count as speech. 0 = every packet counts.
## Typical speech is around 0.02 - 0.2.
@export_range(0.0, 1.0, 0.001) var level_threshold: float = 0.0
## How fast [member level] falls back to 0 (per second), for meters / pulsing icons
@export var level_decay: float = 3.0

## Read-only: whether the player is currently talking
var is_speaking: bool = false
## Read-only: voice level 0..1 (peak-hold with decay)
var level: float = 0.0

## Set up by VoiceNwNode via setup_playback()
var playback: AudioStreamGeneratorPlayback
## pitch_scale before VoiceNwNode adjusted it for the sample rate
var original_pitch: float = 1.0
## Whether ui_node has a `toggle_ui` method
var has_ui_toggle: bool = false

## `self` as an untyped value: this script extends Node, so the audio player API
## (play, stream, pitch_scale...) is only reachable dynamically
var _sampler = self
var _last_packet_ms: int = 0
var _pitch_saved: bool = false


func _init() -> void:
	# VoiceNwNode registers nodes on SceneTree.node_added, which fires before _ready:
	# the group has to be there before the node enters the tree
	add_to_group(VOICE_GROUP)


func _enter_tree() -> void:
	# exports are already assigned here, and this runs before VoiceNwNode's node_added registration
	has_ui_toggle = ui_node != null and ui_node.has_method(&"toggle_ui")


func _ready() -> void:
	set_process(false)

	if not is_sampler(self):
		push_error("[VoiceSpeaker] %s must be attached to an AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D, not %s!" % [get_path(), get_class()])
		return
	if ui_node != null and not has_ui_toggle:
		push_error("[VoiceSpeaker] %s: ui_node %s has no `toggle_ui(is_on: bool)` method!" % [get_path(), ui_node.get_path()])


static func is_sampler(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


## Called by VoiceNwNode on registration: starts the generator stream at the given sample rate.
## Returns false if this node can't be used as a voice speaker.
func setup_playback(mix_rate: int) -> bool:
	if not is_sampler(self):
		push_error("[VoiceSpeaker] %s is not an AudioStreamPlayer/2D/3D, can't play voice!" % get_path())
		return false
	if not _sampler.stream is AudioStreamGenerator:
		push_error("[VoiceSpeaker] %s needs an AudioStreamGenerator stream!" % get_path())
		return false

	if not _pitch_saved:
		# only the first time: later calls would read back our own sample-rate adjusted pitch
		original_pitch = _sampler.pitch_scale
		_pitch_saved = true

	_sampler.stream.mix_rate = mix_rate
	_sampler.play()
	playback = _sampler.get_stream_playback()
	return true


## Compensates the pitch when the voice's sample rate differs from the default one
func apply_sample_rate(sample_rate: int, default_rate: int) -> void:
	_sampler.pitch_scale = (float(sample_rate) / default_rate) * original_pitch


## Called by VoiceNwNode for every voice packet routed to this node.
## packet_level: RMS loudness of the packet (0..1), or 1.0 if unknown (own voice is still compressed)
func _on_voice_packet(packet_level: float = 1.0) -> void:
	level = max(level, packet_level)
	set_process(true) # also lets the level meter decay

	if packet_level < level_threshold:
		# background noise that got past Steam's silence detection
		return

	_last_packet_ms = Time.get_ticks_msec()
	if not is_speaking:
		_set_speaking(true)


func _process(delta: float) -> void:
	level = move_toward(level, 0.0, level_decay * delta)

	if is_speaking and Time.get_ticks_msec() - _last_packet_ms > int(release_time * 1000.0):
		_set_speaking(false)

	if not is_speaking and level <= 0.0:
		set_process(false)


func _exit_tree() -> void:
	# player left / despawned / scene changed mid-sentence: don't leave the UI stuck on
	if is_speaking:
		_set_speaking(false)
	level = 0.0


func _set_speaking(on: bool) -> void:
	if is_speaking == on:
		return
	is_speaking = on
	speaking_changed.emit(on)
	if has_ui_toggle and is_instance_valid(ui_node):
		ui_node.toggle_ui(on)
