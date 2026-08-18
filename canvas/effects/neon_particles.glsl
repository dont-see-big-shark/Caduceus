// Neon particles — ambient sparkles rising through the void, pink dots + cyan crosses.
// 霓虹粒子 — 环境粒子在虚空中上升闪烁：粉色圆点 + 青色十字。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #ff45c2
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec3 col = vec3(0.0);
  float t = u_time;

  for (int i = 0; i < 42; i++) {
    float fi = float(i);
    float hx = fract(sin(fi * 127.1 + 311.7) * 43758.5453);
    float hy = fract(sin(fi * 269.5 + 183.3) * 43758.5453);
    float hs = fract(sin(fi * 419.2 + 77.7) * 43758.5453);

    float speed = 0.12 + hs * 0.45;
    float y = fract(hy + t * speed);
    vec2 c = vec2(hx, y);

    float d = distance(uv, c);
    float tw = 0.5 + 0.5 * sin(t * 2.0 + fi * 7.0);
    float glow = exp(-d * 24.0) * tw * (0.35 + 0.65 * hs);

    vec3 pc = hs > 0.62 ? vec3(0.0, 0.94, 1.0) : u_color;
    col += pc * glow;
  }

  gl_FragColor = vec4(col, min(1.0, length(col) * 1.2));
}
