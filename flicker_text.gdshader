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
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    // Pixelate UV once — all lookups use this grid
    vec2 pix_uv = floor(vec2(UV.x * pixel_size * uv_aspect, UV.y * pixel_size));

    // --- Text layer ---
    float rnd = hash(pix_uv);
    float f   = sin(TIME * flicker_speed + rnd * 20.0) * 0.5 + 0.5;
    float on  = step(flicker_intensity, f);

    // --- Shadow layer ---
    // This pixel's shadow is cast by the text pixel at (pix_uv - shadow_pixel_steps).
    // Subtract the offset to find the source text pixel, hash that, get its flicker.
    vec2 src_pix_uv = pix_uv - floor(shadow_pixel_steps);
    float src_rnd   = hash(src_pix_uv);
    float src_f     = sin(TIME * flicker_speed + src_rnd * 20.0) * 0.5 + 0.5;
    float shadow_on = step(flicker_intensity, src_f);

    // Text wins; shadow only where this pixel has no text
    float use_shadow = (1.0 - on) * shadow_on;

    // Discard pixels that are neither text nor shadow
    if (on < 0.5 && use_shadow < 0.5) discard;

    ALBEDO = on > 0.5 ? text_color : shadow_color;
    ALPHA  = 1.0;
}
