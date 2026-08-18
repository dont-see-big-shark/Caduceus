// Neon touch — interactive: move the pointer to feel the glow + expanding ripple rings.
// 霓虹触摸 — 交互：移动指针感受光晕与扩散涟漪。
/** @resolution */
uniform vec2 u_resolution;

/** @mouse */
uniform vec2 u_mouse;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #ff2d78
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 m = u_mouse / u_resolution;

  float d = distance(uv, m);
  float glow = exp(-d * 6.5) * (0.6 + 0.4 * sin(u_time * 5.0));

  float t1 = fract(u_time * 0.9);
  float ring1 = exp(-pow(abs(d - t1 * 0.5), 2.0) / 0.003) * (1.0 - t1);
  float t2 = fract(u_time * 0.9 + 0.5);
  float ring2 = exp(-pow(abs(d - t2 * 0.5), 2.0) / 0.003) * (1.0 - t2);

  float total = glow + ring1 * 1.4 + ring2 * 1.4;
  vec3 col = u_color * total;
  float a = min(1.0, total * 1.4);
  gl_FragColor = vec4(col, a);
}
