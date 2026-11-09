extends RefCounted
## Room-owned mode and local keyboard bindings; the manifest constrains player counts.
const AMMO_NAMES: Array[String] = ["标准弹", "重型爆破", "三重散射", "集束花火", "跳弹", "钻地弹", "造山弹", "虹吸弹", "滚地雷", "空爆弹雨", "燃烧弹", "电磁脉冲", "跃迁弹", "连锁震爆", "感应雷", "护盾弹"]

static func initial_ammo(values: Dictionary) -> Array[int]:
	var ammo: Array[int] = [-1]
	for i: int in range(1, AMMO_NAMES.size()):
		ammo.append(int(values.get("initial_ammo_%d" % i, 1 if i == 2 else 0)))
	return ammo

const TIERS: Array[Array] = [[1,2,4,6,8,14], [5,7,10,11,12,15], [3,9,13]]
const SUPPLY_DEFAULTS: Dictionary = {"early":[1,1,0], "middle":[1,1,1], "late":[1,2,1], "crate":[1,1,1]}

static func supply_counts(values: Dictionary, stage: String) -> Array[int]:
	var counts: Array[int] = []
	for tier: int in 3:
		counts.append(int(values.get("supply_%s_%d" % [stage,tier], SUPPLY_DEFAULTS[stage][tier])))
	return counts

static func schema() -> Dictionary:
	var config: Dictionary = {"schema_format": 3, "settings_version": 1, "fields": {
		"mode": {"type": "string", "default": "ffa", "title": "对战模式",
			"description": "混战 2–8 人；团队对抗 2/4/6/8 人；单人测试 1 人。",
			"audience": "room", "apply": "next_round", "control": "select",
			"values": ["ffa", "teams", "training"], "labels": ["自由混战", "团队对抗", "单人测试"]}
	}, "layout": [{"id": "battle", "title": "对战规则", "expanded": true,
		"children": [{"field": "mode"}]}]}

	var ammunition: Array[Dictionary] = []
	var defaults: Array[int] = initial_ammo({})
	for i: int in range(1, AMMO_NAMES.size()):
		var key: String = "initial_ammo_%d" % i
		config.fields[key] = {"type": "int", "default": defaults[i], "title": AMMO_NAMES[i],
			"min": 0, "max": 20, "audience": "room", "apply": "next_round", "control": "number"}
		ammunition.append({"field": key})
	config.layout.append({"id": "initial_ammo", "title": "初始特殊弹药（标准弹无限，单人测试不受限）",
		"expanded": false, "children": ammunition})
	for stage: String in SUPPLY_DEFAULTS:
		var rows: Array[Dictionary] = []
		var labels: Array[String] = ["基础弹", "进阶弹", "高级弹"]
		var titles: Dictionary = {"early":"第 3 轮配给", "middle":"第 5 轮配给", "late":"第 7 轮起每两轮配给", "crate":"补给箱弹药"}
		for tier: int in 3:
			var key: String = "supply_%s_%d" % [stage,tier]
			config.fields[key] = {"type":"int", "default":SUPPLY_DEFAULTS[stage][tier],
				"title":labels[tier], "min":0, "max":10, "audience":"room", "apply":"next_round", "control":"number"}
			rows.append({"field":key})
		config.layout.append({"id":"supply_"+stage, "title":titles[stage], "expanded":false, "children":rows})
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
