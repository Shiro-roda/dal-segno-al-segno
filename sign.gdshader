shader_type spatial;
render_mode unshaded; // keep or remove depending on lighting needs

// reactive flash params (set from your code)
uniform int vision_mode = 0;        // 0=C,1=M,2=Y
uniform vec3 flash_pos = vec3(0.0);
uniform vec3 flash_dir = vec3(0.0, 0.0, -1.0);
uniform float flash_angle = 0.5;    // radians
uniform float cone_range = 20.0;    // meters
uniform float edge_softness = 0.02;
uniform float hue_match_boost = 3.0;
uniform float resonance_tolerance = 0.12;

// use material color by default; if using a texture, set use_texture = 1 and provide an albedo texture
uniform bool use_texture = false;
uniform sampler2D albedo_tex;
uniform vec3 base_color : source_color = vec3(1.0);

// varyings to pass world-space position (computed per-vertex)
varying vec3 v_world_pos;

float get_hue(vec3 c){
    float cmax = max(c.r, max(c.g, c.b));
    float cmin = min(c.r, min(c.g, c.b));
    float d = cmax - cmin;
    if (d < 1e-5) return 0.0;
    float h;
    if (cmax == c.r) h = mod((c.g - c.b) / d, 6.0);
    else if (cmax == c.g) h = ((c.b - c.r) / d) + 2.0;
    else h = ((c.r - c.g) / d) + 4.0;
    h /= 6.0;
    if (h < 0.0) h += 1.0;
    return h;
}

float get_target_hue(int mode){
    if (mode == 0) return 0.0 / 6.0; // red for cyan filter
    if (mode == 1) return 2.0 / 6.0; // green for magenta filter
    if (mode == 2) return 4.0 / 6.0; // blue for yellow filter
    return 0.0;
}

// vertex stage: compute world position
void vertex() {
    v_world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment(){
    // get object's base color (optionally sample albedo texture)
    vec3 obj_color = base_color;
    if (use_texture) {
        // if your mesh uses UVs and a texture, uncomment and set use_texture=1 on material
        obj_color = texture(albedo_tex, UV).rgb;
    }

    // vector from object point to flashlight position
    vec3 to_flash = flash_pos - v_world_pos;
    float dist = length(to_flash);
    vec3 to_flash_n = normalize(to_flash);

    // cone angle test
    float cone_dot = dot(normalize(flash_dir), to_flash_n);
    float cone_cos = cos(flash_angle * 0.5);
    float cone_mask = smoothstep(cone_cos - edge_softness, cone_cos + edge_softness, cone_dot);

    // distance falloff
    float dist_falloff = clamp(1.0 - dist / cone_range, 0.0, 1.0);
    float influence = cone_mask * dist_falloff;

    // hue resonance check
    float obj_hue = get_hue(obj_color);
    float target_hue = get_target_hue(vision_mode);
    float hue_diff = abs(obj_hue - target_hue);
    hue_diff = min(hue_diff, 1.0 - hue_diff); // circular wrap
    float resonance = smoothstep(resonance_tolerance, 0.0, hue_diff);

    // intensity and glow
    float intensity = influence * resonance * hue_match_boost;

    // Construct glow (emission) and boosted albedo
    vec3 boosted = obj_color * (1.0 + intensity);
    vec3 emission_col = obj_color * intensity;

    // Final outputs
    ALBEDO = clamp(boosted, 0.0, 1.0);
    EMISSION = clamp(emission_col, 0.0, 10.0); // EMISSION can be >1 for HDR/bloom
}
