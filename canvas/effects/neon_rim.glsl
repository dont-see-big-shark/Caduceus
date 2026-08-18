// Neon rim — material outer glow: the shape's edge radiates colored light, pulsing.
// 材质外发光 — 形状边缘向外辐射彩色光，呼吸式脉冲。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #3dff74
 */
uniform vec3 u_color;

/**
 * @label Speed
 * @default 1.0
 * @range 0.2, 3.0
 */
uniform float u_speed;

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = uv - 0.5;
  float d = sdRoundRect(p, vec2(0.40, 0.28), 0.05);

  float pulse = 0.7 + 0.3 * sin(u_time * 3.0 * u_speed);
  float glow = exp(d * 14.0) * pulse;
  float shape = 1.0 - smoothstep(0.0, 0.025, d);

  vec3 col = u_color * (glow * 0.85 + shape * 0.45);
  float a = max(min(glow, 1.0), shape);
  gl_FragColor = vec4(col, a);
}
