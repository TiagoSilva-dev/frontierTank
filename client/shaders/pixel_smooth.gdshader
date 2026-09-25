shader_type canvas_item;

// Crisp pixel art at any scale. Plain nearest filtering at 1.5x or 2.25x makes some
// art pixels one screen pixel wider than others; here every art pixel keeps the
// same width and only the seam between two of them is blended over one screen
// pixel. Whole-number scales come out exactly like nearest filtering.
// The canvas item must use linear filtering.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 texel = UV * size;
	vec2 seam = floor(texel + 0.5);
	vec2 span = max(fwidth(texel), vec2(1e-4));
	texel = seam + clamp((texel - seam) / span, -0.5, 0.5);
	COLOR = texture(TEXTURE, texel / size) * tint;
}
