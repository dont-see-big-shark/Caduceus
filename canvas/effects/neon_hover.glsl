// Neon hover — interactive rim: the button's edge lights up as the pointer approaches.
// 霓虹悬停 — 交互边缘光：指针靠近时按钮边缘亮起。
/** @resolution */
uniform vec2 u_resolution;

/** @mouse */
uniform vec2 u_mouse;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #ff5ca8
 */
uniform vec3 u_color;

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = uv - 0.5;
  vec2 m = u_mouse / u_resolution;

  float d = sdRoundRect(p, vec2(0.44, 0.40), 0.05);
  float shape = 1.0 - smoothstep(-0.02, 0.02, d);

  float md = distance(uv, m);
  float hot = exp(-md * 5.0);
  float rim = exp(d * 20.0) * (0.15 + 0.85 * hot);
  float pulse = 0.85 + 0.15 * sin(u_time * 3.0);

  vec3 col = u_color * (shape * 0.35 + rim * (0.3 + 0.7 * hot) * pulse);
  float a = max(shape * 0.9, rim * 0.95);
  gl_FragColor = vec4(col, a);
}
