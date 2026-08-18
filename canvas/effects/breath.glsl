// Breath — a status dot that is alive, not greyed out. Ambient loop.
// 呼吸 — 状态点活着而不是灰掉。环境循环，resting frame = steady glow.
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * @label Color
 * @color
 * @default #2ED3A5
 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float r = length(uv - 0.5);
  float t = u_time;

  float breath = 0.62 + 0.38 * sin(t * 2.0);
  float core = smoothstep(0.50, 0.40, r) * (0.72 + 0.28 * breath);
  float halo = exp(-(r * r) / 0.055) * 0.30 * breath;

  vec3 col = u_color * (core + halo);
  gl_FragColor = vec4(col, 1.0);
}
