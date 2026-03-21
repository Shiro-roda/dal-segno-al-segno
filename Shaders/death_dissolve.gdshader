shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform float dissolve    : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

// Pixel sizes for each fragmentation stage (large -> small)
const float PS0 = 24.0;
const float PS1 = 12.0;
const float PS2 = 6.0;
const float PS3 =  3.0;


// dissolve thresholds at which each split occurs
const float T0 = 0.0;   // stage 0 starts immediately
const float T1 = 0.10;  // split to PS1 at 20%
const float T2 = 0.24;  // split to PS2 at 42%
const float T3 = 0.38;  // split to PS3 at 64%


float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    // Modulo keeps t small so hash inputs stay well-distributed.
    float t = mod(TIME + time_offset, 997.0);

    // Pick pixel size based on dissolve stage
    float ps;
    if      (dissolve < T1) ps = PS0;
    else if (dissolve < T2) ps = PS1;
    else if (dissolve < T3) ps = PS2;
    else                    ps = PS3;
	
    // Quantise fragment to current block grid
    vec2 pix = floor(FRAGCOORD.xy / ps) * ps;

    // Each block gets a stable random id seeded by position AND current stage
    // (so blocks reshuffle when the size splits — avoids same blocks always dying first)
    float stage_seed = ps * 0.01;
    float rnd = hash(pix * 0.01 + vec2(stage_seed, stage_seed * 7.3));

    // Remap dissolve into [0,1] within the current stage's window so each
    // stage fully dissolves its blocks before the next split begins.
    float stage_start;
    float stage_end;
    if      (dissolve < T1) { stage_start = T0; stage_end = T1; }
    else if (dissolve < T2) { stage_start = T1; stage_end = T2; }
    else if (dissolve < T3) { stage_start = T2; stage_end = T3; }
    else                    { stage_start = T3; stage_end = 1.0; }
    
    float local_d = (dissolve - stage_start) / (stage_end - stage_start);
    // Ease in so blocks hold longer at the start of each stage
    local_d = local_d * local_d;

    if (rnd < local_d) discard;

    // Technicolor: hue per block, cycling with time
    float hue_rnd = hash(pix * 0.037 + floor(t * 12.0) * vec2(0.1, 0.17));
    float hue = fract(hue_rnd + t * 0.35);

    // HSV -> RGB (S=1, V=1)
    vec3 col;
    float h6 = hue * 6.0;
    float f  = fract(h6);
    float q  = 1.0 - f;
    if      (h6 < 1.0) col = vec3(1.0, f,   0.0);
    else if (h6 < 2.0) col = vec3(q,   1.0, 0.0);
    else if (h6 < 3.0) col = vec3(0.0, 1.0, f  );
    else if (h6 < 4.0) col = vec3(0.0, q,   1.0);
    else if (h6 < 5.0) col = vec3(f,   0.0, 1.0);
    else               col = vec3(1.0, 0.0, q  );

    // Flicker brightness per block
    float brightness = 0.55 + 0.45 * hash(pix * 0.01 + floor(t * 28.0) * vec2(0.3, 0.7));
    col *= brightness;

    ALBEDO = col;
    ALPHA  = 1.0;
}
