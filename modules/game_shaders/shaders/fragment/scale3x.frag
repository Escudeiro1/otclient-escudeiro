// Scale3x (AdvMAME3x) - same algorithm family as EPX/Eagle, but a genuinely
// different, 3x-specific rule: divides each source texel into a 3x3 grid of
// 9 output sub-pixels (instead of EPX/Eagle's 2x2), each independently
// replaced with an orthogonal neighbour or left as the center color. Still
// a hard replacement, no gradient blending - "similar family to EPX,
// slightly cleaner corner handling, but still clearly pixel-ish up close."
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

#define SCALE3X_TOLERANCE 0.06

bool sameColor(vec3 a, vec3 b) {
    return all(lessThan(abs(a - b), vec3(SCALE3X_TOLERANCE)));
}

void main() {
    float dx = u_MapZoom / u_Resolution.x;
    float dy = u_MapZoom / u_Resolution.y;

    vec4 centerSample = texture2D(u_Tex0, v_TexCoord);
    vec3 E = centerSample.rgb;
    vec3 A = texture2D(u_Tex0, v_TexCoord + vec2(-dx, -dy)).rgb;
    vec3 B = texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -dy)).rgb;
    vec3 C = texture2D(u_Tex0, v_TexCoord + vec2( dx, -dy)).rgb;
    vec3 D = texture2D(u_Tex0, v_TexCoord + vec2(-dx,  0.0)).rgb;
    vec3 F = texture2D(u_Tex0, v_TexCoord + vec2( dx,  0.0)).rgb;
    vec3 G = texture2D(u_Tex0, v_TexCoord + vec2(-dx,  dy)).rgb;
    vec3 H = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  dy)).rgb;
    vec3 I = texture2D(u_Tex0, v_TexCoord + vec2( dx,  dy)).rgb;

    vec2 fp = fract(v_TexCoord / vec2(dx, dy));
    ivec2 cell = ivec2(clamp(floor(fp * 3.0), 0.0, 2.0));

    vec3 result = E;
    bool bh = !sameColor(B, H);
    bool df = !sameColor(D, F);

    if (bh && df) {
        if (cell == ivec2(0, 0)) {
            if (sameColor(D, B)) result = D;
        } else if (cell == ivec2(1, 0)) {
            if ((sameColor(D, B) && !sameColor(E, C)) || (sameColor(B, F) && !sameColor(E, A))) result = B;
        } else if (cell == ivec2(2, 0)) {
            if (sameColor(B, F)) result = F;
        } else if (cell == ivec2(0, 1)) {
            if ((sameColor(D, B) && !sameColor(E, G)) || (sameColor(D, H) && !sameColor(E, A))) result = D;
        } else if (cell == ivec2(2, 1)) {
            if ((sameColor(B, F) && !sameColor(E, I)) || (sameColor(H, F) && !sameColor(E, C))) result = F;
        } else if (cell == ivec2(0, 2)) {
            if (sameColor(D, H)) result = D;
        } else if (cell == ivec2(1, 2)) {
            if ((sameColor(D, H) && !sameColor(E, I)) || (sameColor(H, F) && !sameColor(E, G))) result = H;
        } else if (cell == ivec2(2, 2)) {
            if (sameColor(H, F)) result = F;
        }
        // center cell (1,1) always stays E, matching the reference rule.
    }

    gl_FragColor = vec4(result, centerSample.a);
}
