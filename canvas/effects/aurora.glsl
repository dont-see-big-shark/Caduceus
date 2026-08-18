// Aurora — three drifting lights over deep space (the page background).
// 极光 — 深空上的三团漂移光。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Speed
 * @default 1.0
 * @range 0.1, 3.0
 */
uniform float u_speed;

/**
 * @label Intensity
 * @default 1.0
 * @range 0.2, 1.5
 */
uniform float u_intensity;

vec3 glow(vec2 uv, vec2 center, vec3 col, float radius) {
  float d = length(uv - center);
  float g = exp(-(d * d) / (radius * radius));
  return col * g;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float t = u_time * u_speed;

  vec2 c1 = vec2(0.26 + 0.10 * sin(t * 0.70), 0.22 + 0.09 * cos(t * 0.90));
  vec2 c2 = vec2(0.82 + 0.09 * sin(t * 0.50 + 2.10), 0.28 + 0.11 * cos(t * 0.62));
  vec2 c3 = vec2(0.14 + 0.10 * cos(t * 0.40 + 1.30), 0.86 + 0.08 * sin(t * 0.78 + 4.20));

  vec3 col = vec3(0.016, 0.020, 0.039); // Palette.voidBlack
  col += glow(uv, c1, vec3(0.357, 0.486, 0.980), 0.34) * u_intensity; // azure
  col += glow(uv, c2, vec3(0.608, 0.420, 0.941), 0.27) * u_intensity; // violet
  col += glow(uv, c3, vec3(0.180, 0.827, 0.647), 0.24) * u_intensity; // jade

  gl_FragColor = vec4(col, 1.0);
}
