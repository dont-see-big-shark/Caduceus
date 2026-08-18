// Neon bloom — a pink core with a breathing multi-layer aura.
// 霓虹绽放 — 粉色核心 + 多层呼吸光晕。
/** @resolution */
uniform vec2 u_resolution;

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
  float d = length(uv - 0.5);

  float pulse = 0.7 + 0.3 * sin(u_time * 2.5);
  float core = 1.0 - smoothstep(0.0, 0.20, d);
  float aura = exp(-d * 4.2) * pulse;
  float halo = exp(-d * 2.1) * pulse * 0.6;

  vec3 col = u_color * (core * 1.4 + aura * 0.9 + halo * 0.55);
  float a = min(1.0, core + aura);
  gl_FragColor = vec4(col, a);
}
