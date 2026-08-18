// Neon shape morph — a square morphs into a 5-point star, a diamond and a circle,
// tweened through their signed distance fields on a chunky pixel grid.
// 霓虹形状渐变 — 方形 → 星形 → 菱形 → 圆形，通过 SDF 几何渐变，像素网格量化。
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

float sdSquare(vec2 p) { return max(abs(p.x), abs(p.y)) - 0.30; }
float sdDiamond(vec2 p) { return (abs(p.x) + abs(p.y)) - 0.34; }
float sdCircle(vec2 p) { return length(p) - 0.33; }

float sdStar(vec2 p, float r) {
  float an = 3.14159265 / 5.0;
  float en = 3.14159265 / 2.5;
  vec2 acs = vec2(cos(an), sin(an));
  vec2 ecs = vec2(cos(en), sin(en));
  float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
  p = length(p) * vec2(cos(bn), abs(sin(bn)));
  p -= r * acs;
  p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
  return length(p) * sign(p.x);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (floor((uv - 0.5) * 18.0) + 0.5) / 18.0;

  float t = fract(u_time * 0.10 * u_speed);
  float d;
  if (t < 0.25) {
    d = mix(sdSquare(p), sdStar(p, 0.38), t / 0.25);
  } else if (t < 0.50) {
    d = mix(sdStar(p, 0.38), sdDiamond(p), (t - 0.25) / 0.25);
  } else if (t < 0.75) {
    d = mix(sdDiamond(p), sdCircle(p), (t - 0.50) / 0.25);
  } else {
    d = mix(sdCircle(p), sdSquare(p), (t - 0.75) / 0.25);
  }

  float a = 1.0 - smoothstep(0.0, 0.07, d);
  vec3 col = vec3(1.0, 0.27, 0.76) * a; // neon pink, cyan-leaning
  gl_FragColor = vec4(col, a);
}
