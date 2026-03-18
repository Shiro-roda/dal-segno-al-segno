shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform sampler2D TEXTURE;
uniform vec3 text_color;

uniform float glitch_strength = 3.0;
uniform float glitch_speed = 30.0;

float hash(vec2 p){
    return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);
}

void fragment(){

    vec2 uv = UV;

    float t = floor(TIME * glitch_speed);

    float block = floor(uv.y * 40.0);

    float offset =
        (hash(vec2(t,block))-.5)
        *glitch_strength
        *0.03;

    uv.x += offset;

    float alpha = texture(TEXTURE,uv).a;

    if(alpha < .2) discard;

    float flicker =
        sin(TIME*50.0+uv.y*20.0)*.5+.5;

    ALBEDO = text_color * (1.5 + flicker);

    EMISSION = text_color * 2.5;

    ALPHA = alpha;
}
