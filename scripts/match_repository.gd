extends RefCounted
## Provides league and match data. Currently backed by a static JSON file;
## replace the loading logic here once match generation is implemented.

const SOURCE_PATH := "res://data/matches.json"

static var _cache: Dictionary = {}


static func get_leagues() -> Array:
	if _cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Failed to load match data from %s" % SOURCE_PATH)
			return []
		_cache = parsed
	return _cache.get("leagues", [])


## The fixture with this id, or an empty Dictionary.
static func find_match(match_id: String) -> Dictionary:
	for league in get_leagues():
		for fixture in league.matches:
			if fixture.id == match_id:
				return fixture
	return {}


## Marks a fixture as full time with the result's score.
static func apply_result(match_id: String, result: Dictionary) -> void:
	var fixture := find_match(match_id)
	if fixture.is_empty():
		return
	fixture["home_score"] = result.score[0]
	fixture["away_score"] = result.score[1]
	fixture["status"] = "FT"


## Marks a fixture as in play so it can no longer be bet on.
static func set_live(match_id: String) -> void:
	var fixture := find_match(match_id)
	if not fixture.is_empty() and fixture.get("status", "") == "NS":
		fixture["status"] = "LIVE"
		fixture["home_score"] = 0
		fixture["away_score"] = 0


## Mirrors the running score onto the fixture while it is being watched.
static func update_score(match_id: String, score: Array) -> void:
	var fixture := find_match(match_id)
	if not fixture.is_empty() and fixture.get("status", "") == "LIVE":
		fixture["home_score"] = score[0]
		fixture["away_score"] = score[1]


## Forgets cached fixtures so they reload from disk (used by tests).
static func reset() -> void:
	_cache = {}
