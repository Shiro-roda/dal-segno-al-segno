shader_type canvas_item;
render_mode unshaded, skip_vertex_transform;

uniform float curvature : hint_range(0.0, 10.0, 0.1) = 6.0;
uniform float vignette_multiplier : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform float ca_strength : hint_range(0.0, 20.0, 0.1) = 2.5;
uniform float blur_strength : hint_range(0.0, 3.0, 0.1) = 0.5;
uniform float brightness   : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float contrast     : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float saturation   : hint_range(0.0, 2.0, 0.01) = 1.0;

uniform vec3 channel_strength = vec3(1.0);

uniform float glitch_intensity = 0.0;
uniform float noise_strength = 0.0;
uniform float tear_intensity = 0.0;
uniform float block_glitch = 0.0;


uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap;

float rand(vec2 co){
	return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {

	vec2 centered_uv = SCREEN_UV * 2.0 - 1.0;

	// ----------------------------
	// 1️⃣ CURVATURE FIRST
	// ----------------------------
	vec2 uv_offset = centered_uv.yx / curvature;
	vec2 warped_uv = centered_uv + centered_uv * uv_offset * uv_offset;

	// ----------------------------
	// 2️⃣ TEARING ON CURVED SPACE
	// ----------------------------
	// ----------------------------
	// 2️⃣ SHARPER TEARING
	// ----------------------------

	float tear_freq = 120.0; // more lines = thinner slices
	float tear_band = floor(warped_uv.y * tear_freq);

	float tear_rand = rand(vec2(tear_band, floor(TIME * 40.0)));

	float tear_mask = step(0.7, tear_rand);

	warped_uv.x += tear_mask * tear_intensity * 0.6;


	
	warped_uv.x += sin(warped_uv.y * 120.0 + TIME * 60.0) * tear_intensity * 0.01;

	float block_size = 140.0;

	vec2 block_uv = floor(warped_uv * block_size) / block_size;

	warped_uv = mix(warped_uv, block_uv, block_glitch);


	// --- CRT EDGE CUTOFF ---
	float edge = max(abs(warped_uv.x), abs(warped_uv.y));
	float cutoff_mask = smoothstep(1.05, 1.0, edge);



	// ----------------------------
	// 3️⃣ RGB SPLIT
	// ----------------------------
	float removed_count = 3.0 - (channel_strength.r + channel_strength.g + channel_strength.b);

	float ca_dynamic = ca_strength
		+ removed_count * 2.0
		+ glitch_intensity * 25.0;

	vec2 ca_offset = vec2(ca_dynamic, 0.0) * SCREEN_PIXEL_SIZE;

	vec2 sample_uv = (warped_uv + 1.0) / 2.0;

	float red = textureLod(screen_texture, sample_uv - ca_offset, blur_strength).r;
	float green = textureLod(screen_texture, sample_uv, blur_strength).g;
	float blue = textureLod(screen_texture, sample_uv + ca_offset, blur_strength).b;

	vec3 filtered = vec3(
		red * channel_strength.r,
		green * channel_strength.g,
		blue * channel_strength.b
	);

	// ----------------------------
	// 4️⃣ DESATURATION / SATURATION
	// ----------------------------
	float grayscale = dot(filtered, vec3(0.299, 0.587, 0.114));
	// Channel-removal desaturation (existing system)
	float desat_amount = removed_count * 0.02;
	filtered = mix(filtered, vec3(grayscale), desat_amount);
	// User-controlled saturation: 1.0 = normal, 0.0 = grey, 2.0 = vivid
	grayscale = dot(filtered, vec3(0.299, 0.587, 0.114));
	filtered = mix(vec3(grayscale), filtered, saturation);

	// ----------------------------
	// 5️⃣ SCANLINES
	// ----------------------------
	float scan = sin(warped_uv.y * 180.0) * 0.1 + 0.85;
	scan += glitch_intensity * sin(warped_uv.y * 400.0 + TIME * 40.0) * 0.05;

	float stripe = sin(warped_uv.x * 600.0) * 0.02;
	scan *= 1.0 - stripe;

	vec3 scanlines = vec3(scan);

	// ----------------------------
	// 6️⃣ NOISE
	// ----------------------------
	float noise = rand(warped_uv * TIME) * noise_strength;
	filtered += noise;

	// ----------------------------
	// 7️⃣ VIGNETTE (USE CURVED SPACE)
	// ----------------------------
	float vignette = length(pow(abs(warped_uv), vec2(4.0)) / 8.0);
	float vignette_dynamic = vignette_multiplier + removed_count * 0.5;

	vec3 final_color = (filtered * scanlines * cutoff_mask)
		- vignette * vignette_dynamic;


	// Brightness and contrast applied globally over the full screen
	final_color = (final_color - 0.5) * contrast + 0.5;
	final_color = clamp(final_color * brightness, 0.0, 1.0);

	COLOR = vec4(final_color, 1.0);
}

