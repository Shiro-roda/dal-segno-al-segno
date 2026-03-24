shader_type canvas_item;
render_mode unshaded;

uniform float sync_jitter_px : hint_range(0.0, 20.0) = 4.0;
uniform float sync_speed     : hint_range(0.1, 50.0) = 50.0;
uniform float interlace_px   : hint_range(0.0, 12.0) = 1.0;
uniform float noise_amount   : hint_range(0.0, 1.0)  = 0.05;
uniform float active         : hint_range(0.0, 1.0)  = 1.0;

uniform vec4  font_color   : source_color = vec4(1.0);
uniform vec4  shadow_color : source_color = vec4(0.0,0.0,0.0,0.72);

uniform vec2 shadow_offset = vec2(3.0, 3.0);



float hash(vec2 p){
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}



void fragment() {

    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;

    // --- Horizontal sync roll ---
    float t_step   = mod(floor(TIME * sync_speed), 997.0);
    float sync_rnd = hash(vec2(t_step, 0.0));
    float sync_off = (sync_rnd * 2.0 - 1.0) * sync_jitter_px * active;

    // --- Interlace ---
    float scanline  = floor(UV.y * screen_size.y);
    float field     = mod(scanline,2.0);
    float ilace_off = interlace_px * (field * 2.0 - 1.0) * active;

    float total_offset = (sync_off + ilace_off) * SCREEN_PIXEL_SIZE.x;

    // Main UV
    vec2 shifted_uv = clamp(UV + vec2(total_offset,0.0), vec2(0.0), vec2(1.0));

    // Shadow UV
	vec2 shadow_uv = clamp(
	    UV - shadow_offset * SCREEN_PIXEL_SIZE + vec2(total_offset, 0.0),
	    vec2(0.0),
	    vec2(1.0)
	);
    float glyph        = texture(TEXTURE, shifted_uv).a;
    float shadow_glyph = texture(TEXTURE, shadow_uv).a;

    // --- Pixel noise ---
    // Modulo keeps seed small so hash stays well-distributed at large TIME.
    float noise_t = mod(floor(TIME * 60.0), 1000.0);

    vec2 pixel = floor(UV * screen_size);
    float rnd  = hash(pixel + vec2(noise_t, noise_t * 0.37));

    float pixel_on = step(noise_amount * active, rnd);

    float main_alpha   = glyph * pixel_on;
    float shadow_alpha = shadow_glyph;

    vec4 text_col = font_color;
    vec4 shad_col = shadow_color;

    // Composite
    vec4 result = vec4(0.0);

    result += shad_col * shadow_alpha;
    result = mix(result, text_col, main_alpha);

    COLOR = result;
}