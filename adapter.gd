extends RefCounted
## Artillery supports the standard ranking contract; it does not consume resources.
func check_request(request: Dictionary) -> Dictionary:
	if request.mode != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "火炮大战仅支持普通排名局"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
