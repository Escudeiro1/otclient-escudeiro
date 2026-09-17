// xBR level 3 ("corner C" / default corner_type=3 variant): a wider, more
// accurate refinement of xbr.frag's lv2. Adds two extra diagonal angles
// (15/75 degrees, on top of lv2's 30/45/60) and a smoothstep-based blend
// curve instead of lv2's linear clamp, for noticeably smoother curved edges
// at the cost of a bit more math per fragment (still one pass, same 21
// texture samples as lv2 - the extra 15/75 terms reuse i4/i5/h5 via swizzles,
// no new samples needed).
//
// Ported from Hyllian's xBR-lv3 shader (Copyright 2011-2015 Hyllian,
// MIT-style license):
// https://github.com/libretro/glsl-shaders/blob/master/xbr/shaders/xbr-lv3.glsl
//
// See xbr.frag for the two engine-specific adaptations this also needs:
// (1) neighbour offsets/sub-pixel position computed inline from
// u_MapZoom/u_Resolution instead of a vertex-shader precompute step and an
// explicit source-texture-size uniform; (2) XBR_NOISE_THRESHOLD replacing
// the reference's bit-exact notEqual() checks, which fire on pure bilinear-
// filtering interpolation noise under this client's "Smooth Retro" mode.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

#define XBR_EQ_THRESHOLD 10.0
#define XBR_EQ_THRESHOLD2 2.0
#define XBR_NOISE_THRESHOLD 4.0
#define XBR_LV2_COEFFICIENT 2.0

const vec3 rgbw = vec3(14.352, 28.176, 5.472);
const vec4 delta = vec4(0.4);

vec4 df(vec4 a, vec4 b) {
    return abs(a - b);
}

bvec4 eqv(vec4 a, vec4 b) {
    return lessThan(df(a, b), vec4(XBR_EQ_THRESHOLD));
}

bvec4 eq2v(vec4 a, vec4 b) {
    return lessThan(df(a, b), vec4(XBR_EQ_THRESHOLD2));
}

bvec4 neqNoiseTol(vec4 a, vec4 b) {
    return greaterThan(df(a, b), vec4(XBR_NOISE_THRESHOLD));
}

bvec4 andv(bvec4 a, bvec4 b) {
    return bvec4(a.x && b.x, a.y && b.y, a.z && b.z, a.w && b.w);
}

bvec4 orv(bvec4 a, bvec4 b) {
    return bvec4(a.x || b.x, a.y || b.y, a.z || b.z, a.w || b.w);
}

vec4 weighted_distance(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h) {
    return df(a, b) + df(a, c) + df(d, e) + df(d, f) + 4.0 * df(g, h);
}

float c_df(vec3 c1, vec3 c2) {
    vec3 d = abs(c1 - c2);
    return d.r + d.g + d.b;
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

    vec4 c1 = i4.yzwx;
    vec4 g0 = i5.wxyz;
    vec4 b1 = h5.zwxy;
    vec4 d0 = h5.wxyz;

    const vec4 Ao = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 Bo = vec4( 1.0,  1.0, -1.0,-1.0);
    const vec4 Co = vec4( 1.5,  0.5, -0.5, 0.5);
    const vec4 Ax = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 Bx = vec4( 0.5,  2.0, -0.5,-2.0);
    const vec4 Cx = vec4( 1.0,  1.0, -0.5, 0.0);
    const vec4 Ay = vec4( 1.0, -1.0, -1.0, 1.0);
    const vec4 By = vec4( 2.0,  0.5, -2.0,-0.5);
    const vec4 Cy = vec4( 2.0,  0.0, -1.0, 0.5);

    const vec4 Az = vec4( 6.0, -2.0, -6.0, 2.0);
    const vec4 Bz = vec4( 2.0,  6.0, -2.0,-6.0);
    const vec4 Cz = vec4( 5.0,  3.0, -3.0,-1.0);
    const vec4 Aw = vec4( 2.0, -6.0, -2.0, 6.0);
    const vec4 Bw = vec4( 6.0,  2.0, -6.0,-2.0);
    const vec4 Cw = vec4( 5.0, -1.0, -3.0, 3.0);

    vec4 fx       = Ao * fp.y + Bo * fp.x;
    vec4 fx_left  = Ax * fp.y + Bx * fp.x;
    vec4 fx_up    = Ay * fp.y + By * fp.x;
    vec4 fx3_left = Az * fp.y + Bz * fp.x;
    vec4 fx3_up   = Aw * fp.y + Bw * fp.x;

    // corner_type 3 (the reference's default "else" branch - CORNER_C).
    bvec4 interp_restriction_lv1 = andv(
        andv(neqNoiseTol(e, f), neqNoiseTol(e, h)),
        orv(
            orv(andv(not(eqv(f, b)), not(eqv(f, c))), andv(not(eqv(h, d)), not(eqv(h, g)))),
            orv(
                andv(eqv(e, i), orv(andv(not(eqv(f, f4)), not(eqv(f, i4))), andv(not(eqv(h, h5)), not(eqv(h, i5))))),
                orv(eqv(e, g), eqv(e, c))
            )
        )
    );

    bvec4 interp_restriction_lv2_left = andv(neqNoiseTol(e, g), neqNoiseTol(d, g));
    bvec4 interp_restriction_lv2_up   = andv(neqNoiseTol(e, c), neqNoiseTol(b, c));
    bvec4 interp_restriction_lv3_left = andv(eq2v(g, g0), not(eq2v(d0, g0)));
    bvec4 interp_restriction_lv3_up   = andv(eq2v(c, c1), not(eq2v(b1, c1)));

    vec4 fx45 = smoothstep(Co - delta, Co + delta, fx);
    vec4 fx30 = smoothstep(Cx - delta, Cx + delta, fx_left);
    vec4 fx60 = smoothstep(Cy - delta, Cy + delta, fx_up);
    vec4 fx15 = smoothstep(Cz - delta, Cz + delta, fx3_left);
    vec4 fx75 = smoothstep(Cw - delta, Cw + delta, fx3_up);

    bvec4 edr = andv(lessThan(weighted_distance(e, c, g, i, h5, f4, h, f), weighted_distance(h, d, i5, f, i4, b, e, i)), interp_restriction_lv1);
    bvec4 edr_left = andv(lessThanEqual(XBR_LV2_COEFFICIENT * df(f, g), df(h, c)), interp_restriction_lv2_left);
    bvec4 edr_up   = andv(greaterThanEqual(df(f, g), XBR_LV2_COEFFICIENT * df(h, c)), interp_restriction_lv2_up);
    bvec4 edr3_left = interp_restriction_lv3_left;
    bvec4 edr3_up   = interp_restriction_lv3_up;

    bvec4 nc45 = andv(edr, bvec4(fx45));
    bvec4 nc30 = andv(edr, andv(edr_left, bvec4(fx30)));
    bvec4 nc60 = andv(edr, andv(edr_up, bvec4(fx60)));
    bvec4 nc15 = andv(andv(edr, edr_left), andv(edr3_left, bvec4(fx15)));
    bvec4 nc75 = andv(andv(edr, edr_up), andv(edr3_up, bvec4(fx75)));

    bvec4 px = lessThanEqual(df(e, f), df(e, h));

    bvec4 nc = bvec4(
        nc75.x || nc15.x || nc30.x || nc60.x || nc45.x,
        nc75.y || nc15.y || nc30.y || nc60.y || nc45.y,
        nc75.z || nc15.z || nc30.z || nc60.z || nc45.z,
        nc75.w || nc15.w || nc30.w || nc60.w || nc45.w
    );

    vec4 final45 = vec4(nc45) * fx45;
    vec4 final30 = vec4(nc30) * fx30;
    vec4 final60 = vec4(nc60) * fx60;
    vec4 final15 = vec4(nc15) * fx15;
    vec4 final75 = vec4(nc75) * fx75;

    vec4 maximo = max(max(max(final15, final75), max(final30, final60)), final45);

    vec3 pix1 = E, pix2 = E;
    float blend1 = 0.0, blend2 = 0.0;

    if (nc.x)      { pix1 = px.x ? F : H; blend1 = maximo.x; }
    else if (nc.y) { pix1 = px.y ? B : F; blend1 = maximo.y; }
    else if (nc.z) { pix1 = px.z ? D : B; blend1 = maximo.z; }
    else if (nc.w) { pix1 = px.w ? H : D; blend1 = maximo.w; }

    if (nc.w)      { pix2 = px.w ? H : D; blend2 = maximo.w; }
    else if (nc.z) { pix2 = px.z ? D : B; blend2 = maximo.z; }
    else if (nc.y) { pix2 = px.y ? B : F; blend2 = maximo.y; }
    else if (nc.x) { pix2 = px.x ? F : H; blend2 = maximo.x; }

    vec3 res1 = mix(E, pix1, blend1);
    vec3 res2 = mix(E, pix2, blend2);
    vec3 res = mix(res1, res2, step(c_df(E, res1), c_df(E, res2)));

    gl_FragColor = vec4(res, E4.a);
}
