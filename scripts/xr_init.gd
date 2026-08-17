extends Node3D
## Ensures the game launches in VR.
##
## On Quest 2 this runs as part of the main scene. We explicitly start the
## OpenXR interface and set the display refresh rate to 90 Hz. If OpenXR fails
## to start for any reason we print a clear error - this build is VR-only and
## we don't want a silent flatscreen fallback.

@export var xr_origin: XROrigin3D
@export var camera: XRCamera3D
@export var target_refresh_rate: float = 90.0


func _ready() -> void:
	var xr_interface: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		push_error("OpenXR interface not available. This build is VR-only.")
		return

	if not xr_interface.is_initialized():
		var ok: bool = xr_interface.initialize()
		if not ok:
			push_error("Failed to initialize OpenXR: %s" % xr_interface.get_initialize_error())
			return

	get_viewport().use_xr = true
	# Force stage space so we get accurate 1:1 tracking.
	xr_interface.set_reference_space(OpenXRInterface.REFERENCE_SPACE_STAGE)

	# Request 90 Hz if the headset supports it.
	_try_set_refresh_rate(xr_interface, target_refresh_rate)

	RenderServer.viewport_set_use_xr(get_viewport().get_viewport_rid(), true)

	print("OpenXR initialized: %s" % xr_interface.get_system_name())
	print("  runtime: %s %s" % [xr_interface.get_runtime_name(), xr_interface.get_runtime_version()])
	print("  refresh rate: %.1f Hz" % xr_interface.get_display_refresh_rate())


func _try_set_refresh_rate(xr_interface: OpenXRInterface, target: float) -> void:
	# Godot 4.3 exposes the available rates via OpenXRInterface.
	var rates: PackedFloat32Array = PackedFloat32Array()
	if xr_interface.has_method("get_available_display_refresh_rates"):
		var result: Variant = xr_interface.get_available_display_refresh_rates()
		if result is PackedFloat32Array:
			rates = result
		elif result is Array:
			for v in result:
				if typeof(v) == TYPE_FLOAT:
					rates.append(v)
	if target in rates:
		xr_interface.request_display_refresh_rate(target)
