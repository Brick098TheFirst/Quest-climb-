extends Node3D
## Fall catcher.
##
## When GameState goes to FALLING:
##   - If at least one draw has been clipped, the player falls about twice the
##     distance from their harness to that draw (rope stretches), then swings
##     like a pendulum under it.
##   - If no draw is clipped, they fall all the way to the ground and reset.
##
## This is implemented by moving the XROrigin. The hand visuals are left
## attached to the controller so the player can flail realistically; the rope
## catches them.

@export var xr_origin: XROrigin3D
@export var climber_path: NodePath
@export var catch_stiffness: float = 55.0
@export var catch_damping: float = 8.0
@export var rope_stretch: float = 1.4   # catches ~1.4x the slack distance

var _climber: Node3D
var _velocity: Vector3 = Vector3.ZERO
var _falling: bool = false
var _caught: bool = false
var _pivot_world: Vector3
var _rope_length: float


func _ready() -> void:
	_climber = get_node_or_null(climber_path) as Node3D
	GameState.state_changed.connect(_on_state_changed)
	GameState.fell.connect(func(_d): _on_state_changed(GameState.State.FALLING))


func _on_state_changed(new_state: int) -> void:
	if new_state == GameState.State.FALLING and not _falling:
		_begin_fall()
	elif new_state != GameState.State.FALLING:
		_falling = false
		_caught = false
		_velocity = Vector3.ZERO


func _begin_fall() -> void:
	_falling = true
	_caught = false
	_velocity = Vector3.ZERO
	var draw_idx: int = GameState.last_clipped_draw
	if draw_idx < 0:
		_pivot_world = Vector3.ZERO  # ground fall
		_rope_length = 999.0
		return
	var draw: Node3D = get_tree().get_first_node_in_group("draw_%d" % draw_idx) as Node3D
	if draw == null:
		return
	_pivot_world = draw.global_position
	var harness: Vector3 = _climber.get_harness_position()
	_rope_length = harness.distance_to(_pivot_world) * rope_stretch


func _physics_process(delta: float) -> void:
	if not _falling:
		return

	var harness: Vector3 = _climber.get_harness_position()
	var origin_delta: Vector3 = Vector3.ZERO

	if _rope_length > 100.0:
		# Ground fall.
		origin_delta = Vector3(0.0, -9.81 * delta * delta, 0.0)
		_velocity.y -= 9.81 * delta
		origin_delta = _velocity * delta
	else:
		# Pendulum: gravity pulls toward pivot, rope constraint keeps distance.
		_velocity.y -= 9.81 * delta
		# Air drag.
		_velocity *= clamp(1.0 - 0.55 * delta, 0.0, 1.0)

		var from_pivot: Vector3 = harness - _pivot_world
		var dist: float = from_pivot.length()
		if dist > _rope_length:
			# Rope catches - spring back toward the pivot.
			var over: float = dist - _rope_length
			var dir: Vector3 = from_pivot / dist
			var along_vel: float = _velocity.dot(dir)
			if along_vel > 0.0:
				_velocity -= dir * along_vel  # remove outward velocity
			var spring: Vector3 = -dir * over * catch_stiffness
			var damp: Vector3 = -_velocity * catch_damping * clamp(over / 0.5, 0.0, 1.0)
			_velocity += (spring + damp) * delta
			_caught = true

		origin_delta = _velocity * delta

	xr_origin.global_position += origin_delta

	# Stop swinging at low energy.
	if _caught and _velocity.length() < 0.35:
		_velocity = _velocity.lerp(Vector3.ZERO, 0.1)
		if _velocity.length() < 0.08:
			GameState.state = GameState.State.RESTING
			# Give the player a second, then reset to ground.
			await get_tree().create_timer(2.5).timeout
			_reset_to_ground()


func _reset_to_ground() -> void:
	xr_origin.global_position = Vector3(0.0, 0.0, 1.8)
	_velocity = Vector3.ZERO
	GameState.reset()
