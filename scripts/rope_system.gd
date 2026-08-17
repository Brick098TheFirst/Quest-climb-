extends Node3D
class_name RopeSystem
## Verlet rope system.
##
## The rope is a chain of N particles connected by distance constraints.
## Particles:
##   - the first is the "harness" end - it follows the climber's waist
##   - the last is the "belayer" end - pinned to the ground near the wall
##   - when the rope is clipped through a quickdraw, the corresponding particle
##     is pinned to the draw's carabiner position
##
## Rope rendering is done by pushing particle positions into an ImmediateMesh
## (or a tube mesh) every frame. The rope can be grabbed by the player's free
## hand - grabbing it pulls slack, which is what you need in order to clip.
##
## This is intentionally a cheap verlet integrator - no rigid bodies, no
## joints - so it holds up at 90 Hz on Quest 2.

const NUM_PARTICLES := 42
const SEGMENT_LENGTH := 0.35  # meters
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const DAMPING := 0.985
const CONSTRAINT_ITERS := 6

# Where the fake belayer is anchored - behind/under the climber at ground level,
# in WORLD coordinates (the RopeSystem node stays at the origin).
@export var belayer_anchor: Vector3 = Vector3(-0.5, 0.1, 1.6)

# Extra slack the player has pulled up for clipping, in meters.
@export var extra_slack_for_clip: float = 0.0

# How much rope the belayer has paid out in total (0 = no rope out).
var paid_out_m: float = 0.0

var _positions: Array[Vector3] = []
var _prev_positions: Array[Vector3] = []
var _pinned: Array[bool] = []
var _pin_world: Array[Vector3] = []

# Index of the particle currently routed through each draw.  -1 if not clipped.
var draw_particle_index: Array[int] = [-1, -1, -1, -1, -1, -1]

# The rope MeshInstance - rebuilt from a SurfaceTool every time the particle
# count changes (which is once at start). Each frame we just push new vertex
# positions into the existing arrays so it stays cheap.
@onready var _rope_mesh: MeshInstance3D = $RopeMesh
var _array_mesh: ArrayMesh
var _mat: StandardMaterial3D
const ROPE_RADIUS := 0.008
const ROPE_RADIAL_SEGMENTS := 5

# Reference to the climber for following the harness.
@export var climber: NodePath
var _climber: Node3D

# True once the player has grabbed the rope with a free hand. The grabbed
# particle follows that hand while held.
var grabbed_particle: int = -1
var grabbed_by_hand: StringName = &""


func _ready() -> void:
	_climber = get_node_or_null(climber) as Node3D
	_mat = _rope_mesh.material_override as StandardMaterial3D
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.95, 0.83, 0.45)
		_mat.roughness = 0.9
	_build_rope()
	_build_rope_mesh()


func _build_rope() -> void:
	_positions.clear()
	_prev_positions.clear()
	_pinned.clear()
	_pin_world.clear()
	for i in NUM_PARTICLES:
		var t: float = float(i) / float(NUM_PARTICLES - 1)
		var p: Vector3 = belayer_anchor.lerp(_harness_position(), t)
		_positions.append(p)
		_prev_positions.append(p)
		_pinned.append(false)
		_pin_world.append(p)
	# Pin the belayer end.
	_pinned[NUM_PARTICLES - 1] = true
	_pin_world[NUM_PARTICLES - 1] = belayer_anchor


func _physics_process(delta: float) -> void:
	_update_pins()
	_integrate(delta)
	for i in CONSTRAINT_ITERS:
		_constrain_segments()
		_constrain_particles_to_draws()
	_update_mesh()


func _integrate(delta: float) -> void:
	for i in NUM_PARTICLES:
		if _pinned[i]:
			_positions[i] = _pin_world[i]
			continue
		if i == grabbed_particle:
			continue  # hand controls this one directly
		var velocity: Vector3 = (_positions[i] - _prev_positions[i]) * DAMPING
		_prev_positions[i] = _positions[i]
		_positions[i] += velocity + GRAVITY * delta * delta


func _constrain_segments() -> void:
	for i in NUM_PARTICLES - 1:
		var a: Vector3 = _positions[i]
		var b: Vector3 = _positions[i + 1]
		var delta: Vector3 = b - a
		var dist: float = delta.length()
		if dist < 0.0001:
			continue
		var diff: float = (dist - SEGMENT_LENGTH) / dist
		var correction: Vector3 = delta * 0.5 * diff
		if not _pinned[i] and i != grabbed_particle:
			_positions[i] += correction
		if not _pinned[i + 1] and i + 1 != grabbed_particle:
			_positions[i + 1] -= correction


func _constrain_particles_to_draws() -> void:
	for draw_idx in draw_particle_index.size():
		var pidx: int = draw_particle_index[draw_idx]
		if pidx >= 0:
			# Snap the routed particle to the carabiner world position. The
			# draw node is located via the RoutedDraw group.
			var draw: Node3D = get_tree().get_first_node_in_group("draw_%d" % draw_idx) as Node3D
			if draw != null:
				_positions[pidx] = draw.global_position


func _update_pins() -> void:
	# First particle follows the harness.
	_positions[0] = _harness_position()
	_pinned[0] = true
	_pin_world[0] = _positions[0]
	# Belayer end stays put.
	_pinned[NUM_PARTICLES - 1] = true
	_pin_world[NUM_PARTICLES - 1] = belayer_anchor


func _harness_position() -> Vector3:
	if _climber != null and _climber.has_method("get_harness_position"):
		return _climber.get_harness_position()
	return global_position


func _update_mesh() -> void:
	if _array_mesh == null or _positions.size() < 2:
		return
	# Push new positions into the existing vertex array without rebuilding
	# the topology. Each segment has a ring of ROPE_RADIAL_SEGMENTS verts.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in _positions.size():
		var p: Vector3 = _positions[i]
		# Build a frame: tangent along the rope, normal and binormal
		# perpendicular. Vertices around the ring use these to offset.
		var tangent: Vector3
		if i == 0:
			tangent = (_positions[1] - p).normalized()
		elif i == _positions.size() - 1:
			tangent = (p - _positions[i - 1]).normalized()
		else:
			tangent = (_positions[i + 1] - _positions[i - 1]).normalized()
		var normal: Vector3
		if abs(tangent.dot(Vector3.UP)) > 0.95:
			normal = tangent.cross(Vector3.RIGHT).normalized()
		else:
			normal = tangent.cross(Vector3.UP).normalized()
		var binormal: Vector3 = tangent.cross(normal).normalized()
		for s in ROPE_RADIAL_SEGMENTS:
			var ang: float = TAU * float(s) / float(ROPE_RADIAL_SEGMENTS)
			var off: Vector3 = (normal * cos(ang) + binormal * sin(ang)) * ROPE_RADIUS
			verts.append(p + off)
			uvs.append(Vector2(float(s) / float(ROPE_RADIAL_SEGMENTS),
				float(i) / float(_positions.size() - 1)))
	_array_mesh.surface_update_vertex_region(0, 0, verts.to_byte_array())


func _build_rope_mesh() -> void:
	# Build the tube topology once (indices + UVs + a placeholder vertex
	# array); positions are refreshed every frame in _update_mesh.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in NUM_PARTICLES:
		for s in ROPE_RADIAL_SEGMENTS:
			verts.append(_positions[i])
			normals.append(Vector3(0, 1, 0))
			uvs.append(Vector2(float(s) / float(ROPE_RADIAL_SEGMENTS),
				float(i) / float(NUM_PARTICLES - 1)))
	for i in NUM_PARTICLES - 1:
		for s in ROPE_RADIAL_SEGMENTS:
			var s2: int = (s + 1) % ROPE_RADIAL_SEGMENTS
			var a: int = i * ROPE_RADIAL_SEGMENTS + s
			var b: int = i * ROPE_RADIAL_SEGMENTS + s2
			var c: int = (i + 1) * ROPE_RADIAL_SEGMENTS + s2
			var d: int = (i + 1) * ROPE_RADIAL_SEGMENTS + s
			indices.append_array([a, d, b, b, d, c])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	_array_mesh = ArrayMesh.new()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_rope_mesh.mesh = _array_mesh
	_rope_mesh.material_override = _mat


# ---------------------------------------------------------------------------
# Public API

## Route the rope through the given draw. Called by Quickdraw when the player
## successfully clips.
func clip_to_draw(draw_index: int, draw_node: Node3D) -> void:
	# Find the particle closest to the carabiner that's between the harness
	# and the next free draw.
	var target: Vector3 = draw_node.global_position
	var best_idx: int = 0
	var best_dist: float = INF
	for i in range(1, NUM_PARTICLES - 1):
		var d: float = _positions[i].distance_to(target)
		if d < best_dist:
			best_dist = d
			best_idx = i
	draw_particle_index[draw_index] = best_idx
	_pinned[best_idx] = true
	_pin_world[best_idx] = target
	GameState.last_clipped_draw = max(GameState.last_clipped_draw, draw_index)
	GameState.clipped_to_draw.emit(draw_index)


func release_grab() -> void:
	grabbed_particle = -1
	grabbed_by_hand = &""


## Returns the world position of the rope at the given particle index, or
## the closest point to `from_pos` if idx is -1.
func get_closest_particle(from_pos: Vector3) -> int:
	var best_idx: int = -1
	var best_dist: float = 0.09  # must be within 9cm to grab
	for i in range(2, NUM_PARTICLES - 2):
		if _pinned[i]:
			continue
		var d: float = _positions[i].distance_to(from_pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func get_particle_position(idx: int) -> Vector3:
	if idx < 0 or idx >= _positions.size():
		return Vector3.ZERO
	return _positions[idx]


func set_grabbed_particle(idx: int, hand: StringName) -> void:
	grabbed_particle = idx
	grabbed_by_hand = hand


func set_grabbed_position(world_pos: Vector3) -> void:
	if grabbed_particle >= 0 and grabbed_particle < _positions.size():
		_prev_positions[grabbed_particle] = _positions[grabbed_particle]
		_positions[grabbed_particle] = world_pos


func get_particle_velocity(idx: int) -> Vector3:
	if idx < 0 or idx >= _positions.size():
		return Vector3.ZERO
	return _positions[idx] - _prev_positions[idx]
