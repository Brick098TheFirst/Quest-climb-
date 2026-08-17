extends StaticBody3D
class_name Quickdraw
## A quickdraw hanging on the wall: two carabiners joined by a dogbone sling.
##
## The TOP carabiner is bolted to the wall and fixed. The BOTTOM carabiner is
## the one you clip the rope into. Clipping works like this:
##
##   1. Player grabs a section of rope with their free hand.
##   2. They push that rope up toward the bottom carabiner.
##   3. We look at the angle at which the rope approaches the gate opening.
##      The gate faces away from the wall and slightly downward (real sport
##      draws are pre-oriented). If the rope approaches from inside the
##      acceptance cone AND has enough velocity through the gate, it clips.
##   4. If the angle is wrong, the rope simply bounces off the carabiner body
##      - no sound, no glow - exactly like real life.
##
## This "silent failure" is intentional per the design brief.

@export var draw_index: int = 0
@export var acceptance_cone_degrees: float = 55.0  ## How wide the "good" approach angle is.
@export var min_clip_speed: float = 0.35           ## m/s through the gate.

@onready var gate: Node3D = $Bottom/GateAnchor
@onready var rope_system: RopeSystem = get_tree().get_first_node_in_group("rope") as RopeSystem
@onready var _clip_sound: AudioStreamPlayer3D = $ClipSound

var clipped: bool = false


func _ready() -> void:
	add_to_group("draw_%d" % draw_index)


func _physics_process(_delta: float) -> void:
	if clipped:
		return
	if rope_system == null or rope_system.grabbed_particle < 0:
		return

	# Is the grabbed particle near the gate?
	var particle_pos: Vector3 = rope_system.get_particle_position(rope_system.grabbed_particle)
	var gate_world: Vector3 = gate.global_position
	var to_particle: Vector3 = particle_pos - gate_world
	var dist: float = to_particle.length()
	if dist > 0.18:
		return

	# Direction from gate "inside" (toward the wall) outward. The rope must
	# travel in roughly this direction to push through the gate.
	var gate_out: Vector3 = gate.global_basis.z.normalized()

	# Particle motion: use previous vs current position from the rope.
	var prev_idx: int = rope_system.grabbed_particle
	var velocity: Vector3 = rope_system.get_particle_velocity(prev_idx)
	var speed: float = velocity.length()

	if speed < min_clip_speed:
		return

	var approach: Vector3 = velocity.normalized()
	var dot: float = approach.dot(gate_out)
	var angle_ok: bool = dot > cos(deg_to_rad(acceptance_cone_degrees))

	# Also require the rope to be on the *outside* side of the gate (not
	# pushing through from behind the wall).
	var from_gate_to_wall: Vector3 = -gate_out
	var is_outside: bool = to_particle.dot(gate_out) > 0.0

	if angle_ok and is_outside and dist < 0.12:
		_perform_clip()


func _perform_clip() -> void:
	clipped = true
	rope_system.clip_to_draw(draw_index, self)
	if _clip_sound != null and _clip_sound.stream != null:
		_clip_sound.play()
