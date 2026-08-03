uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;

float luma(vec4 c) {
    return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 p = 1.0 / u_Resolution;

    vec4 c  = texture2D(u_Tex0, v_TexCoord);
    vec4 n  = texture2D(u_Tex0, v_TexCoord + vec2( 0.0,  p.y));
    vec4 s  = texture2D(u_Tex0, v_TexCoord + vec2( 0.0, -p.y));
    vec4 e  = texture2D(u_Tex0, v_TexCoord + vec2( p.x,  0.0));
    vec4 w  = texture2D(u_Tex0, v_TexCoord + vec2(-p.x,  0.0));
    vec4 ne = texture2D(u_Tex0, v_TexCoord + vec2( p.x,  p.y));
    vec4 nw = texture2D(u_Tex0, v_TexCoord + vec2(-p.x,  p.y));
    vec4 se = texture2D(u_Tex0, v_TexCoord + vec2( p.x, -p.y));
    vec4 sw = texture2D(u_Tex0, v_TexCoord + vec2(-p.x, -p.y));

    // Sobel edge detection on luminance
    float lN  = luma(n);  float lS  = luma(s);
    float lE  = luma(e);  float lW  = luma(w);
    float lNE = luma(ne); float lNW = luma(nw);
    float lSE = luma(se); float lSW = luma(sw);

    float sobelH = (-lNW - 2.0*lW - lSW) + (lNE + 2.0*lE + lSE);
    float sobelV = (-lNW - 2.0*lN - lNE) + (lSW + 2.0*lS + lSE);
    float edge = sqrt(sobelH*sobelH + sobelV*sobelV);

    // 8-neighbour average (used for both sharpening and smoothing)
    vec4 blur = (n + s + e + w + ne + nw + se + sw) / 8.0;

    // Unsharp mask: push center away from local average
    float sharpStrength = 1.8;
    vec4 sharp = c + (c - blur) * sharpStrength;
    sharp = clamp(sharp, 0.0, 1.0);

    // Edge -> sharp, flat area -> very slightly smoothed (flattens color fills)
    float edgeFactor = smoothstep(0.05, 0.25, edge);
    vec4 result = mix(mix(c, blur, 0.12), sharp, edgeFactor);
    result.a = c.a;

    gl_FragColor = result;
}
