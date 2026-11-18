#version 460 core
// The Curl page turn: rolls a picture of the old page off the screen around
// a vertical cylinder and leaves what is underneath showing where the page
// has gone. Drawn by PageTurnOverlay (reader feature, presentation/widgets),
// which sets the uniforms in this order.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;      // page size, px
uniform float uProgress; // 0 = flat, 1 = gone
uniform float uRtl;      // 1 = the page leaves to the right (Japanese forward turn)
uniform sampler2D uPage;

out vec4 fragColor;

const float PI = 3.14159265;

vec4 page(float x, float y) {
  // x is in the "leaves to the left" frame; mirror it back for rtl.
  float px = mix(x, uSize.x - x, uRtl);
  // No y flip for IMPELLER_TARGET_OPENGLES: an image sampler is already the
  // right way up there, and flipping drew the page upside down.
  return texture(uPage, vec2(px, y) / uSize);
}

// The back of the sheet: the page seen through paper.
vec4 back(float x, float y, float light) {
  vec4 c = page(x, y);
  return vec4(mix(c.rgb, vec3(1.0), 0.82) * light, 1.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float w = uSize.x;
  float x = mix(p.x, w - p.x, uRtl);
  float r = max(w * 0.07, 28.0);
  // The cylinder's axis travels from the free edge to just past the spine.
  float cx = mix(w, -r, uProgress);
  float d = x - cx;

  if (d > r) {
    // The page has left this part: a soft shadow next to the roll.
    float s = 0.28 * (1.0 - smoothstep(0.0, r * 1.6, d - r)) * step(0.001, uProgress);
    fragColor = vec4(0.0, 0.0, 0.0, s);
    return;
  }
  if (d > 0.0) {
    // On the cylinder: the sheet goes up the near side and comes back over.
    float theta = asin(d / r);
    float xUpper = cx + r * (PI - theta);
    float xLower = cx + r * theta;
    if (xUpper <= w) {
      fragColor = back(xUpper, p.y, 0.80 + 0.20 * cos(theta));
    } else if (xLower <= w) {
      vec4 c = page(xLower, p.y);
      fragColor = vec4(c.rgb * (1.0 - 0.35 * (d / r) * (d / r)), 1.0);
    } else {
      fragColor = vec4(0.0);
    }
    return;
  }
  // Flat part: the turned sheet may be lying on top of it.
  float xFlap = cx + PI * r - d;
  if (xFlap <= w) {
    fragColor = back(xFlap, p.y, 1.0);
  } else {
    // A little shade where the flap's edge is about to arrive.
    float edge = xFlap - w;
    float shade = 1.0 - 0.18 * (1.0 - smoothstep(0.0, r, edge)) * step(0.001, uProgress);
    vec4 c = page(x, p.y);
    fragColor = vec4(c.rgb * shade, c.a);
  }
}
