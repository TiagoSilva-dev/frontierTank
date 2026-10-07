shader_type canvas_item;

// Shock ring of the time bomb (and, smaller, of the laser): a ring that runs out from the
// blast bending the picture as it crosses, with a short flash of light at the start. It only
// moves the picture a few pixels inside the ring, so the aim and the fighters stay where they are.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float thickness = 0.07;
uniform float strength = 0.02;
uniform float flash = 0.0;
uniform float aspect = 1.7777;
uniform vec3 flash_color = vec3(1.0, 0.82, 0.55);

void fragment() {
	vec2 d = (SCREEN_UV - center) * vec2(aspect, 1.0);
	float dist = length(d);
	vec2 dir = dist > 0.0001 ? d / dist : vec2(0.0);
	float front = (dist - radius) / thickness;
	float ring = smoothstep(1.0, 0.0, abs(front));
	vec2 offset = dir * sin(front * 3.14159) * ring * strength;
	offset.x /= aspect;
	vec3 color = texture(screen_texture, SCREEN_UV + offset).rgb;
	color += flash_color * ring * ring * 0.18 * step(0.0001, strength);
	float lit = flash * smoothstep(0.7, 0.0, dist);
	color = mix(color, flash_color, clamp(lit, 0.0, 0.9));
	COLOR = vec4(color, 1.0);
}
