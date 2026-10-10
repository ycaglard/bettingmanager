extends RefCounted
## Provides per-match statistics by match id. Currently backed by a static
## JSON file; replace with the real data bank source later.

const MatchResultStore = preload("res://scripts/match_result_store.gd")
const SOURCE_PATH := "res://data/match_stats.json"

static var _cache: Dictionary = {}


static func get_stats(match_id: String) -> Dictionary:
	var played := MatchResultStore.get_result(match_id)
	if not played.is_empty():
		return played.stats
	if _cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Failed to load match stats from %s" % SOURCE_PATH)
			return {}
		_cache = parsed
	return _cache.get(match_id, {})
