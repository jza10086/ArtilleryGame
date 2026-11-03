extends RefCounted
## Room-owned mode; the manifest narrows valid participant counts before launch.
static func schema() -> Dictionary:
	return {"schema_format": 3, "settings_version": 1, "fields": {
		"mode": {"type": "string", "default": "ffa", "title": "对战模式",
			"description": "混战 2–8 人；团队对抗 2/4/6/8 人；单人测试 1 人。",
			"audience": "room", "apply": "next_round", "control": "select",
			"values": ["ffa", "teams", "training"], "labels": ["自由混战", "团队对抗", "单人测试"]}
	}, "layout": [{"id": "battle", "title": "对战规则", "expanded": true,
		"children": [{"field": "mode"}]}]}
