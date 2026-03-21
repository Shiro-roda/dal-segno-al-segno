shader_type canvas_item;
render_mode unshaded, skip_vertex_transform;

uniform float curvature : hint_range(0.0, 10.0, 0.1) = 6.0;
uniform float vignette_multiplier : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform float ca_strength : hint_range(0.0, 20.0, 0.1) = 3.0;
uniform float blur_strength : hint_range(0.0, 3.0, 0.1) = 0.5;
uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 ca_offset = vec2(ca_strength, 0.0) * SCREEN_PIXEL_SIZE;
	vec2 centered_uv = SCREEN_UV * 2.0 - 1.0;
	vec2 uv_offset = centered_uv.yx / curvature;
	vec2 warped_uv = centered_uv + centered_uv * uv_offset * uv_offset;
	vec3 cutoff = vec3(step(abs(warped_uv.x), 1.0) * step(abs(warped_uv.y), 1.0));
	// Scale scanline frequency by viewport height so density stays consistent at any resolution
	float scanline_freq = (1.0 / SCREEN_PIXEL_SIZE.y) * (PI / 960.0);
	vec3 scanlines = vec3(sin(warped_uv.y * scanline_freq) * 0.1 + 0.9);
	vec3 vignette = vec3(length(pow(abs(centered_uv), vec2(4.0)) / 8.0));

	float red = textureLod(screen_texture, ((warped_uv + 1.0) / 2.0) - ca_offset, blur_strength).r;
	float green = textureLod(screen_texture, ((warped_uv + 1.0) / 2.0), blur_strength).g;
	float blue = textureLod(screen_texture, ((warped_uv + 1.0) / 2.0) + ca_offset, blur_strength).b;

	// Clamp to 0 to prevent negative vignette from creating bright artifacts at screen edges
	vec3 screen_color = max(vec3(0.0), (vec3(red, green, blue) * cutoff * scanlines) - vignette * vignette_multiplier);

	COLOR = vec4(screen_color, 1.0);
}