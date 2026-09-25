shader_type canvas_item;

// Character look: hair dye (palette swap inside the head area) and the clothes aura
// glow drawn around the sprite silhouette.

uniform int hair_count = 0;
uniform vec3 hair[16];
uniform vec2 hair_luma = vec2(0.0, 1.0);
uniform vec4 head_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 dye = vec4(0.0);
uniform vec4 glow = vec4(0.0);
uniform float glow_width = 5.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Godot 4 feeds fragment() a COLOR already multiplied by the texture, so the
// modulate colour is carried separately.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (dye.a > 0.0 && color.a > 0.5 && UV.x >= head_rect.x && UV.y >= head_rect.y && UV.x <= head_rect.z && UV.y <= head_rect.w) {
		for (int i = 0; i < hair_count; i++) {
			vec3 d = abs(color.rgb - hair[i]);
			if (max(d.r, max(d.g, d.b)) < 0.012) {
				float t = clamp((luma(color.rgb) - hair_luma.x) / max(0.001, hair_luma.y - hair_luma.x), 0.0, 1.0);
				vec3 dark = dye.rgb * 0.32;
				vec3 light = mix(dye.rgb, vec3(1.0), 0.42);
				color.rgb = t < 0.5 ? mix(dark, dye.rgb, t * 2.0) : mix(dye.rgb, light, (t - 0.5) * 2.0);
				break;
			}
		}
	}
	if (glow.a > 0.0) {
		float pulse = 0.72 + 0.28 * sin(TIME * 3.0 + UV.y * 14.0);
		vec3 bright = mix(glow.rgb, vec3(1.0), 0.55);
		if (color.a < 0.5) {
			// Soft outer glow: brighter next to the body, fading over glow_width texels.
			float best = 99.0;
			for (int dy = -5; dy <= 5; dy++) {
				for (int dx = -5; dx <= 5; dx++) {
					vec2 offset = vec2(float(dx), float(dy));
					float dist = length(offset);
					if (dist > glow_width + 0.5 || dist >= best) {
						continue;
					}
					if (texture(TEXTURE, UV + offset * TEXTURE_PIXEL_SIZE).a > 0.5) {
						best = dist;
					}
				}
			}
			if (best < 90.0) {
				float t = clamp((best - 0.5) / glow_width, 0.0, 1.0);
				float strength = pow(1.0 - t, 1.25) * glow.a * pulse;
				color = vec4(mix(bright, glow.rgb, t), clamp(strength, 0.0, 1.0));
			}
		} else {
			// Rim light: the outline of the body catches the aura's colour.
			float edge = 0.0;
			for (int k = 0; k < 4; k++) {
				vec2 dir = vec2(k == 0 ? 1.0 : (k == 1 ? -1.0 : 0.0), k == 2 ? 1.0 : (k == 3 ? -1.0 : 0.0));
				if (texture(TEXTURE, UV + dir * TEXTURE_PIXEL_SIZE).a < 0.5) {
					edge = 1.0;
				} else if (texture(TEXTURE, UV + dir * 2.0 * TEXTURE_PIXEL_SIZE).a < 0.5) {
					edge = max(edge, 0.45);
				}
			}
			color.rgb = mix(color.rgb, bright, edge * 0.4 * pulse * glow.a);
		}
	}
	COLOR = color * tint;
}
