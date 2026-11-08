extends RefCounted
## Room-owned mode and local keyboard bindings; the manifest constrains player counts.
static func schema() -> Dictionary:
	var config: Dictionary = {"schema_format": 3, "settings_version": 1, "fields": {
		"mode": {"type": "string", "default": "ffa", "title": "对战模式",
			"description": "混战 2–8 人；团队对抗 2/4/6/8 人；单人测试 1 人。",
			"audience": "room", "apply": "next_round", "control": "select",
			"values": ["ffa", "teams", "training"], "labels": ["自由混战", "团队对抗", "单人测试"]}
	}, "layout": [{"id": "battle", "title": "对战规则", "expanded": true,
		"children": [{"field": "mode"}]}]}

	var controls: Array[Dictionary] = []
	for definition: Array in [
		["move_left", "向左移动", KEY_A], ["move_right", "向右移动", KEY_D],
		["artillery_angle_up", "增加角度", KEY_W], ["artillery_angle_down", "减小角度", KEY_S],
		["artillery_power_down", "减小力度", KEY_Q], ["artillery_power_up", "增加力度", KEY_E],
		["artillery_fire", "发射炮弹", KEY_SPACE]]:
		var action: String = definition[0]
		config.fields[action] = {"type": "array", "action": action,
			"default": [{"kind": "key", "code": definition[2], "physical": true}],
			"title": definition[1], "audience": "local", "apply": "immediate",
			"control": "binding", "items": {"type": "object", "format": "binding"}, "max_items": 2}
		controls.append({"field": action})
	config.layout.append({"id": "controls", "title": "操作", "expanded": true, "children": controls})
	return config
