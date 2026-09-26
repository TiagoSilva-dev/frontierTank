shader_type canvas_item;

// Flat-colour silhouette of a texture (its alpha, one colour): the rim of the POW
// cut-in portrait and the ghosts of the empty equipment slots in the Mochila.

uniform vec4 flat_color : source_color = vec4(1.0);

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(flat_color.rgb, alpha * flat_color.a * COLOR.a);
}
