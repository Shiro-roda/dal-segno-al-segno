shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform sampler2D TEXTURE;
uniform vec3 text_color;

uniform float pulse_speed = 1.2;

void fragment(){

    float alpha =
        texture(TEXTURE,UV).a;

    if(alpha < .1) discard;

    float breath =
        sin(TIME*pulse_speed)*.5+.5;

    float wave =
        sin(UV.y*20.0+TIME*2.0)*.2;

    vec3 col =
        text_color *
        (0.6 + breath*0.8 + wave);

    ALBEDO = col;

    EMISSION = col * 1.5;

    ALPHA = alpha;
}
