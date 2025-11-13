shader_type spatial;
render_mode unshaded, depth_draw_always;

uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D depth_tex : hint_depth_texture;

uniform int vision_mode = 0;        // 0=C,1=M,2=Y
uniform vec3 flash_pos = vec3(0.0);
uniform vec3 flash_dir = vec3(0.0, 0.0, -1.0);
uniform float flash_angle = 0.5;    // radians
uniform float cone_range = 20.0;    // meters
uniform float edge_softness = 0.01; // smoothness near edge
uniform float hue_boost = 2.5;      // brightness multiplier
uniform float resonance_tolerance = 0.15; // how wide the hue match is

// Helper to convert RGB to approximate hue (0..1)
float get_hue(vec3 color) {
    float cmax = max(color.r, max(color.g, color.b));
    float cmin = min(color.r, min(color.g, color.b));
    float delta = cmax - cmin;

    if (delta < 1e-5) return 0.0; // gray
    float hue;
    if (cmax == color.r) hue = mod((color.g - color.b) / delta, 6.0);
    else if (cmax == color.g) hue = ((color.b - color.r) / delta) + 2.0;
    else hue = ((color.r - color.g) / delta) + 4.0;
    hue /= 6.0;
    if (hue < 0.0) hue += 1.0;
    return hue;
}

// return hue (0..1) of the "excited" complementary color per mode
float get_target_hue(int mode) {
    if (mode == 0) return 0.0 / 6.0; // Red complement for Cyan
    if (mode == 1) return 2.0 / 6.0; // Green complement for Magenta
    if (mode == 2) return 4.0 / 6.0; // Blue complement for Yellow
    return 0.0;
}

void fragment() {
    vec3 col = texture(screen_tex, SCREEN_UV).rgb;
    float depth = texture(depth_tex, SCREEN_UV).r;

    // reconstruct world position
    vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
    view_pos.xyz /= view_pos.w;
    vec3 world_pos = (INV_VIEW_MATRIX * view_pos).xyz;

    // compute camera position
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    // vector to flashlight
    vec3 to_flash = flash_pos - world_pos;
    float dist = length(to_flash);
    vec3 to_flash_n = normalize(to_flash);

    // cone angle mask
    float cone_dot = dot(normalize(flash_dir), to_flash_n);
    float cone_cos = cos(flash_angle * 0.5);
    float inside = smoothstep(cone_cos - edge_softness, cone_cos + edge_softness, cone_dot);

    // distance falloff
    float dist_falloff = clamp(1.0 - dist / cone_range, 0.0, 1.0);
    float influence = inside * dist_falloff;

    // resonance detection: if object's hue ≈ complementary hue
    float obj_hue = get_hue(col);
    float target_hue = get_target_hue(vision_mode);
    float hue_diff = abs(obj_hue - target_hue);
    hue_diff = min(hue_diff, 1.0 - hue_diff); // circular wrap

    float resonance = smoothstep(resonance_tolerance, 0.0, hue_diff);

    // apply brightness resonance where cone overlaps
    vec3 final_col = col;
    float boost = hue_boost * influence * resonance;
    final_col *= (1.0 + boost);

    // absorb light (remove filtered channels)
    if (vision_mode == 0) { final_col.g *= 0.0; final_col.b *= 0.0; }
    else if (vision_mode == 1) { final_col.r *= 0.0; final_col.g *= 0.0; }
    else if (vision_mode == 2) { final_col.r *= 0.0; final_col.b *= 0.0; }

    final_col = clamp(final_col, 0.0, 1.0);
    ALBEDO = final_col;
}
