shader_type canvas_item;

// Animated sea for the city painting: water pixels (bright cyan/blue) ripple one texel
// at a time, get drifting light bands and twinkling glints; land stays untouched.

uniform vec2 texels = vec2(400.0, 224.0);

bool is_water(vec3 c) {
	return c.b > 0.55 && c.g > 0.5 && c.r < 0.5 && c.b > c.r + 0.25;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Godot 4 feeds fragment() a COLOR already multiplied by the texture, so the
// modulate colour is carried separately.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (is_water(color.rgb)) {
		vec2 cell = floor(UV * texels);
		float t = floor(TIME * 6.0) / 6.0;
		float wave = sin(cell.y * 0.9 + t * 2.4) + sin(cell.x * 0.13 + t * 1.3);
		vec2 shifted = UV + vec2(round(wave * 0.6) / texels.x, 0.0);
		vec4 moved = texture(TEXTURE, shifted);
		if (is_water(moved.rgb)) {
			color = moved;
		}
		// Slow diagonal light bands.
		float band = fract((cell.x * 0.5 + cell.y - t * 5.0) / 23.0);
		if (band < 0.07) {
			color.rgb = mix(color.rgb, vec3(0.85, 1.0, 1.0), 0.28);
		}
		// Twinkling glints on a sparse grid.
		vec2 glint_cell = floor(cell / 5.0);
		float h = hash(glint_cell);
		if (h > 0.9 && mod(cell.x, 5.0) == 2.0 && mod(cell.y, 5.0) == 2.0 && sin(TIME * 3.0 + h * 60.0) > 0.75) {
			color.rgb = vec3(1.0);
		}
	}
	COLOR = color * tint;
}
