shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 tint_color : source_color = vec3(0.02, 0.02, 0.02);
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    ALBEDO = tint_color;
    METALLIC = 1.0;
    ROUGHNESS = 0.05;
    SPECULAR = reflection_strength; // Cap reflection intensity
}