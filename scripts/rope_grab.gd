extends Node3D
## Rope grab controller.
##
## When a hand is NOT holding a climbing hold, pressing grip near the rope
## grabs it. The grabbed particle follows the hand while grip is held. This
## is what lets the player pull up slack and push it through a quickdraw gate.
##
## The grip threshold is a little lower for the rope than for a hold because
## catching a swinging rope is hard enough with a controller.

@export var climber_path: NodePath
@export var rope_path: NodePath
@export var left_controller: XRController3D
@export var right_controller: XRController3D
@export var grab_threshold: float = 0.45
@export var release_threshold: float = 0.12

var _climber: Node
var _rope: RopeSystem
var _held_hand: StringName = &""


func _ready() -> void:
	_climber = get_node_or_null(climber_path)
	_rope = get_node_or_null(rope_path) as RopeSystem


func _physics_process(_delta: float) -> void:
	if _rope == null or _climber == null:
		return

	if _held_hand != &"":
		# Currently holding the rope.
		var ctrl: XRController3D = left_controller if _held_hand == "left" else right_controller
		var grip: float = clamp(ctrl.get_float("grip"), 0.0, 1.0)
		# Also release if the same hand has grabbed a hold (handled by climber).
		var hand_busy: bool = (_held_hand == "left" and _climber.left_held != null) or \
				(_held_hand == "right" and _climber.right_held != null)
		if grip < release_threshold or hand_busy:
			_held_hand = &""
			_rope.release_grab()
		else:
			# Move the grabbed particle to the controller tip.
			var tip: Vector3 = ctrl.global_position - ctrl.global_basis.z * 0.05
			_rope.set_grabbed_position(tip)
		return

	# Not holding - look for a grab from whichever hand is free.
	_try_grab("left", left_controller)
	if _held_hand == &"":
		_try_grab("right", right_controller)


func _try_grab(hand: StringName, ctrl: XRController3D) -> void:
	if ctrl == null:
		return
	if hand == "left" and _climber.left_held != null:
		return
	if hand == "right" and _climber.right_held != null:
		return
	var grip: float = clamp(ctrl.get_float("grip"), 0.0, 1.0)
	if grip < grab_threshold:
		return
	var tip: Vector3 = ctrl.global_position - ctrl.global_basis.z * 0.05
	var idx: int = _rope.get_closest_particle(tip)
	if idx >= 0:
		_held_hand = hand
		_rope.set_grabbed_particle(idx, hand)
