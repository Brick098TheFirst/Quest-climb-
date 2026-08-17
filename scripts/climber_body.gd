extends Node3D
## Climber body rig.
##
## Owns the two XRController3D hands, the forearm meshes, and the logic that
## lets hands grab holds. When a hand is grabbed, its visual hand mesh is
## detached from the controller and parented to the hold at the point the
## player is touching. When released, it re-parents back to the controller.
##
## Also handles smooth turn on the right stick and ground locomotion on the
## left stick (which only applies while the player is on the ground).

@export var xr_origin: XROrigin3D
@export var left_controller: XRController3D
@export var right_controller: XRController3D
@export var left_hand_pivot: Node3D         ## Pivot for hand + forearm visuals
@export var right_hand_pivot: Node3D
@export var turn_speed: float = 2.2         ## rad/s for smooth turn stick
@export var walk_speed: float = 2.4         ## m/s for ground locomotion
@export var grab_activation_threshold: float = 0.55  ## analog grip pressure required to *start* a grab
@export var min_hold_strength: float = 0.15 ## grip pressure below this -> release even if tired

## Current held holds (null if free).
var left_held: Hold = null
var right_held: Hold = null

## Per-hand stamina 0..1 (1 = fresh).
var left_stamina: float = 1.0
var right_stamina: float = 1.0

## Per-hand "shake" amount, 0..1, driven by low stamina. Exposed to hand mesh.
var left_shake: float = 0.0
var right_shake: float = 0.0

## True if the hand is currently doing a shake-out (grip fully released while
## the other hand is holding on). Drains fatigue fast while held this way.
var left_shaking_out: bool = false
var right_shaking_out: bool = false

@onready var _head: XRCamera3D = xr_origin.find_child("XRCamera3D", true, false) as XRCamera3D

signal grabbed(hand: StringName, hold: Hold)
signal released(hand: StringName, hold: Hold)
signal pumped(hand: StringName)


func _ready() -> void:
	# We don't want the controllers to be visible as their default models.
	# Hands + forearms are our visual "controllers".
	pass


func _physics_process(delta: float) -> void:
	_process_input(delta)
	_update_stamina(delta)
	_update_ground_locomotion(delta)
	_update_smooth_turn(delta)
	_update_body_ik(delta)
	_update_fall_state()


# ---------------------------------------------------------------------------
# Input

func _process_input(delta: float) -> void:
	var l_grip: float = _get_grip(left_controller)
	var r_grip: float = _get_grip(right_controller)
	_handle_hand_input("left", left_controller, left_hand_pivot, l_grip, true)
	_handle_hand_input("right", right_controller, right_hand_pivot, r_grip, false)


func _handle_hand_input(hand_name: StringName, controller: XRController3D,
		pivot: Node3D, grip: float, is_left: bool) -> void:
	var held: Hold = left_held if is_left else right_held

	if held == null:
		# Looking for a grab.
		if grip >= grab_activation_threshold:
			var hit: Hold = _find_hold_under_controller(controller)
			if hit != null and hit.can_grab(_grip_strength(is_left, grip)):
				_grab(hand_name, controller, pivot, hit, is_left)
	else:
		# Already holding. Release if grip goes low OR we're too pumped to hold.
		var too_pumped: bool = _current_strength(is_left) < held.required_grip
		var released_input: bool = grip < min_hold_strength
		if released_input or too_pumped:
			_release(hand_name, controller, pivot, held, is_left)
		else:
			# Staying on - make sure the pivot tracks the hold at the point
			# we grabbed it.
			_align_pivot_to_hold(pivot, held, controller)


func _grab(hand_name: StringName, controller: XRController3D, pivot: Node3D,
		hold: Hold, is_left: bool) -> void:
	if is_left:
		left_held = hold
	else:
		right_held = hold

	# Parent the hand visual to the hold at the exact touch point, so it looks
	# glued to the wall while the rest of the body swings under it.
	pivot.reparent(hold, false)
	# Slight offset so the hand looks like it's wrapping the hold, not poking it.
	pivot.transform = hold.get_grab_transform(controller.global_position, controller.global_basis)
	hold.on_grabbed(hand_name)
	grabbed.emit(hand_name, hold)
	GameState.state = GameState.State.CLIMBING


func _release(hand_name: StringName, controller: XRController3D, pivot: Node3D,
		hold: Hold, is_left: bool) -> void:
	# Re-parent back to the controller so the hand follows it again.
	pivot.reparent(controller, false)
	pivot.transform = Transform3D(Basis(), Vector3(0.0, 0.0, 0.0))
	hold.on_released(hand_name)
	released.emit(hand_name, hold)
	if is_left:
		left_held = null
	else:
		right_held = null


# ---------------------------------------------------------------------------
# Hold detection

func _find_hold_under_controller(controller: XRController3D) -> Hold:
	var origin_pos: Vector3 = controller.global_position
	# Sphere cast from the hand tip slightly down the controller's forward axis
	# so small holds are catchable even if the controller doesn't touch exactly.
	var dir: Vector3 = -controller.global_basis.z.normalized()
	var radius: float = 0.045
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), origin_pos + dir * 0.02)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_head]

	var space := get_world_3d().direct_space_state
	var hits: Array[Dictionary] = space.intersect_shape(query, 8)
	var best: Hold = null
	var best_dist: float = INF
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Hold:
			var candidate: Hold = collider as Hold
			var d: float = origin_pos.distance_to(candidate.global_position)
			if d < best_dist:
				best = candidate
				best_dist = d
	return best


# ---------------------------------------------------------------------------
# Stamina

func _current_strength(is_left: bool) -> float:
	# Effective grip strength = analog grip squeeze * stamina.
	var grip: float = _get_grip(left_controller if is_left else right_controller)
	var stam: float = left_stamina if is_left else right_stamina
	return grip * (0.25 + 0.75 * stam)


func _grip_strength(is_left: bool, grip: float) -> float:
	var stam: float = left_stamina if is_left else right_stamina
	return grip * (0.25 + 0.75 * stam)


func _update_stamina(delta: float) -> void:
	_update_one_stamina(true, left_held, left_controller, delta)
	_update_one_stamina(false, right_held, right_controller, delta)


func _update_one_stamina(is_left: bool, held: Hold, controller: XRController3D,
		delta: float) -> void:
	var other_held: Hold = right_held if is_left else left_held
	var grip: float = _get_grip(controller)
	var stamina: float = left_stamina if is_left else right_stamina

	var drain: float = 0.0
	var regen: float = 0.0

	if held != null:
		# Holding a hold drains energy. Cost scales with:
		#   - how hard the hold is (required_grip)
		#   - how far the arm is extended (reaching hard = more pump)
		#   - how much the player is overhanging / hanging (weight_factor)
		var arm_extension: float = _arm_extension(is_left)
		var weight_factor: float = 1.0
		if other_held == null:
			# One-handed hang = full body weight on this arm.
			weight_factor = 1.7
		drain = held.required_grip * (0.35 + 0.65 * arm_extension) * weight_factor * 1.3
		drain *= 1.0 + (1.0 - grip) * 0.4  # weak squeeze fights to hold, drains more
		stamina -= drain * delta
		if is_left: left_shaking_out = false
		else: right_shaking_out = false
	elif grip < 0.1 and other_held != null:
		# Shake out: other hand holds, this one hangs loose.
		regen = 0.18
		if is_left: left_shaking_out = true
		else: right_shaking_out = true
	elif grip < 0.1 and other_held == null and not _is_on_ground():
		# Both hands off in the air - about to fall. No regen.
		if is_left: left_shaking_out = false
		else: right_shaking_out = false
	else:
		# Passive recovery (on a flat hold, on ground, etc).
		regen = 0.06
		if is_left: left_shaking_out = false
		else: right_shaking_out = false

	# Add small random shake as stamina drops.
	var shake_target: float = clamp(1.0 - stamina * 1.6, 0.0, 1.0)
	var shake_ref: float = left_shake if is_left else right_shake
	shake_ref = lerp(shake_ref, shake_target, delta * 4.0)

	stamina = clamp(stamina, 0.0, 1.0)
	if is_left:
		left_stamina = stamina
		left_shake = shake_ref
	else:
		right_stamina = stamina
		right_shake = shake_ref

	# Pumped out signal.
	if stamina <= 0.001 and held != null:
		pumped.emit("left" if is_left else "right")
		GameState.grip_pumped.emit("left" if is_left else "right")


func _arm_extension(is_left: bool) -> float:
	# Approximate how far the arm is extended by the distance between the head
	# and the hand. Fully extended = 1, hand at shoulder = 0.
	var hand_pos: Vector3 = left_hand_pivot.global_position if is_left else right_hand_pivot.global_position
	var head_pos: Vector3 = _head.global_position
	var d: float = head_pos.distance_to(hand_pos)
	return clamp((d - 0.30) / 0.55, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Locomotion / turn

func _update_ground_locomotion(delta: float) -> void:
	# Left stick only moves the body while on the ground. Once climbing, the
	# hands are the only thing that moves the body.
	if not _is_on_ground():
		return
	if left_held != null or right_held != null:
		return
	var stick: Vector2 = _get_primary(left_controller)
	if stick.length() < 0.15:
		return
	var head_yaw: Basis = Basis(Vector3.UP, _head.rotation.y)
	var move_vec: Vector3 = head_yaw * Vector3(stick.x, 0.0, -stick.y)
	move_vec = move_vec.normalized() * walk_speed * delta
	xr_origin.global_position += move_vec


func _update_smooth_turn(delta: float) -> void:
	var stick: Vector2 = _get_primary(right_controller)
	if abs(stick.x) < 0.25:
		return
	var yaw_delta: float = stick.x * turn_speed * delta
	xr_origin.rotate_object_local(Vector3.UP, yaw_delta)


# ---------------------------------------------------------------------------
# Body IK - when holding holds, the XROrigin is pulled up/across so the body
# follows the hands. Without this the hands would stick to the wall but the
# player would never actually climb.

func _update_body_ik(delta: float) -> void:
	if GameState.state == GameState.State.FALLING:
		return  # FallCatcher owns movement while falling.
	if left_held == null and right_held == null:
		return
	if _is_on_ground():
		# On the wall but near floor - only pull up if hands are clearly
		# above the head (i.e. the player has started climbing).
		var head_y: float = _head.global_position.y
		var highest_hand_y: float = max(
			left_hand_pivot.global_position.y if left_held != null else head_y,
			right_hand_pivot.global_position.y if right_held != null else head_y
		)
		if highest_hand_y < head_y + 0.15:
			return

	# Compute target harness position as the average of held hand positions,
	# pulled down by ~0.7m so the body hangs under the hands.
	var held_positions: Array[Vector3] = []
	if left_held != null:
		held_positions.append(left_hand_pivot.global_position)
	if right_held != null:
		held_positions.append(right_hand_pivot.global_position)
	var avg := Vector3.ZERO
	for p in held_positions:
		avg += p
	avg /= float(held_positions.size())

	var target_harness: Vector3 = avg - Vector3(0.0, 0.75, 0.0)
	# The harness in world = head - 0.9 (see get_harness_position()). We want
	# to move xr_origin so the harness reaches target_harness. Current harness
	# is _head.global_position - (0,0.9,0); so the origin correction is:
	var current_harness: Vector3 = get_harness_position()
	var correction: Vector3 = target_harness - current_harness
	# Smooth it - grabbing a hold should not teleport the body.
	correction = correction * clamp(delta * 4.5, 0.0, 1.0)
	# Don't let hands pull the body downward through the floor.
	var new_origin_y: float = xr_origin.global_position.y + correction.y
	if new_origin_y < 0.0:
		correction.y -= new_origin_y
	xr_origin.global_position += correction


# ---------------------------------------------------------------------------
# Falling

func _update_fall_state() -> void:
	# Both hands off the wall and not on the ground -> fall.
	if (left_held == null and right_held == null
			and not _is_on_ground()
			and GameState.state != GameState.State.FALLING):
		GameState.state = GameState.State.FALLING


func _is_on_ground() -> bool:
	return GameState.state == GameState.State.ON_GROUND or GameState.state == GameState.State.RESTING


# ---------------------------------------------------------------------------
# Helpers

func _get_grip(controller: XRController3D) -> float:
	if controller == null or not is_instance_valid(controller):
		return 0.0
	# XRController3D.get_float reads the OpenXR "grip" action. On desktop
	# without a headset this returns 0, which is fine - grabbing just won't
	# work without a VR controller, which is expected for a VR-only game.
	var v: float = controller.get_float("grip")
	return clamp(v, 0.0, 1.0)


func _get_primary(controller: XRController3D) -> Vector2:
	if controller == null or not is_instance_valid(controller):
		return Vector2.ZERO
	# "primary" is the default thumbstick action name Godot 4.3's OpenXR
	# action map binds to /input/thumbstick on both hands.
	return controller.get_vector2("primary")


func _align_pivot_to_hold(pivot: Node3D, hold: Hold, controller: XRController3D) -> void:
	# Keep the visual hand at the hold but let it rotate to follow the
	# controller's twist, so the player can still orient their hand.
	var target: Transform3D = hold.get_grab_transform(controller.global_position, controller.global_basis)
	# Blend toward the target so it doesn't snap.
	pivot.global_transform = pivot.global_transform.interpolate_with(target, 0.35)


# Public helpers for rope / UI to query.
func both_hands_free() -> bool:
	return left_held == null and right_held == null


func get_hand_world_position(is_left: bool) -> Vector3:
	return left_hand_pivot.global_position if is_left else right_hand_pivot.global_position


func get_harness_position() -> Vector3:
	# Approximate harness / waist position: halfway between head and hands,
	# ~0.9 m below the head. That's where the rope ties in.
	return _head.global_position - Vector3(0.0, 0.9, 0.0)
