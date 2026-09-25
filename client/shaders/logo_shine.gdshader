shader_type canvas_item;

// A diagonal band of light sweeps across the title logo every few seconds. The band
// is computed on the art's own pixel grid so the shine stays blocky like the logo.

uniform float period = 3.6;

// Godot 4 feeds fragment() a COLOR already multiplied by the texture, so the
// modulate colour is carried separately.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE) * TEXTURE_PIXEL_SIZE;
	float sweep = mod(TIME, period) / period * 2.4 - 0.7;
	float band = abs(cell.x + cell.y * 0.45 - sweep);
	float light = step(band, 0.035) * 0.7 + step(band, 0.075) * 0.25;
	color.rgb = mix(color.rgb, vec3(1.0, 1.0, 0.9), light * color.a);
	COLOR = color * tint;
}
