extends Node3D
## Visual hand + forearm.
##
## Built from primitive meshes (palm capsule, 4 finger capsules, thumb
## capsule, forearm capsule) so we don't need an external hand model file.
## It looks "stylized real" - fleshtone, knobbly, with a chalk-dusted palm.
##
## The hand animates based on the analog grip value:
##   - grip = 0: open hand, fingers spread
##   - grip = 1: fist / death grip, fingers curled
##   - low stamina adds a small tremor

@export var is_left: bool = false
@export var climber_path: NodePath
@export var skin_color: Color = Color(0.88, 0.72, 0.58)
@export var forearm_color: Color = Color(0.25, 0.22, 0.2)  # chalk-dusted black sleeve

var _fingers: Array[Node3D] = []
var _thumb: Node3D
var _palm: MeshInstance3D
var _forearm: MeshInstance3D
var _climber: Node
var _tremor_seed: float = 0.0


func _ready() -> void:
	_climber = get_node_or_null(climber_path)
	_tremor_seed = randf() * 10.0
	_build_hand()


func _build_hand() -> void:
	# Forearm capsule extending backward (-Z) from the hand pivot.
	_forearm = _add_capsule(self, Vector3(0.0, 0.0, -0.13), Vector3(0.04, 0.18, 0.04), forearm_color)
	_forearm.rotation.x = deg_to_rad(90.0)

	# Palm.
	_palm = _add_box(self, Vector3(0.0, 0.0, 0.0), Vector3(0.085, 0.10, 0.025), skin_color)

	# Four fingers - each a short chain of two capsules so they can curl.
	var finger_x := [-0.030, -0.010, 0.010, 0.030]
	var finger_y := 0.045
	for i in 4:
		var knuckle := Node3D.new()
		knuckle.position = Vector3(finger_x[i], finger_y, 0.0)
		add_child(knuckle)
		var proximal := _add_capsule(knuckle, Vector3(0.0, 0.018, 0.0),
			Vector3(0.011, 0.022, 0.011), skin_color)
		proximal.rotation.x = deg_to_rad(90.0)
		var tip_pivot := Node3D.new()
		tip_pivot.position = Vector3(0.0, 0.036, 0.0)
		knuckle.add_child(tip_pivot)
		var distal := _add_capsule(tip_pivot, Vector3(0.0, 0.015, 0.0),
			Vector3(0.010, 0.020, 0.010), skin_color)
		distal.rotation.x = deg_to_rad(90.0)
		_fingers.append(knuckle)

	# Thumb - one knuckle pivot, angled in.
	var thumb_pivot := Node3D.new()
	thumb_pivot.position = Vector3(-0.052, -0.005, 0.0)
	thumb_pivot.rotation.z = deg_to_rad(60.0 if is_left else -60.0)
	add_child(thumb_pivot)
	_thumb = _add_capsule(thumb_pivot, Vector3(0.0, 0.025, 0.0),
		Vector3(0.013, 0.030, 0.013), skin_color)
	_thumb.rotation.x = deg_to_rad(90.0)


func _process(delta: float) -> void:
	var grip: float = _get_grip()
	# Curl fingers toward palm based on grip.
	var curl: float = lerp(0.05, 1.2, grip)
	for knuckle in _fingers:
		knuckle.rotation.x = -curl
	# Thumb folds across.
	_thumb.parent.rotation.x = lerp(0.1, 0.7, grip)

	# Stamina tremor.
	var shake: float = 0.0
	if _climber != null:
		shake = _climber.left_shake if is_left else _climber.right_shake
	if shake > 0.01:
		var t: float = Time.get_ticks_msec() * 0.05 + _tremor_seed
		rotation = rotation.lerp(Vector3(
			sin(t) * 0.04 * shake,
			cos(t * 1.3) * 0.05 * shake,
			sin(t * 0.7) * 0.03 * shake
		), 0.4)
	else:
		rotation = rotation.lerp(Vector3.ZERO, 0.2)


func _get_grip() -> float:
	if _climber == null:
		return 0.0
	# Reach into the climber's controller for the raw analog grip value.
	var ctrl: XRController3D = _climber.left_controller if is_left else _climber.right_controller
	if ctrl == null:
		return 0.0
	return clamp(ctrl.get_float("grip"), 0.0, 1.0)


# ---- primitive helpers --------------------------------------------------

func _add_capsule(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = size.x
	cap.height = size.y * 2.0
	m.mesh = cap
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.65
	m.material_override = mat
	parent.add_child(m)
	return m


func _add_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	m.material_override = mat
	parent.add_child(m)
	return m
