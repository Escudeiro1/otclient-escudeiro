// Eagle - same family as EPX/Scale2x (epx.frag), but each corner rule also
// checks the diagonal neighbour, not just the two orthogonal ones. Slightly
// different staircase pattern on diagonals than EPX; still a hard pixel
// replacement, no gradient blending - "cleaner corner handling than EPX,
// but still clearly pixel-ish up close."
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

#define EAGLE_TOLERANCE 0.06

bool sameColor(vec3 a, vec3 b) {
    return all(lessThan(abs(a - b), vec3(EAGLE_TOLERANCE)));
}

void main() {
    float dx = u_MapZoom / u_Resolution.x;
    float dy = u_MapZoom / u_Resolution.y;

    vec4 centerSample = texture2D(u_Tex0, v_TexCoord);
    vec3 E = centerSample.rgb;
    vec3 A = texture2D(u_Tex0, v_TexCoord + vec2(-dx, -dy)).rgb; // up-left
    vec3 B = texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -dy)).rgb; // up
    vec3 C = texture2D(u_Tex0, v_TexCoord + vec2( dx, -dy)).rgb; // up-right
    vec3 D = texture2D(u_Tex0, v_TexCoord + vec2(-dx,  0.0)).rgb; // left
    vec3 F = texture2D(u_Tex0, v_TexCoord + vec2( dx,  0.0)).rgb; // right
    vec3 G = texture2D(u_Tex0, v_TexCoord + vec2(-dx,  dy)).rgb; // down-left
    vec3 H = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  dy)).rgb; // down
    vec3 I = texture2D(u_Tex0, v_TexCoord + vec2( dx,  dy)).rgb; // down-right

    vec2 fp = fract(v_TexCoord / vec2(dx, dy));

    vec3 result = E;
    if (fp.x < 0.5 && fp.y < 0.5) {
        if (sameColor(D, B) && sameColor(D, A)) result = D;
    } else if (fp.x >= 0.5 && fp.y < 0.5) {
        if (sameColor(B, F) && sameColor(B, C)) result = B;
    } else if (fp.x < 0.5 && fp.y >= 0.5) {
        if (sameColor(H, D) && sameColor(H, G)) result = H;
    } else {
        if (sameColor(F, H) && sameColor(F, I)) result = F;
    }

    gl_FragColor = vec4(result, centerSample.a);
}
