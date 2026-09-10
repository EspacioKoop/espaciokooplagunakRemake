shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 sphere_position;

float hash(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x),
                   mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x),
                   mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
    return noise(p)*0.55 + noise(p*2.07)*0.27 + noise(p*4.13)*0.13 + noise(p*8.17)*0.05;
}
void vertex() { sphere_position = VERTEX; }
void fragment() {
    vec3 p = normalize(sphere_position);
    float land = smoothstep(0.47, 0.56, fbm(p*4.6+vec3(1.0,7.0,2.0)));
    float clouds = smoothstep(0.61, 0.72, fbm(p*13.0));
    vec3 ocean = vec3(0.017, 0.055, 0.10);
    vec3 continent = mix(vec3(0.08,0.20,0.15), vec3(0.22,0.26,0.16), fbm(p*22.0));
    ALBEDO = mix(mix(ocean, continent, land), vec3(0.62,0.73,0.76), clouds*0.7);
    ROUGHNESS = 0.82;
    METALLIC = 0.0;
    SPECULAR = 0.18;
    EMISSION = vec3(0.003,0.012,0.019);
}
