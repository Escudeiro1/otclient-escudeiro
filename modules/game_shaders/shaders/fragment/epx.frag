// EPX (Eric's Pixel Expansion) - also independently discovered as Scale2x and
// AdvMAME2x; these three names refer to the exact same algorithm. Cheapest
// of the pixel-art scalers here: only reads the 4 orthogonal neighbours (no
// diagonals), and each output sub-pixel is a hard replacement with a
// neighbour's color or the original - no blending, no gradients. Produces a
// simple 2-step "staircase" on diagonal edges: a real improvement over raw
// nearest-neighbour blockiness, but still clearly a hard-edged result up
// close (unlike xBR's smooth diagonal blend).
//
// The original algorithm is defined for exact color equality, which assumes
// crisp nearest-filtered source art. Adapted here (same lesson as xbr.frag)
// with a small tolerance instead of exact equality, since "Smooth Retro"
// bilinear filtering means two samples are almost never bit-identical even
// in a flat-colored area.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

// Per-channel tolerance in normalized (0-1) color space, ~15/255. Same
// purpose as xbr.frag's XBR_NOISE_THRESHOLD: absorbs bilinear-filtering
// interpolation noise without merging genuinely different colors.
#define EPX_TOLERANCE 0.06

bool sameColor(vec3 a, vec3 b) {
    return all(lessThan(abs(a - b), vec3(EPX_TOLERANCE)));
}

void main() {
    float dx = u_MapZoom / u_Resolution.x;
    float dy = u_MapZoom / u_Resolution.y;

    vec4 centerSample = texture2D(u_Tex0, v_TexCoord);
    vec3 E = centerSample.rgb;
    vec3 B = texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -dy)).rgb; // up
    vec3 D = texture2D(u_Tex0, v_TexCoord + vec2(-dx,  0.0)).rgb; // left
    vec3 F = texture2D(u_Tex0, v_TexCoord + vec2( dx,  0.0)).rgb; // right
    vec3 H = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  dy)).rgb; // down

    vec2 fp = fract(v_TexCoord / vec2(dx, dy));

    // Which quadrant of the source texel this fragment falls into decides
    // which pair of orthogonal neighbours applies (classic EPX is only ever
    // defined for a fixed 2x2 output grid; fp lets this work at any zoom).
    vec3 result = E;
    if (fp.x < 0.5 && fp.y < 0.5) {
        // top-left
        if (sameColor(D, B) && !sameColor(D, H) && !sameColor(B, F)) result = D;
    } else if (fp.x >= 0.5 && fp.y < 0.5) {
        // top-right
        if (sameColor(B, F) && !sameColor(B, D) && !sameColor(F, H)) result = F;
    } else if (fp.x < 0.5 && fp.y >= 0.5) {
        // bottom-left
        if (sameColor(D, H) && !sameColor(D, B) && !sameColor(H, F)) result = D;
    } else {
        // bottom-right
        if (sameColor(H, F) && !sameColor(H, D) && !sameColor(F, B)) result = F;
    }

    gl_FragColor = vec4(result, centerSample.a);
}
