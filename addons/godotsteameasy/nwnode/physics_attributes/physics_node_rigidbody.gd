class_name PhysicsRigidBody extends PhysicsTransform

@export var sync_linear_velocity: bool = true
@export var sync_angular_velocity: bool = true

@export var sync_mass: bool = false
@export var sync_inertia: bool = false

func replace_attribute_representation() -> Array[PhysicsAttribute]:
	# This is a shortcut class for adding sync ruleas for RigidBodies
	var arr: Array[PhysicsAttribute] = super.replace_attribute_representation()

	if sync_linear_velocity:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "linear_velocity"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	if sync_angular_velocity:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "angular_velocity"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	if sync_mass:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "mass"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	if sync_inertia:
		var attr = PhysicsAttribute.new()
		attr.attribute_name = "inertia"
		attr.apply_value_type = apply_value_type
		arr.append(attr)
	
	return arr
