shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 text_color : source_color = vec3(1.0); // COLOR PICKER
uniform float flicker_speed : hint_range(0.1, 20.0) = 4.0;
uniform float uv_aspect = 1.0; // corrects stretched pixels
uniform float pixel_size : hint_range(1.0, 50.0) = 8.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.6;

// Stable random hash
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}



void fragment() {
	// Pixelize UV with aspect fix
    vec2 pix_uv = floor(vec2(UV.x * pixel_size * uv_aspect,
                             UV.y * pixel_size));

    float rnd = hash(pix_uv);

    // Time flicker
    float flicker = sin(TIME * flicker_speed + rnd * 20.0);

    // Normalize 0–1
    flicker = (flicker * 0.5) + 0.5;

    // Visible threshold
    float alpha = step(flicker_intensity, flicker);

    ALBEDO = text_color;
    ALPHA = alpha;
}
