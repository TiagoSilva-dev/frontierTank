shader_type canvas_item;

// Julgamento do Sol: a faint heat ripple around the celestial lance while it crosses the
// screen. It only bends the picture in a small disc around the lance (radius in UV of the
// screen height) and fades to nothing at the edge, so the trajectory, the wind arrow and
// the targets stay exactly where they are.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.12;
uniform float strength = 0.0;
uniform float aspect = 1.7777;

void fragment() {
	vec2 d = (SCREEN_UV - center) * vec2(aspect, 1.0);
	float dist = length(d);
	float falloff = smoothstep(radius, radius * 0.25, dist);
	vec2 dir = dist > 0.0001 ? d / dist : vec2(0.0);
	float wave = sin(dist * 70.0 - TIME * 26.0);
	vec2 offset = dir * wave * 0.0035 * falloff * strength;
	offset.x /= aspect;
	COLOR = vec4(texture(screen_texture, SCREEN_UV + offset).rgb, 1.0);
}
