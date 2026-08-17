extends StaticBody3D
class_name Hold
## A single climbing hold bolted to the wall.
##
## Holds are the only thing the player can grab. Each hold has a difficulty
## expressed as `required_grip` (0..1) - the minimum *effective* grip
## strength needed to hold on. Easy jugs are 0.2, tiny crimps 0.8+.
##
## The hold itself is purely a collider + visual mesh; all the "can I hold
## this?" logic lives here so the climber script can ask it.

@export var required_grip: float = 0.4    ## Minimum effective strength to latch.
@export var hold_color: Color = Color(0.2, 0.7, 0.35)
@export var hold_radius: float = 0.06

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _currently_held_by: StringName = &""


func _ready() -> void:
	if _mesh != null:
		_apply_color(hold_color)


func can_grab(effective_strength: float) -> bool:
	return effective_strength >= required_grip


func on_grabbed(hand: StringName) -> void:
	_currently_held_by = hand


func on_released(hand: StringName) -> void:
	if _currently_held_by == hand:
		_currently_held_by = &""


## Returns the transform the hand pivot should be at while grabbed, in world
## space. We put the hand just in front of the hold facing the wall, with a
## small downward tilt so the fingers visibly curl around the lip.
func get_grab_transform(hand_world_pos: Vector3, controller_basis: Basis) -> Transform3D:
	var xform: Transform3D = global_transform
	# Hand sits slightly in front of the hold (away from the wall = +Z local)
	var offset: Vector3 = Vector3(0.0, -0.01, hold_radius * 0.55)
	var basis: Basis = controller_basis
	# Lock roll so the palm faces the wall; keep yaw/pitch from the controller.
	var look: Vector3 = -global_basis.z.normalized()
	basis = Basis.looking_at(controller_basis.z, Vector3.UP).rotated(Vector3.RIGHT, -0.35)
	return Transform3D(basis, xform * offset)


func _apply_color(color: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.02
	# Holds in a gym are usually bright and slightly chalk-dusted.
	mat.ao_light_affect = 0.2
	if _mesh.mesh is BoxMesh or _mesh.mesh is SphereMesh or _mesh.mesh is CapsuleMesh:
		_mesh.material_override = mat
