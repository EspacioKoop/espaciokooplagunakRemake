shader_type spatial;
render_mode cull_disabled;
uniform vec3 shore_color : source_color = vec3(0.03, 0.32, 0.39);
uniform vec3 horizon_color : source_color = vec3(0.37, 0.59, 0.66);
uniform float movement = 1.0;
varying vec3 world_vertex;
void vertex() {
 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 VERTEX.y += sin(world_vertex.x * 0.9 + TIME * movement * 0.8) * 0.045 + sin(world_vertex.z * 0.6 + TIME * movement * 0.6) * 0.035;
}
void fragment() {
 float wave = sin(world_vertex.x * 1.2 + world_vertex.z * 0.16 + TIME * movement) * 0.04;
 float distance_mix = smoothstep(20.0, 150.0, world_vertex.x);
 ALBEDO = mix(shore_color + wave, horizon_color, distance_mix);
 ROUGHNESS = 0.3;
 METALLIC = 0.25;
 EMISSION = horizon_color * distance_mix * 0.35;
}
