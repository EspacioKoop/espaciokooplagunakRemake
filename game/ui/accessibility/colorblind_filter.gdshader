shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform int mode = 0;

void fragment() {
    vec4 source = textureLod(screen_texture, SCREEN_UV, 0.0);
    vec3 color = source.rgb;
    if (mode == 1) {
        // Protanopia approximation: remove red-channel dependence.
        color = vec3(0.567 * color.r + 0.433 * color.g,
                     0.558 * color.r + 0.442 * color.g,
                     0.242 * color.g + 0.758 * color.b);
    } else if (mode == 2) {
        // Deuteranopia approximation: remove green-channel dependence.
        color = vec3(0.625 * color.r + 0.375 * color.g,
                     0.700 * color.r + 0.300 * color.g,
                     0.300 * color.g + 0.700 * color.b);
    } else if (mode == 3) {
        // Tritanopia approximation: reduce blue/yellow confusion.
        color = vec3(0.950 * color.r + 0.050 * color.g,
                     0.433 * color.g + 0.567 * color.b,
                     0.475 * color.g + 0.525 * color.b);
    } else if (mode == 4) {
        float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = vec3(luminance);
    }
    COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
}
