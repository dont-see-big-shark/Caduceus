// Neon burst — particles explode from the pointer with a cyan shockwave ring. Interactive.
// 霓虹爆发 — 粒子从指针处爆发 + 青色冲击波环。交互。
/** @resolution */
uniform vec2 u_resolution;

/** @mouse */
uniform vec2 u_mouse;

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
  vec2 m = u_mouse / u_resolution;
  vec3 col = vec3(0.0);
  float t = u_time;

  for (int i = 0; i < 36; i++) {
    float fi = float(i);
    float a = (fi / 36.0) * 6.28318 + fi * 0.137;
    float sp = 0.22 + fract(sin(fi * 91.7) * 43758.5453) * 0.42;

    float life = fract(t * 0.8);
    float speed = sp * (1.0 - life);
    vec2 dir = vec2(cos(a), sin(a));
    vec2 p = m + dir * speed;

    float d = distance(uv, p);
    float fade = (1.0 - life) * (1.0 - life);
    float dotp = exp(-d * 42.0) * fade;
    col += u_color * dotp * 0.9;
  }

  float r = fract(t * 0.8) * 0.55;
  float ring = exp(-pow(abs(distance(uv, m) - r), 2.0) / 0.0022) * (1.0 - r);
  col += vec3(0.0, 0.94, 1.0) * ring;

  gl_FragColor = vec4(col, min(1.0, length(col) * 1.2));
}
