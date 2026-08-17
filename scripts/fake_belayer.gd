extends Node3D
## Invisible fake belayer / leader.
##
## There's no belayer avatar - this node only manages the rope "pay-out" logic.
## It acts like a real belayer who's a little slow: it feeds rope when the
## climber is above the last clipped draw, takes in slack when the climber
## moves down, and *locks off* (pays no more rope) when the climber falls.
##
## The rope system itself uses verlet physics; this script just nudges the
## total paid-out length and tells GameState about it. The verlet rope's
## segment count is fixed, but the pinned "belayer anchor" position can be
## moved to give or take slack without changing the particle count.

@export var climber_path: NodePath
@export var rope_path: NodePath
@export var pay_rate: float = 1.6      # m/s - how fast slack is fed
@export var take_rate: float = 2.2     # m/s - how fast slack is taken in
@export var fall_lock_window: float = 0.18  # seconds of downward velocity before lock-off

var _climber: Node3D
var _rope: RopeSystem
var _base_anchor: Vector3
var _fall_velocity_y: float = 0.0
var _fall_time: float = 0.0
var _locked: bool = false
var _prev_harness_y: float = 0.0
var _have_prev: bool = false


func _ready() -> void:
	_climber = get_node_or_null(climber_path) as Node3D
	_rope = get_node_or_null(rope_path) as RopeSystem
	_base_anchor = global_position
	GameState.state_changed.connect(_on_state_changed)


func _on_state_changed(new_state: int) -> void:
	if new_state == GameState.State.ON_GROUND:
		_locked = false
		_fall_time = 0.0


func _physics_process(delta: float) -> void:
	if _climber == null or _rope == null:
		return

	var harness: Vector3 = _climber.get_harness_position() if _climber.has_method("get_harness_position") else _climber.global_position
	var last_draw_world: Vector3 = _get_last_draw_position()

	# Distance from harness down to the last clipped draw (or ground if none).
	var fall_distance: float
	if last_draw_world == Vector3.INF:
		fall_distance = harness.y - _base_anchor.y
	else:
		fall_distance = harness.y - last_draw_world.y

	# Track vertical velocity to detect falls.
	if _have_prev:
		var v_y: float = (harness.y - _prev_harness_y) / max(delta, 0.001)
		_fall_velocity_y = lerp(_fall_velocity_y, v_y, 0.4)
	_prev_harness_y = harness.y
	_have_prev = true

	if _fall_velocity_y < -1.2 and not _locked:
		_fall_time += delta
		if _fall_time > fall_lock_window:
			_locked = true
	elif _fall_velocity_y > 0.4:
		_fall_time = 0.0
		_locked = false

	# Move the belayer anchor to simulate slack pay-out / take-in.
	var target_anchor: Vector3 = _base_anchor
	if _locked:
		# No more rope out - anchor holds firm.
		pass
	else:
		# Anchor rises toward the last draw as slack is taken in, drops away
		# as slack is paid out. We move it slowly to simulate belayer lag.
		var direction: float = 1.0 if fall_distance > 0.6 else -1.0
		# Cap how far the anchor can move so the rope doesn't stretch absurdly.
		var max_offset: float = clamp(fall_distance * 0.6, -1.0, 3.0)
		target_anchor.y = _base_anchor.y + max_offset * direction
	# Smoothly nudge the rope's pinned belayer point.
	_rope.belayer_anchor = _rope.belayer_anchor.lerp(
		Vector3(_base_anchor.x, target_anchor.y, _base_anchor.z),
		delta * 3.0
	)


func _get_last_draw_position() -> Vector3:
	var idx: int = GameState.last_clipped_draw
	if idx < 0:
		return Vector3.INF
	var draw: Node3D = get_tree().get_first_node_in_group("draw_%d" % idx) as Node3D
	if draw == null:
		return Vector3.INF
	return draw.global_position
