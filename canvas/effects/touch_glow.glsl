// Touch glow — an interactive glow that follows the mouse. Move the pointer to play.
// 触摸发光 — 跟随鼠标的交互光晕。移动指针即可体验。
/** @resolution */
uniform vec2 u_resolution;

/** @mouse */
uniform vec2 u_mouse;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #3dff74
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 m = u_mouse / u_resolution;

  float d = distance(uv, m);
  float pulse = 0.65 + 0.35 * sin(u_time * 4.0);
  float glow = exp(-d * 7.0) * pulse;

  // Chunky pixel ring for the 8-bit read.
  float ring = exp(-pow(abs(d - 0.18), 2.0) / 0.004) * 0.5;

  vec3 col = u_color * (glow + ring);
  float a = min(1.0, (glow + ring) * 1.4);
  gl_FragColor = vec4(col, a);
}
