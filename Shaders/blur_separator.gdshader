shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 10.0) = 4.0;
uniform float spread : hint_range(0.0, 0.1) = 0.02;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.4; // Higher = softer fade

void fragment() {
    // 1. Sample both sides
    vec2 left_uv = SCREEN_UV - vec2(spread, 0.0);
    vec2 right_uv = SCREEN_UV + vec2(spread, 0.0);
    vec4 left_side = textureLod(screen_texture, left_uv, blur_amount);
    vec4 right_side = textureLod(screen_texture, right_uv, blur_amount);
    
    // 2. Linear blend across the width
    vec4 blended_color = mix(left_side, right_side, UV.x);
    
    // 3. Create a smooth alpha mask for ALL edges
    // Fades out top/bottom and left/right based on 'edge_softness'
    
    float h_mask = smoothstep(0.0, edge_softness, UV.x) * smoothstep(1.0, 1.0 - edge_softness, UV.x);
    
    // 4. Combine mask and color
    COLOR = vec4(blended_color.rgb, h_mask);
}
