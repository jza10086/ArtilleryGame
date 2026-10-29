shader_type canvas_item;
render_mode unshaded;

// Texture stores a signed distance, not colored pixels. The 0 contour is
// reconstructed at the actual output resolution; AA covers only its edge.
uniform sampler2D terrain_field : filter_linear, repeat_disable;
varying vec2 local_position;

vec4 cubic_weights(float f) {
	float g = 1.0 - f;
	float f2 = f * f;
	float f3 = f2 * f;
	return vec4(g * g * g, 3.0 * f3 - 6.0 * f2 + 4.0,
		-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0, f3) / 6.0;
}

vec3 continuous_field(vec2 uv) {
	vec2 size = vec2(480.0, 300.0);
	vec2 p = uv * size - 0.5;
	vec2 base = floor(p);
	vec2 f = fract(p);
	vec4 wx = cubic_weights(f.x);
	vec4 wy = cubic_weights(f.y);
	vec2 gx = vec2(wx.x + wx.y, wx.z + wx.w);
	vec2 gy = vec2(wy.x + wy.y, wy.z + wy.w);
	vec2 hx = vec2(wx.y / gx.x - 1.0, wx.w / gx.y + 1.0);
	vec2 hy = vec2(wy.y / gy.x - 1.0, wy.w / gy.y + 1.0);
	vec4 coordinates = vec4(base.x + hx.x, base.y + hy.x,
		base.x + hx.y, base.y + hy.y) + 0.5;
	coordinates /= size.xyxy;
	vec3 a = texture(terrain_field, coordinates.xy).rgb;
	vec3 b = texture(terrain_field, coordinates.zy).rgb;
	vec3 c = texture(terrain_field, coordinates.xw).rgb;
	vec3 d = texture(terrain_field, coordinates.zw).rgb;
	return mix(mix(a, b, gx.y), mix(c, d, gx.y), gy.y);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 field = continuous_field(UV);
	float distance_px = field.r * 3.0;
	float aa = max(fwidth(distance_px) * 0.65, 0.12);
	float coverage = smoothstep(-aa, aa, distance_px);
	vec2 inward = field.gb / max(length(field.gb), 0.001);
	float upward_edge = smoothstep(0.45, 0.85, inward.y);

	// Broad painterly clay planes, with no tiled texture or per-pixel grain.
	float depth = clamp((local_position.y - 470.0) / 400.0, 0.0, 1.0);
	vec3 soil = mix(vec3(0.81, 0.55, 0.36), vec3(0.53, 0.29, 0.28), depth);
	float stratum = sin(local_position.y * 0.035 + sin(local_position.x * 0.007) * 0.75);
	soil += vec3(0.028, 0.019, 0.014) * stratum;
	float broad_light = 0.5 + 0.5 * sin(local_position.x * 0.004 + 1.1);
	soil += vec3(0.022, 0.016, 0.008) * broad_light;

	// A smooth soft bevel follows every hole, cliff and freshly carved crater.
	float rim = 1.0 - smoothstep(1.3, 5.0, distance_px);
	float light_side = clamp(dot(inward, normalize(vec2(0.45, 1.0))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 edge_tone = mix(vec3(0.32, 0.28, 0.26), vec3(0.96, 0.74, 0.45), light_side);
	soil = mix(soil, edge_tone, rim * 0.6);

	// Grass is a continuous band on upward-facing boundaries, never pixel tufts.
	float grass = (1.0 - smoothstep(11.0, 15.0, distance_px)) * upward_edge;
	float lip = (1.0 - smoothstep(14.0, 19.0, distance_px)) * upward_edge;
	soil = mix(soil, vec3(0.22, 0.40, 0.28), lip * 0.66);
	vec3 turf = mix(vec3(0.64, 0.77, 0.34), vec3(0.32, 0.55, 0.32), smoothstep(1.0, 12.0, distance_px));
	soil = mix(soil, turf, grass);
	float highlight = (1.0 - smoothstep(0.5, 2.3, distance_px)) * upward_edge;
	soil = mix(soil, vec3(0.84, 0.89, 0.52), highlight * 0.68);
	COLOR = vec4(soil, coverage);
}
