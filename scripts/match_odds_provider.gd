extends RefCounted
## Provides betting markets and odds by match id. Currently backed by a static
## JSON file; replace with the real odds source later.
##
## Shape of get_odds(match_id):
## {
##   "match_id", "home", "away", "margin", "expected_goals": [home, away],
##   "markets": [
##     { "id": "match_result", "name": "Match Result",
##       "selections": [ { "id": "home", "name": "...", "odds": 1.85, "line"?: 2.5 }, ... ] },
##     ...
##   ]
## }

const SOURCE_PATH := "res://data/match_odds.json"

static var _cache: Dictionary = {}


static func get_odds(match_id: String) -> Dictionary:
	_ensure_loaded()
	return _cache.get(match_id, {})


static func get_markets(match_id: String) -> Array:
	return get_odds(match_id).get("markets", [])


static func get_market(match_id: String, market_id: String) -> Dictionary:
	for market in get_markets(match_id):
		if market.id == market_id:
			return market
	return {}


static func get_selection(match_id: String, market_id: String, selection_id: String) -> Dictionary:
	for selection in get_market(match_id, market_id).get("selections", []):
		if selection.id == selection_id:
			return selection
	return {}


static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to load match odds from %s" % SOURCE_PATH)
		return
	_cache = parsed
