// Caret blink — a blinking caret says the answer is still coming.
// 光标闪烁 — 闪烁的光标表示回答还在继续。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #F3F4F8
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float blink = 0.5 + 0.5 * sin(u_time * 2.2);

  float bar = 1.0 - smoothstep(0.0, 2.5 / u_resolution.x, uv.x);

  gl_FragColor = vec4(u_color, bar * blink);
}
