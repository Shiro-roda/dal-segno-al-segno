shader_type spatial;
render_mode unshaded, depth_draw_always;

uniform sampler2D screen_tex : hint_screen_texture;
uniform sampler2D depth_tex : hint_depth_texture;

uniform int vision_mode = 0;        // 0=C,1=M,2=Y
uniform vec3 flash_pos = vec3(0.0);
uniform vec3 flash_dir = vec3(0.0, 0.0, -1.0);
uniform float flash_angle = 0.5;   // radians
uniform float hue_boost = 10.0;     // resonance multiplier
uniform float cone_range = 20.0;   // distance falloff range (meters)
uniform float edge_softness = 0.05; // small for hard edge

vec3 absorb(vec3 c, int mode){
    if(mode==0){ c.g = 0.0; c.b = 0.0; }      // cyan -> red
    else if(mode==1){ c.r = 0.0; c.g = 0.0; } // magenta -> blue
    else if(mode==2){ c.r = 0.0; c.b = 0.0; } // yellow -> green
    return c;
}

void fragment(){
    // read scene color + depth
    vec3 col = texture(screen_tex, SCREEN_UV).rgb;
    float depth = texture(depth_tex, SCREEN_UV).r;

    // reconstruct world position
    vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
    view_pos.xyz /= view_pos.w;
    vec3 world_pos = (INV_VIEW_MATRIX * view_pos).xyz;

    // compute camera position from inv view matrix
    vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    // vector from world pixel to flashlight and distance
    vec3 to_flash = flash_pos - world_pos;
    float dist = length(to_flash);
    vec3 to_flash_n = normalize(to_flash);

    // angle test using dot(cos)
    float cone_dot = dot(normalize(flash_dir), to_flash_n);
    // cos of half-angle for a sharper cutoff
    float cone_cos = cos(flash_angle * 0.5);

    // edge falloff (use smoothstep near the boundary for slight softness)
    float inside = smoothstep(cone_cos - edge_softness, cone_cos + edge_softness, cone_dot);

    // determine whether the light is between camera and the point:
    // test whether the flash position projects in front of the camera relative to the world_pos
    // i.e. dot( (flash_pos - cam_pos), (world_pos - cam_pos) ) > 0  -> flash is on same side as world_pos
    float cam_side = dot(flash_pos - cam_pos, world_pos - cam_pos);
    float flash_between = step(0.0, cam_side); // 1 when flash is on the same side of the world_pos as camera (simple test)

    // distance falloff for volumetric feel
    float dist_falloff = clamp(1.0 - (dist / cone_range), 0.0, 1.0);

    // final influence mask
    float influence = inside * flash_between * dist_falloff;

    // build filtered/resonant color
    vec3 filtered = absorb(col, vision_mode);

    // amplify the target channel when inside
    if (influence > 0.001) {
        if (vision_mode == 0) { filtered.r *= hue_boost; } // cyan -> red boost
        else if (vision_mode == 1) { filtered.b *= hue_boost; } // magenta -> blue boost
        else if (vision_mode == 2) { filtered.g *= hue_boost; } // yellow -> green boost
    }

    filtered = clamp(filtered, 0.0, 1.0);

	   // --- inside cone: consume all light ---
	vec3 void_col = vec3(0.0); // absolute black void
	vec3 out_col = mix(col, void_col, influence);

	ALBEDO = out_col;

}
