class_name PhysicsAttribute extends Resource

enum ApplyValueType {SNAP, DAMP, INTERPOLATE_LINEAR, INTERPOLATE_ANGLE, INTERPOLATE_SLERP}

@export var attribute_name: String
@export var apply_value_type: ApplyValueType = ApplyValueType.DAMP
@export var damp_value: float = 0.1

# Last value sent across the network
var last_sent_value = null
