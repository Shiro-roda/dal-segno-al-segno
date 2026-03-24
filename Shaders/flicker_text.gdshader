shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform vec3 text_color : source_color = vec3(1.0);
uniform float flicker_speed : hint_range(0.1, 20.0) = 4.0;
uniform float uv_aspect = 1.0;
uniform float pixel_size : hint_range(1.0, 50.0) = 8.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.6;

uniform vec3 shadow_color : source_color = vec3(0.0);
// Integer pixel-grid steps: (1, -1) = 1 pixel right, 1 pixel down
uniform vec2 shadow_pixel_steps = vec2(1.0, -1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Each pixel gets an independent random on/off state that changes at its own rate.
// phase_seed is unique per pixel; time_bucket quantises TIME so state holds briefly.
float flicker_on(vec2 pix, float speed, float intensity) {
    float phase   = hash(pix);                              // [0,1) unique per cell
    float rate    = 0.5 + hash(pix + vec2(7.3, 13.7));     // [0.5,1.5) per-cell rate
    float t_frame = floor(TIME * speed * rate + phase * 97.3); // quantised, per-cell offset
    float rnd     = hash(pix + vec2(t_frame * 0.1371, t_frame * 0.7913));
    return step(intensity, rnd);
}

void fragment() {
    // Pixelate UV once — all lookups use this grid
    vec2 pix_uv = floor(vec2(UV.x * pixel_size * uv_aspect, UV.y * pixel_size));

    // --- Text layer ---
    float on = flicker_on(pix_uv, flicker_speed, flicker_intensity);

    // --- Shadow layer ---
    vec2 src_pix_uv = pix_uv - floor(shadow_pixel_steps);
    float shadow_on = flicker_on(src_pix_uv, flicker_speed, flicker_intensity);

    // Text wins; shadow only where this pixel has no text
    float use_shadow = (1.0 - on) * shadow_on;

    // Discard pixels that are neither text nor shadow
    if (on < 0.5 && use_shadow < 0.5) discard;

    ALBEDO = on > 0.5 ? text_color : shadow_color;
    ALPHA  = 1.0;
}
