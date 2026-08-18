// CRT scanlines — moving scan sweep + phosphor bloom + vignette overlay.
// CRT 扫描线 — 移动扫描带 + 磷光辉光 + 暗角覆盖层。
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

  // Fine scanlines with a slow downward drift.
  float scanline = 0.86 + 0.14 * sin(y * 1.6 * 3.14159 + u_time * 6.0);

  // A slower sweep band travelling top to bottom, like a CRT refresh.
  float band = 0.5 + 0.5 * sin(y * 0.09 - u_time * 1.4);
  vec3 col = vec3(0.95, 1.0, 0.97) * scanline * (0.88 + 0.12 * band);

  // Vignette — the tube darkens toward the edges.
  float d = length(uv - 0.5);
  col *= 1.0 - smoothstep(0.42, 0.85, d) * 0.55;

  gl_FragColor = vec4(col, u_intensity * 0.32);
}
