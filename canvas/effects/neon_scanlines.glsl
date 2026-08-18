// Neon scanlines — pink CRT sweep + vignette, the tube is always on.
// 霓虹扫描线 — 粉色 CRT 扫描带 + 暗角。
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Intensity
 * @default 1.0
 * @range 0.2, 2.0
 */
uniform float u_intensity;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float y = uv.y * u_resolution.y;

  float scanline = 0.86 + 0.14 * sin(y * 1.6 * 3.14159 + u_time * 8.0);
  float band = 0.5 + 0.5 * sin(y * 0.08 - u_time * 1.8);
  vec3 col = vec3(0.98, 0.72, 0.90) * scanline * (0.86 + 0.14 * band);

  float d = length(uv - 0.5);
  col *= 1.0 - smoothstep(0.42, 0.85, d) * 0.5;

  gl_FragColor = vec4(col, u_intensity * 0.30);
}
