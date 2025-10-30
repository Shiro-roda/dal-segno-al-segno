shader_type canvas_item;

uniform float glow_strength = 0.4;
uniform float fade = 0.3;
uniform vec3 tint_color = vec3(1.0, 0.95, 0.6);
uniform float vignette_radius = 0.8; // 0–1 range, bigger = wider vignette
uniform float vignette_softness = 0.5; // controls fade smoothness
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec4 col = texture(SCREEN_TEXTURE, SCREEN_UV);
    vec2 uv = SCREEN_UV * 2.0 - 1.0;
	float dist = length(uv);
    float vignette = smoothstep(vignette_radius, vignette_radius - vignette_softness, dist);
    col.rgb *= mix(1.0, vignette, 1.0); // darken edges
    col.rgb = mix(col.rgb, tint_color, fade);
    col.rgb += col.rgb * glow_strength;
    col.rgb *= vignette;
    COLOR = col;
}
