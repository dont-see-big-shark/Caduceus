// Brass sheen — the 4.5s highlight travelling across the primary button.
// 黄铜扫光 — 主按钮上一道 4.5s 移动的高光。
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

  // Vertical brass gradient: light gathers at the top, falls into shadow.
  float v = 1.0 - uv.y;
  vec3 brass = mix(
    vec3(0.753, 0.561, 0.322),  // brassShadow
    vec3(0.965, 0.894, 0.769),  // brassLight
    smoothstep(0.0, 1.0, v * 1.35 - 0.25)
  );

  // A slow sheen sweeping left to right; too slow to read as motion.
  float x = fract(t * 0.22 - 0.5);
  float sheen = exp(-pow((uv.x - x) / 0.09, 2.0)) * 0.55;
  brass += vec3(1.0, 0.99, 0.93) * sheen;

  gl_FragColor = vec4(brass, 1.0);
}
