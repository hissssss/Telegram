#version 460 core

// Port of Telegram Android's liquid glass refraction shader.
// Source: TMessagesProj/src/main/res/raw/liquid_glass_shader.agsl
//
// Contract (ui.ImageFilter.shader): the first uniform must be a vec2 that the
// engine sets to the size of the bound backdrop texture in physical pixels;
// the first sampler2D is bound by the engine to the filter input. When driven
// manually through a Canvas (test harness), set u_size yourself.
//
// Coordinates: FlutterFragCoord() is top-left-origin pixel space matching the
// AGSL fragCoord. Refraction displacement happens in that pixel space; the
// normalized flip for GLES happens only at sampling time.
//
// Deliberate addition vs the AGSL (ARCHITECTURE.md section 3.2): the output is
// clipped to the SDF with a 1-px smoothstep feather. Android clips the effect
// render node to the rounded outline (setClipToOutline,
// BlurredBackgroundDrawableRenderNode.java:39, 79-85); the Flutter port pushes
// the backdrop layer under a plain rect clip inflated by the refraction bleed
// (a rounded clip would clamp backdrop sampling and kill rim refraction), so
// the shader itself must emit transparency outside the panel.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 u_size;                            // engine-set backdrop size (px)
uniform vec2 u_center;                          // panel center (px)
uniform vec2 u_half_size;                       // panel half extents (px) — AGSL `size`
uniform vec4 u_radius;                          // corner radii packed (RB, RT, LB, LT)
uniform float u_thickness;                      // glass lip thickness (px)
uniform float u_refract_index;                  // 1.5 in production
uniform float u_refract_intensity;              // 0.75 in production
uniform vec4 u_foreground_color;                // premultiplied tint

uniform sampler2D u_backdrop;

out vec4 frag_color;

// AGSL sdfRect: rounded-box SDF with per-quadrant radius selection.
// r is (RB, RT, LB, LT): x>0 picks .xy (right pair), then y>0 picks bottom.
float sdfRect(vec2 p, vec4 r) {
  r.xy = (p.x > 0.0) ? r.xy : r.zw;
  r.x = (p.y > 0.0) ? r.x : r.y;
  vec2 q = abs(p) - u_half_size + r.x;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r.x;
}

vec4 srcOver(vec4 src, vec4 dst) {
  return vec4(src.rgb + dst.rgb * (1.0 - src.a), src.a + (1.0 - src.a) * dst.a);
}

vec4 sampleBackdrop(vec2 posPx) {
  vec2 uv = posPx / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_backdrop, uv);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 p = fragCoord - u_center;
  float sd = sdfRect(p, u_radius);
  vec2 uv = fragCoord;

  if (sd < 0.0) {
    float sdX = sdfRect(p + vec2(1.0, 0.0), u_radius);
    float sdY = sdfRect(p + vec2(0.0, 1.0), u_radius);

    float n_cos = max(u_thickness + sd, 0.0) / u_thickness;
    float n_cos2 = n_cos * n_cos;
    float n_sin = sqrt(1.0 - n_cos2);
    vec3 normal = normalize(vec3((sdX - sd) * n_cos, (sdY - sd) * n_cos, n_sin));

    vec3 refract_vec = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / u_refract_index);
    float h = sd < -u_thickness ? u_thickness : sqrt(sd * (-2.0 * u_thickness - sd));
    float refract_length = (h + 8.0 * u_thickness) / -refract_vec.z;

    uv += refract_vec.xy * refract_length * u_refract_intensity;
  }

  // SDF output clip (no AGSL analog — see the header comment): fully
  // transparent outside the panel so the srcOver-composited backdrop layer
  // preserves the destination there, with a 1-px anti-aliased edge. The
  // coverage factor scales the premultiplied color as a whole.
  float coverage = 1.0 - smoothstep(-1.0, 0.0, sd);
  frag_color = coverage * srcOver(u_foreground_color, sampleBackdrop(uv));
}
