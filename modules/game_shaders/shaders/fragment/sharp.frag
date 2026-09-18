// Forces nearest-neighbour-style sharp sampling from inside the shader,
// regardless of whether the underlying sprite texture is set to bilinear
// ("Smooth Retro") filtering or not.
//
// Bilinear filtering only blends a sample toward its neighbours when that
// sample lands *between* texel centers. Sampling exactly *at* a texel's own
// center returns that texel's pure, unblended color - identical to true
// nearest-neighbour sampling. This snaps every fragment's UV coordinate to
// the center of whichever source texel it falls into before sampling, so
// edges (silhouettes, grout lines, item outlines) come out crisp instead of
// blended, while genuinely flat/noisy areas (dithered floor textures) look
// the same either way - there's nothing to blend toward there regardless.
//
// No pattern-matching, no neighbour comparisons, no scale change - this is
// the simplest shader in this menu.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_MapZoom;

void main() {
    vec2 texelSize = vec2(u_MapZoom / u_Resolution.x, u_MapZoom / u_Resolution.y);
    vec2 snapped = (floor(v_TexCoord / texelSize) + 0.5) * texelSize;
    gl_FragColor = texture2D(u_Tex0, snapped);
}
