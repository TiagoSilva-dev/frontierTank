shader_type canvas_item;

// Julgamento do Sol: the EDGES of the screen darken (never the middle), so the terrain,
// the enemies, the wind arrow and the shot line keep their normal brightness.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.05, 0.03, 0.16, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.72, 0.25, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 0.85)) * 1.55;
	float v = smoothstep(0.55, 1.1, d);
	float edge = smoothstep(0.92, 1.25, d);
	vec3 colour = mix(tint.rgb, rim.rgb, edge * 0.55);
	COLOR = vec4(colour, v * amount);
}
