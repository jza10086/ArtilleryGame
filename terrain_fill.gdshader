shader_type canvas_item;
render_mode unshaded;

// One immutable height sample per initial terrain column. Craters only change
// the polygon mask; color remains a function of the original world position.
uniform sampler2D initial_surface : filter_linear, repeat_disable;
uniform vec4 deep_color : source_color = vec4(0.031373, 0.211765, 0.376471, 1.0);
uniform vec4 blue_color : source_color = vec4(0.086275, 0.552941, 0.905882, 1.0);
uniform vec4 cyan_color : source_color = vec4(0.219608, 0.858824, 0.945098, 1.0);
uniform float gradient_depth = 179.0;
varying vec2 terrain_position;

void vertex() {
	terrain_position = VERTEX;
}

void fragment() {
	float column = terrain_position.x / 4.0;
	float original_y = texture(initial_surface, vec2((column + 0.5) / 481.0, 0.5)).r;
	float depth = clamp((terrain_position.y - original_y) / gradient_depth, 0.0, 1.0);
	float light = 0.5 + 0.5 * cos(terrain_position.x / 510.0);
	COLOR = mix(mix(blue_color, cyan_color, light), deep_color, depth);
}
