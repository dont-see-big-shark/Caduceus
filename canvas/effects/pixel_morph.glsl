// Pixel morph — a square morphs into a circle, a diamond and back, on a chunky pixel grid.
// 像素变形 — 方块 → 圆形 → 菱形 → 方块，在块状像素网格上，时间驱动。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Speed
 * @default 1.0
 * @range 0.2, 3.0
 */
uniform float u_speed;

float sSquare(vec2 p) { return max(abs(p.x), abs(p.y)) - 0.30; }
float sCircle(vec2 p) { return length(p) - 0.33; }
float sDiamond(vec2 p) { return (abs(p.x) + abs(p.y)) - 0.36; }

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  // Pixelate to an 8-bit grid (16 x 9 cells).
  vec2 p = (floor((uv - 0.5) * 16.0) + 0.5) / 16.0;

  float t = fract(u_time * 0.12 * u_speed);
  float d;
  if (t < 0.33) {
    d = mix(sSquare(p), sCircle(p), t / 0.33);
  } else if (t < 0.66) {
    d = mix(sCircle(p), sDiamond(p), (t - 0.33) / 0.33);
  } else {
    d = mix(sDiamond(p), sSquare(p), (t - 0.66) / 0.34);
  }

  float a = 1.0 - smoothstep(0.0, 0.06, d);
  vec3 col = vec3(0.24, 1.0, 0.45) * a;
  gl_FragColor = vec4(col, a);
}
