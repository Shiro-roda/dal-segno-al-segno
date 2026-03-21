shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform sampler2D TEXTURE;
uniform vec3 text_color;

void fragment(){

    float base =
        texture(TEXTURE,UV).a;

    float ghost1 =
        texture(TEXTURE,
        UV+vec2(.02,0)).a;

    float ghost2 =
        texture(TEXTURE,
        UV-vec2(.02,0)).a;

    float combined =
        max(base,
        max(ghost1*.6,
        ghost2*.4));

    if(combined < .05)
        discard;

    float drift =
        sin(TIME*2.0+UV.x*30.0)*.2;

    vec3 col =
        text_color *
        (0.8 + drift);

    ALBEDO = col;

    EMISSION = col * 2.0;

    ALPHA = combined;
}
