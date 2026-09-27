shader_type canvas_item;

// The skill icons of the battle HUD (0.16). Enlarged, every art pixel keeps the same
// width (as pixel_smooth.gdshader); shrunk (a 64 px icon in a 36 px slot) four taps
// are averaged so no art pixel simply drops out. While the skill cannot be used the
// icon turns grey and darker. The canvas item must use linear filtering.

uniform float saturation : hint_range(0.0, 1.0) = 1.0;
uniform float brightness = 1.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 texel = UV * size;
	vec2 span = max(fwidth(texel), vec2(1e-4));
	vec4 c;
	if (span.x > 1.0) {
		vec2 d = span / size * 0.25;
		c = (texture(TEXTURE, UV + vec2(-d.x, -d.y)) + texture(TEXTURE, UV + vec2(d.x, -d.y))
			+ texture(TEXTURE, UV + vec2(-d.x, d.y)) + texture(TEXTURE, UV + vec2(d.x, d.y))) * 0.25;
	} else {
		vec2 seam = floor(texel + 0.5);
		texel = seam + clamp((texel - seam) / span, -0.5, 0.5);
		c = texture(TEXTURE, texel / size);
	}
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(grey), c.rgb, saturation) * brightness;
	COLOR = c * tint;
}
