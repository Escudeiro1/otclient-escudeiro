// Kuwahara filter - produces a smooth "plastic/painterly" look.
// Divides the 3x3 neighbourhood into 4 overlapping 2x2 quadrants,
// picks the quadrant with the lowest luminance variance, and outputs
// its mean colour. Flat areas become perfectly smooth; edges stay sharp.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;

float luma(vec4 c) {
    return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 p = 1.0 / u_Resolution;

    // 3x3 neighbourhood
    vec4 c  = texture2D(u_Tex0, v_TexCoord);
    vec4 n  = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  p.y));
    vec4 s  = texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -p.y));
    vec4 e  = texture2D(u_Tex0, v_TexCoord + vec2( p.x,  0.0));
    vec4 w  = texture2D(u_Tex0, v_TexCoord + vec2(-p.x,  0.0));
    vec4 ne = texture2D(u_Tex0, v_TexCoord + vec2( p.x,  p.y));
    vec4 nw = texture2D(u_Tex0, v_TexCoord + vec2(-p.x,  p.y));
    vec4 se = texture2D(u_Tex0, v_TexCoord + vec2( p.x, -p.y));
    vec4 sw = texture2D(u_Tex0, v_TexCoord + vec2(-p.x, -p.y));

    float lC  = luma(c);
    float lN  = luma(n);  float lS  = luma(s);
    float lE  = luma(e);  float lW  = luma(w);
    float lNE = luma(ne); float lNW = luma(nw);
    float lSE = luma(se); float lSW = luma(sw);

    // 4 overlapping quadrants (each 2x2, all share centre pixel c)
    // Q0: nw, n, w, c  |  Q1: n, ne, c, e
    // Q2: w, c, sw, s  |  Q3: c, e, s, se
    vec4  mean0 = (nw + n + w + c) * 0.25;
    vec4  mean1 = (n + ne + c + e) * 0.25;
    vec4  mean2 = (w + c + sw + s) * 0.25;
    vec4  mean3 = (c + e + s + se) * 0.25;

    float m0 = luma(mean0);
    float m1 = luma(mean1);
    float m2 = luma(mean2);
    float m3 = luma(mean3);

    float var0 = (lNW-m0)*(lNW-m0) + (lN-m0)*(lN-m0) + (lW-m0)*(lW-m0) + (lC-m0)*(lC-m0);
    float var1 = (lN-m1)*(lN-m1) + (lNE-m1)*(lNE-m1) + (lC-m1)*(lC-m1) + (lE-m1)*(lE-m1);
    float var2 = (lW-m2)*(lW-m2) + (lC-m2)*(lC-m2) + (lSW-m2)*(lSW-m2) + (lS-m2)*(lS-m2);
    float var3 = (lC-m3)*(lC-m3) + (lE-m3)*(lE-m3) + (lS-m3)*(lS-m3) + (lSE-m3)*(lSE-m3);

    // Output the mean of the most uniform quadrant
    vec4 result = mean0;
    float minVar = var0;
    if (var1 < minVar) { result = mean1; minVar = var1; }
    if (var2 < minVar) { result = mean2; minVar = var2; }
    if (var3 < minVar) { result = mean3; }

    result.a = c.a;
    gl_FragColor = result;
}
