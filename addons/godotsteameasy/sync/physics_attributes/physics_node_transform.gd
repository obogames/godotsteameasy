class_name PhysicsTransform extends PhysicsNodeType

@export var sync_position: bool = true
@export var sync_rotation: bool = true
@export var sync_scale: bool = true

func replace_attribute_representation() -> Array[PhysicsAttribute]:
	# This is a shortcut class for adding sync ruleas for RigidBodies
	var arr: Array[PhysicsAttribute] = []

	if sync_position:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "position"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	if sync_rotation:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "rotation"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	if sync_scale:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "scale"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
		
	return arr
