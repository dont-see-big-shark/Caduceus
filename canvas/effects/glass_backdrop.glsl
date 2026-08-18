// Glass backdrop — frosted sheet sampling the aurora behind it.
// 玻璃折射 — 毛玻璃采样背后的极光，边缘带高光 rim。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Backdrop
 */
uniform sampler2D u_backdrop;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;

  // Gentle drift so the frost reads as alive.
  float t = u_time;
  vec2 drift = vec2(sin(t * 0.6) * 0.004, cos(t * 0.5) * 0.003);

  vec3 sum = vec3(0.0);
  sum += texture2D(u_backdrop, uv + drift + vec2(0.012, 0.0)).rgb;
  sum += texture2D(u_backdrop, uv + drift + vec2(-0.012, 0.0)).rgb;
  sum += texture2D(u_backdrop, uv + drift + vec2(0.0, 0.012)).rgb;
  sum += texture2D(u_backdrop, uv + drift + vec2(0.0, -0.012)).rgb;
  vec3 col = sum / 4.0;

  // Frosted tint + top-left rim highlight.
  col = col * 0.72 + vec3(0.05, 0.06, 0.10) * 0.28;
  float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  float rim = exp(-edge * 16.0);
  col += vec3(0.85, 0.87, 0.93) * rim * 0.28;

  gl_FragColor = vec4(col, 1.0);
}
