shader_type canvas_item;
render_mode unshaded;

uniform float flicker_speed : hint_range(0.1, 20.0) = 4.0;
uniform float pixel_size : hint_range(1.0, 50.0) = 8.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 font_color   : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Integer pixel-grid steps for shadow offset
uniform vec2 shadow_pixel_steps = vec2(1.0, -1.0);
// CRT interlace jitter: magnitude in screen pixels (0 = off)
uniform float interlace_jitter : hint_range(0.0, 8.0) = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float flicker_on(vec2 pix, float speed, float intensity) {
    float phase   = hash(pix);
    float rate    = 0.5 + hash(pix + vec2(7.3, 13.7));
    float t_frame = floor(TIME * speed * rate + phase * 97.3);
    float rnd     = hash(pix + vec2(t_frame * 0.1371, t_frame * 0.7913));
    return step(intensity, rnd);
}

void fragment() {
    // --- CRT interlace jitter ---
    // Alternate scanlines are horizontally displaced by interlace_jitter pixels.
    // Magnitude is animated so it decays naturally when set from GDScript.
    vec2 jitter_uv = UV;
    if (interlace_jitter > 0.001) {
        float screen_h = 1.0 / SCREEN_PIXEL_SIZE.y;
        float scanline  = floor(UV.y * screen_h);
        float field     = mod(scanline, 2.0);  // 0 or 1 per line
        float jitter_px = interlace_jitter * (field * 2.0 - 1.0);  // +/- per field
        jitter_uv.x += jitter_px * SCREEN_PIXEL_SIZE.x;
        jitter_uv = clamp(jitter_uv, vec2(0.0), vec2(1.0));
    }

    // Glyph mask — canvas_item TEXTURE alpha gives exact letter shape
    float glyph = texture(TEXTURE, jitter_uv).a;

    // Pixelate in screen-pixel space using SCREEN_PIXEL_SIZE
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 pix_uv = floor(UV * screen_size / pixel_size);

    // --- Text flicker ---
    float on = flicker_on(pix_uv, flicker_speed, flicker_intensity) * glyph;

    // --- Shadow flicker ---
    vec2 src_pix_uv    = pix_uv - floor(shadow_pixel_steps);
    vec2 src_uv        = (src_pix_uv * pixel_size) / screen_size;
    float shadow_glyph = texture(TEXTURE, src_uv).a;
    float shadow_on    = flicker_on(src_pix_uv, flicker_speed, flicker_intensity) * shadow_glyph;

    // Text wins; shadow only where text is off at this pixel
    float use_shadow = (1.0 - step(0.5, on)) * shadow_on;

    // Discard fully blank pixels so nothing leaks into the CRT buffer
    if (on < 0.5 && use_shadow < 0.5) discard;

    // Output: text color preserved from TEXTURE RGB, shadow is flat color
    vec4 text_sample = texture(TEXTURE, jitter_uv);
    COLOR = on > 0.5 ? vec4(font_color.rgb, 1.0) : shadow_color;
}
