extends CanvasLayer
## Full-screen fatigue feedback.
##
##  - red vignette that pulses in as average arm stamina drops
##  - subtle controller rumble as hands pump out
##  - faint heartbeat audio at very low stamina
##
## This is the only 2D UI in the game by design - everything else is
## diegetic / world-space.

@export var climber_path: NodePath
@export var left_controller: XRController3D
@export var right_controller: XRController3D
@export var vignette: ColorRect
@export var heartbeat: AudioStreamPlayer

var _climber: Node
var _rumble_accum: float = 0.0


func _ready() -> void:
	_climber = get_node_or_null(climber_path)
	if vignette != null:
		vignette.color = Color(0.6, 0.0, 0.0, 0.0)


func _process(delta: float) -> void:
	if _climber == null:
		return
	var avg_stam: float = (_climber.left_stamina + _climber.right_stamina) * 0.5
	# Vignette ramps in below 0.5.
	var intensity: float = clamp((0.5 - avg_stam) / 0.5, 0.0, 1.0)
	# Pulse with a heartbeat-like envelope.
	var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	var alpha: float = intensity * intensity * pulse * 0.55
	if vignette != null:
		vignette.color = Color(0.55, 0.0, 0.0, alpha)

	# Haptics.
	if intensity > 0.25:
		_rumble_accum += delta
		var interval: float = lerp(0.45, 0.85, intensity)
		if _rumble_accum > interval:
			_rumble_accum = 0.0
			var amp: float = intensity * 0.6
			var dur: float = lerp(0.08, 0.18, intensity)
			if left_controller:
				left_controller.trigger_haptic_pulse("haptic", amp, dur)
			if right_controller:
				right_controller.trigger_haptic_pulse("haptic", amp, dur)
	else:
		_rumble_accum = 0.0

	# Heartbeat at very low stamina.
	if heartbeat != null:
		if avg_stam < 0.18 and not heartbeat.playing:
			heartbeat.play()
		elif avg_stam >= 0.3 and heartbeat.playing:
			heartbeat.stop()
