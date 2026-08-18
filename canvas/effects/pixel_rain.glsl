// Pixel rain — green digits falling down the tube, matrix style.
// 像素雨 — 绿色字符沿屏幕下落，矩阵风格。
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

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 cell = floor(uv * vec2(44.0, 24.0));

  float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);

  float speed = 0.25 + seed * 0.75;
  float y = fract(cell.y / 24.0 - u_time * speed);

  // Head bright, trail fading behind it.
  float head = smoothstep(0.0, 0.05, y) * (1.0 - smoothstep(0.10, 0.22, y));
  float trail = smoothstep(0.0, 0.05, y) * (1.0 - y) * 0.35;

  float a = (head + trail) * (0.35 + 0.65 * seed);
  gl_FragColor = vec4(u_color * (head * 0.9 + trail * 0.4), a * 0.7);
}
