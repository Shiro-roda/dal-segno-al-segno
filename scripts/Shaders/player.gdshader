shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;

uniform vec3 cone_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float absorption_strength : hint_range(0.0, 1.0) = 1.0;
uniform int vision_mode = 0; // 0=C, 1=M, 2=Y

vec3 absorb(vec3 c, int mode){
    if (mode == 0) { // Cyan eyes — absorb green+blue
        c.g = 0.0;
        c.b = 0.0;
    } else if (mode == 1) { // Magenta eyes — absorb red+green
        c.r = 0.0;
        c.g = 0.0;
    } else if (mode == 2) { // Yellow eyes — absorb red+blue
        c.r = 0.0;
        c.b = 0.0;
    }
    return c;
}

void fragment(){
    vec3 base = cone_color;
    vec3 filtered = absorb(base, vision_mode);
    ALBEDO = mix(base, filtered, absorption_strength);
    ALPHA = 0.9; // semi-transparent
}
