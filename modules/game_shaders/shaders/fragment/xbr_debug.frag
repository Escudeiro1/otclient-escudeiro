// Diagnostic variant of xbr.frag: instead of blending the reconstructed edge
// color, this paints a solid magenta over every fragment where the xBR
// edge-detection logic actually fired (any of the four diagonal blend rules
// triggered). Everything else passes through unmodified.
//
// Purpose: "Map - xBR" can look very subtle on Tibia's already-anti-aliased
// sprites even when working correctly, since it only touches true diagonal
// edges. This variant answers one yes/no question directly: is the detection
// logic firing at all? Solid magenta tracing sprite edges = yes, it's working
// (the base xBR filter is just subtle by nature here). No magenta anywhere =
// a real bug in the neighbour/texel-size math, not a matter of tuning.
//
// See xbr.frag for the full algorithm explanation; this file mirrors it.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

#define XBR_EQ_THRESHOLD 15.0
// See xbr.frag for why this exists: bilinear/"Smooth Retro" filtering means
// bit-exact float equality (what the reference shader uses for its base
// edge-existence checks) fires on pure interpolation noise almost
// everywhere. This is a tolerance-based replacement for that check.
#define XBR_NOISE_THRESHOLD 4.0
#define XBR_LV2_COEFFICIENT 2.0
#define XBR_SCALE 3.0

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

void main() {
    float dx = u_MapZoom / u_Resolution.x;
    float dy = u_MapZoom / u_Resolution.y;

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

    vec4 delta   = vec4(1.0 / XBR_SCALE);
    vec4 delta_l = vec4(0.5 / XBR_SCALE, 1.0 / XBR_SCALE, 0.5 / XBR_SCALE, 1.0 / XBR_SCALE);
    vec4 delta_u = delta_l.yxwz;

    vec4 fx   = Ao * fp.y + Bo * fp.x;
    vec4 fx_l = Ax * fp.y + Bx * fp.x;
    vec4 fx_u = Ay * fp.y + By * fp.x;

    vec4 irlv0 = neqNoiseTol(e, f) * neqNoiseTol(e, h);
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

    vec4 maximos = max(max(fx30, fx60), max(fx45, fx45i));
    float fired = max(max(maximos.x, maximos.y), max(maximos.z, maximos.w));

    vec3 debugColor = mix(E, vec3(1.0, 0.0, 1.0), step(0.001, fired));
    gl_FragColor = vec4(debugColor, E4.a);
}
