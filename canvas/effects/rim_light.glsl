// Rim light — a running turn lights the composer's edge.
// 边缘光 — 运行中的回合点亮输入框边缘，取代 "generating…" 文字。
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

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float t = u_time * u_speed;

  float edge = min(
    min(uv.x, 1.0 - uv.x) * u_resolution.x,
    min(uv.y, 1.0 - uv.y) * u_resolution.y
  );
  float glow = exp(-edge / 16.0);

  float pulse = 0.55 + 0.45 * sin(t * 2.4);
  vec3 col = mix(vec3(0.89, 0.75, 0.54), vec3(0.97, 0.92, 0.82), pulse);
  float alpha = glow * (0.28 + 0.55 * pulse);

  gl_FragColor = vec4(col, alpha);
}
