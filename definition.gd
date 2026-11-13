## Lightweight catalog data. Do not load gameplay scenes or scripts here.
extends RefCounted

static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "player_count_rules": [{"when": {"mode": "ffa"}, "counts": [2, 3, 4, 5, 6, 7, 8]}, {"when": {"mode": "teams"}, "counts": [2, 4, 6, 8]}, {"when": {"mode": "training"}, "counts": [1]}]}
