shader_type spatial;
render_mode unshaded, depth_draw_always;

uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D depth_tex : hint_depth_texture;
uniform sampler2D emission_tex; // Optional: emission capture if using SceneColor with HDR

uniform int vision_mode = 0;        // 0 = Cyan (red only), 1 = Magenta (blue only), 2 = Yellow (green only)
uniform vec3 flash_pos;
uniform vec3 flash_dir;
uniform float flash_angle;          // radians

vec3 absorb(vec3 c, int mode) {
    if (mode == 0) {                // Cyan eyes → red only
        c.g = 0.0; c.b = 0.0;
    } else if (mode == 1) {         // Magenta eyes → blue only
        c.r = 0.0; c.g = 0.0;
    } else if (mode == 2) {         // Yellow eyes → green only
        c.r = 0.0; c.b = 0.0;
    }
    return c;
}

void fragment() {
    vec3 col = texture(screen_tex, SCREEN_UV).rgb;
    float depth = texture(depth_tex, SCREEN_UV).r;
    vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
    vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
    view_pos.xyz /= view_pos.w;
    vec3 world_pos = (INV_VIEW_MATRIX * view_pos).xyz;

    vec3 to_pix = normalize(world_pos - flash_pos);
    float ang = acos(dot(flash_dir, to_pix));

    // Hard cone mask
    float inside = step(ang, flash_angle * 5.0);

    // --- Emission filtering (optional) ---
    vec3 emission_col = vec3(0.0);
    if (textureSize(emission_tex, 0).x > 0) {
        emission_col = texture(emission_tex, SCREEN_UV).rgb;
        emission_col = absorb(emission_col, vision_mode);
        col += emission_col * 0.5; // Blend emission into color
    }

    // --- Apply vision mode filtering ---
    vec3 filtered = absorb(col, vision_mode);
    ALBEDO = mix(col, filtered, inside);
}
