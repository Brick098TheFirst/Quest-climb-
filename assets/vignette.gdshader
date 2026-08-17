shader_type canvas_item;

// Radial red vignette. `intensity` is driven by stamina_feedback.gd via the
// ColorRect's modulate alpha. Edges of the screen get progressively more red,
// the center stays (mostly) clear.

render_mode unshaded;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float d = distance(UV, center) * 1.45;
	d = smoothstep(0.35, 1.0, d);
	COLOR = vec4(0.55, 0.0, 0.0, d * COLOR.a);
}
