// Kuwahara filter radius-2 (5x5 neighbourhood, 3x3 quadrants).
// Produces a strong smooth "plastic/painterly" look: flat colour areas
// become perfectly clean, edges stay sharp without blurring.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;

float luma(vec4 c) {
    return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 p = 1.0 / u_Resolution;

    // Sample full 5x5 neighbourhood (rows A..E top to bottom, cols 1..5 left to right)
    vec4 A1 = texture2D(u_Tex0, v_TexCoord + vec2(-2.0*p.x,  2.0*p.y));
    vec4 A2 = texture2D(u_Tex0, v_TexCoord + vec2(-1.0*p.x,  2.0*p.y));
    vec4 A3 = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,       2.0*p.y));
    vec4 A4 = texture2D(u_Tex0, v_TexCoord + vec2( 1.0*p.x,  2.0*p.y));
    vec4 A5 = texture2D(u_Tex0, v_TexCoord + vec2( 2.0*p.x,  2.0*p.y));

    vec4 B1 = texture2D(u_Tex0, v_TexCoord + vec2(-2.0*p.x,  1.0*p.y));
    vec4 B2 = texture2D(u_Tex0, v_TexCoord + vec2(-1.0*p.x,  1.0*p.y));
    vec4 B3 = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,       1.0*p.y));
    vec4 B4 = texture2D(u_Tex0, v_TexCoord + vec2( 1.0*p.x,  1.0*p.y));
    vec4 B5 = texture2D(u_Tex0, v_TexCoord + vec2( 2.0*p.x,  1.0*p.y));

    vec4 C1 = texture2D(u_Tex0, v_TexCoord + vec2(-2.0*p.x,  0.0));
    vec4 C2 = texture2D(u_Tex0, v_TexCoord + vec2(-1.0*p.x,  0.0));
    vec4 C3 = texture2D(u_Tex0, v_TexCoord);
    vec4 C4 = texture2D(u_Tex0, v_TexCoord + vec2( 1.0*p.x,  0.0));
    vec4 C5 = texture2D(u_Tex0, v_TexCoord + vec2( 2.0*p.x,  0.0));

    vec4 D1 = texture2D(u_Tex0, v_TexCoord + vec2(-2.0*p.x, -1.0*p.y));
    vec4 D2 = texture2D(u_Tex0, v_TexCoord + vec2(-1.0*p.x, -1.0*p.y));
    vec4 D3 = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,      -1.0*p.y));
    vec4 D4 = texture2D(u_Tex0, v_TexCoord + vec2( 1.0*p.x, -1.0*p.y));
    vec4 D5 = texture2D(u_Tex0, v_TexCoord + vec2( 2.0*p.x, -1.0*p.y));

    vec4 E1 = texture2D(u_Tex0, v_TexCoord + vec2(-2.0*p.x, -2.0*p.y));
    vec4 E2 = texture2D(u_Tex0, v_TexCoord + vec2(-1.0*p.x, -2.0*p.y));
    vec4 E3 = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,      -2.0*p.y));
    vec4 E4 = texture2D(u_Tex0, v_TexCoord + vec2( 1.0*p.x, -2.0*p.y));
    vec4 E5 = texture2D(u_Tex0, v_TexCoord + vec2( 2.0*p.x, -2.0*p.y));

    // Precompute luminances
    float lA1=luma(A1), lA2=luma(A2), lA3=luma(A3), lA4=luma(A4), lA5=luma(A5);
    float lB1=luma(B1), lB2=luma(B2), lB3=luma(B3), lB4=luma(B4), lB5=luma(B5);
    float lC1=luma(C1), lC2=luma(C2), lC3=luma(C3), lC4=luma(C4), lC5=luma(C5);
    float lD1=luma(D1), lD2=luma(D2), lD3=luma(D3), lD4=luma(D4), lD5=luma(D5);
    float lE1=luma(E1), lE2=luma(E2), lE3=luma(E3), lE4=luma(E4), lE5=luma(E5);

    // Q0: top-left  (A1-A3, B1-B3, C1-C3)
    vec4 mean0 = (A1+A2+A3 + B1+B2+B3 + C1+C2+C3) / 9.0;
    float m0 = luma(mean0);
    float var0 = (lA1-m0)*(lA1-m0) + (lA2-m0)*(lA2-m0) + (lA3-m0)*(lA3-m0)
               + (lB1-m0)*(lB1-m0) + (lB2-m0)*(lB2-m0) + (lB3-m0)*(lB3-m0)
               + (lC1-m0)*(lC1-m0) + (lC2-m0)*(lC2-m0) + (lC3-m0)*(lC3-m0);

    // Q1: top-right (A3-A5, B3-B5, C3-C5)
    vec4 mean1 = (A3+A4+A5 + B3+B4+B5 + C3+C4+C5) / 9.0;
    float m1 = luma(mean1);
    float var1 = (lA3-m1)*(lA3-m1) + (lA4-m1)*(lA4-m1) + (lA5-m1)*(lA5-m1)
               + (lB3-m1)*(lB3-m1) + (lB4-m1)*(lB4-m1) + (lB5-m1)*(lB5-m1)
               + (lC3-m1)*(lC3-m1) + (lC4-m1)*(lC4-m1) + (lC5-m1)*(lC5-m1);

    // Q2: bottom-left (C1-C3, D1-D3, E1-E3)
    vec4 mean2 = (C1+C2+C3 + D1+D2+D3 + E1+E2+E3) / 9.0;
    float m2 = luma(mean2);
    float var2 = (lC1-m2)*(lC1-m2) + (lC2-m2)*(lC2-m2) + (lC3-m2)*(lC3-m2)
               + (lD1-m2)*(lD1-m2) + (lD2-m2)*(lD2-m2) + (lD3-m2)*(lD3-m2)
               + (lE1-m2)*(lE1-m2) + (lE2-m2)*(lE2-m2) + (lE3-m2)*(lE3-m2);

    // Q3: bottom-right (C3-C5, D3-D5, E3-E5)
    vec4 mean3 = (C3+C4+C5 + D3+D4+D5 + E3+E4+E5) / 9.0;
    float m3 = luma(mean3);
    float var3 = (lC3-m3)*(lC3-m3) + (lC4-m3)*(lC4-m3) + (lC5-m3)*(lC5-m3)
               + (lD3-m3)*(lD3-m3) + (lD4-m3)*(lD4-m3) + (lD5-m3)*(lD5-m3)
               + (lE3-m3)*(lE3-m3) + (lE4-m3)*(lE4-m3) + (lE5-m3)*(lE5-m3);

    // Output the mean of the most uniform quadrant
    vec4 result = mean0;
    float minVar = var0;
    if (var1 < minVar) { result = mean1; minVar = var1; }
    if (var2 < minVar) { result = mean2; minVar = var2; }
    if (var3 < minVar) { result = mean3; }

    result.a = C3.a;
    gl_FragColor = result;
}
