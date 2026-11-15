extends RefCounted

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}

## Artillery supports the standard ranking contract; it does not consume resources.
func check_request(request: Dictionary) -> Dictionary:
	if request.mode != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "炮火争锋仅支持普通排名局"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
