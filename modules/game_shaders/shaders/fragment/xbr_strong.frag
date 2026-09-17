// Same algorithm as xbr.frag (see that file for the full explanation), with
// the sensitivity constants turned up: a lower XBR_EQ_THRESHOLD means fewer
// neighbouring colors get classified as "equal", so more borderline cases
// trigger edge reconstruction; a lower XBR_LV2_COEFFICIENT makes the corner-
// rounding rule fire more readily. Exists to A/B against xbr.frag and gauge
// how much of "barely changed a thing" was the algorithm being correct-but-
// subtle on Tibia's already-anti-aliased sprites, versus needing retuning.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

#define XBR_EQ_THRESHOLD 6.0
// See xbr.frag for why this exists: bilinear/"Smooth Retro" filtering means
// bit-exact float equality (what the reference shader uses for its base
// edge-existence checks) fires on pure interpolation noise almost
// everywhere. This is a tolerance-based replacement for that check.
#define XBR_NOISE_THRESHOLD 4.0
#define XBR_LV2_COEFFICIENT 1.0
// See xbr.frag for why this exists: the reference's fixed fraction-of-texel
// blend width is under 1 screen pixel wide at this client's 2x "Smooth
// Retro" render scale. This expresses the target in real screen pixels.
#define XBR_BLEND_TARGET_PIXELS 3.0

const vec3 rgbw = vec3(14.352, 28.176, 5.472);

vec4 df(vec4 a, vec4 b) {
    return abs(a - b);
}

vec4 eqv(vec4 a, vec4 b) {
    return step(df(a, b), vec4(XBR_EQ_THRESHOLD));
}

vec4 neqv(vec4 a, vec4 b) {
    return vec4(1.0) - eqv(a, b);
}

vec4 neqNoiseTol(vec4 a, vec4 b) {
    return vec4(1.0) - step(df(a, b), vec4(XBR_NOISE_THRESHOLD));
}

vec4 wd(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h) {
    return df(a, b) + df(a, c) + df(d, e) + df(d, f) + 4.0 * df(g, h);
}

float c_df(vec3 c1, vec3 c2) {
    vec3 d = abs(c1 - c2);
    return d.r + d.g + d.b;
}

void main() {
    // UV-space size of exactly one source texel, derived from how many screen
    // pixels this draw call renders one texel at (u_MapZoom), not the sprite
    // atlas's own layout.
    float dx = u_MapZoom / u_Resolution.x;
    float dy = u_MapZoom / u_Resolution.y;

    // Tiny epsilon nudge (matches the reference shader) so a fragment landing
    // exactly on a texel boundary doesn't tie-break inconsistently.
    vec2 texCoord = v_TexCoord;
    texCoord.x *= 1.00000001;

    vec3 A1 = texture2D(u_Tex0, texCoord + vec2(-dx, -2.0 * dy)).rgb;
    vec3 B1 = texture2D(u_Tex0, texCoord + vec2( 0.0, -2.0 * dy)).rgb;
    vec3 C1 = texture2D(u_Tex0, texCoord + vec2( dx, -2.0 * dy)).rgb;

    vec3 A  = texture2D(u_Tex0, texCoord + vec2(-dx, -dy)).rgb;
    vec3 B  = texture2D(u_Tex0, texCoord + vec2( 0.0, -dy)).rgb;
    vec3 C  = texture2D(u_Tex0, texCoord + vec2( dx, -dy)).rgb;

    vec3 D  = texture2D(u_Tex0, texCoord + vec2(-dx, 0.0)).rgb;
    vec4 E4 = texture2D(u_Tex0, texCoord);
    vec3 E  = E4.rgb;
    vec3 F  = texture2D(u_Tex0, texCoord + vec2( dx, 0.0)).rgb;

    vec3 G  = texture2D(u_Tex0, texCoord + vec2(-dx, dy)).rgb;
    vec3 H  = texture2D(u_Tex0, texCoord + vec2( 0.0, dy)).rgb;
    vec3 I  = texture2D(u_Tex0, texCoord + vec2( dx, dy)).rgb;

    vec3 G5 = texture2D(u_Tex0, texCoord + vec2(-dx, 2.0 * dy)).rgb;
    vec3 H5 = texture2D(u_Tex0, texCoord + vec2( 0.0, 2.0 * dy)).rgb;
    vec3 I5 = texture2D(u_Tex0, texCoord + vec2( dx, 2.0 * dy)).rgb;

    vec3 A0 = texture2D(u_Tex0, texCoord + vec2(-2.0 * dx, -dy)).rgb;
    vec3 D0 = texture2D(u_Tex0, texCoord + vec2(-2.0 * dx, 0.0)).rgb;
    vec3 G0 = texture2D(u_Tex0, texCoord + vec2(-2.0 * dx, dy)).rgb;

    vec3 C4 = texture2D(u_Tex0, texCoord + vec2(2.0 * dx, -dy)).rgb;
    vec3 F4 = texture2D(u_Tex0, texCoord + vec2(2.0 * dx, 0.0)).rgb;
    vec3 I4 = texture2D(u_Tex0, texCoord + vec2(2.0 * dx, dy)).rgb;

    // Fractional position of this fragment within the source texel it falls
    // into - i.e. is this output pixel near the top-left, bottom-right, etc.
    // of the (much smaller) source pixel it's upscaling.
    vec2 fp = fract(texCoord / vec2(dx, dy));

    vec4 b = vec4(dot(B, rgbw), dot(D, rgbw), dot(H, rgbw), dot(F, rgbw));
    vec4 c = vec4(dot(C, rgbw), dot(A, rgbw), dot(G, rgbw), dot(I, rgbw));
    vec4 d = b.yzwx;
    vec4 e = vec4(dot(E, rgbw));
    vec4 f = b.wxyz;
    vec4 g = c.zwxy;
    vec4 h = b.zwxy;
    vec4 i = c.wxyz;

    vec4 i4 = vec4(dot(I4, rgbw), dot(C1, rgbw), dot(A0, rgbw), dot(G5, rgbw));
    vec4 i5 = vec4(dot(I5, rgbw), dot(C4, rgbw), dot(A1, rgbw), dot(G0, rgbw));
    vec4 h5 = vec4(dot(H5, rgbw), dot(F4, rgbw), dot(B1, rgbw), dot(D0, rgbw));
    vec4 f4 = h5.yzwx;

    const vec4 Ao = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 Bo = vec4( 1.0,  1.0, -1.0,-1.0);
    const vec4 Co = vec4( 1.5,  0.5, -0.5, 0.5);
    const vec4 Ax = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 Bx = vec4( 0.5,  2.0, -0.5,-2.0);
    const vec4 Cx = vec4( 1.0,  1.0, -0.5, 0.0);
    const vec4 Ay = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 By = vec4( 2.0,  0.5, -2.0,-0.5);
    const vec4 Cy = vec4( 2.0,  0.0, -1.0, 0.5);
    const vec4 Ci = vec4(0.25, 0.25, 0.25, 0.25);

    float xbrScale = (2.0 * u_MapZoom) / XBR_BLEND_TARGET_PIXELS;
    vec4 delta   = vec4(1.0 / xbrScale);
    vec4 delta_l = vec4(0.5 / xbrScale, 1.0 / xbrScale, 0.5 / xbrScale, 1.0 / xbrScale);
    vec4 delta_u = delta_l.yxwz;

    vec4 fx   = Ao * fp.y + Bo * fp.x;
    vec4 fx_l = Ax * fp.y + Bx * fp.x;
    vec4 fx_u = Ay * fp.y + By * fp.x;

    vec4 irlv0 = neqNoiseTol(e, f) * neqNoiseTol(e, h);
    // CORNER_C rule (the variant the reference ships enabled by default).
    vec4 irlv1 = irlv0 * (
        neqv(f, b) * neqv(f, c) + neqv(h, d) * neqv(h, g)
        + eqv(e, i) * (neqv(f, f4) * neqv(f, i4) + neqv(h, h5) * neqv(h, i5))
        + eqv(e, g) + eqv(e, c)
    );

    vec4 irlv2l = neqNoiseTol(e, g) * neqNoiseTol(d, g);
    vec4 irlv2u = neqNoiseTol(e, c) * neqNoiseTol(b, c);

    vec4 fx45i = clamp((fx   + delta   - Co - Ci) / (2.0 * delta),   0.0, 1.0);
    vec4 fx45  = clamp((fx   + delta   - Co)      / (2.0 * delta),   0.0, 1.0);
    vec4 fx30  = clamp((fx_l + delta_l - Cx)      / (2.0 * delta_l), 0.0, 1.0);
    vec4 fx60  = clamp((fx_u + delta_u - Cy)      / (2.0 * delta_u), 0.0, 1.0);

    vec4 wd1 = wd(e, c, g, i, h5, f4, h, f);
    vec4 wd2 = wd(h, d, i5, f, i4, b, e, i);

    vec4 edri  = step(wd1, wd2) * irlv0;
    vec4 edr   = step(wd1 + vec4(0.1), wd2) * step(vec4(0.5), irlv1);
    vec4 edr_l = step(XBR_LV2_COEFFICIENT * df(f, g), df(h, c)) * irlv2l * edr;
    vec4 edr_u = step(XBR_LV2_COEFFICIENT * df(h, c), df(f, g)) * irlv2u * edr;

    fx45  = edr   * fx45;
    fx30  = edr_l * fx30;
    fx60  = edr_u * fx60;
    fx45i = edri  * fx45i;

    vec4 px = step(df(e, f), df(e, h));

    // Reference's SMOOTH_TIPS path (default when CORNER_A isn't selected).
    vec4 maximos = max(max(fx30, fx60), max(fx45, fx45i));

    vec3 res1 = E;
    res1 = mix(res1, mix(H, F, px.x), maximos.x);
    res1 = mix(res1, mix(B, D, px.z), maximos.z);

    vec3 res2 = E;
    res2 = mix(res2, mix(F, B, px.y), maximos.y);
    res2 = mix(res2, mix(D, H, px.w), maximos.w);

    vec3 res = mix(res1, res2, step(c_df(E, res1), c_df(E, res2)));

    gl_FragColor = vec4(res, E4.a);
}
