extends RefCounted
## In-memory record of every match played so far, keyed by match id. Static so
## the repository and stats provider can read it without a scene tree.
## Results are not saved to disk: the calendar is not saved either.

## match_id -> result Dictionary (see MatchDirector.build_result).
static var _results: Dictionary = {}


static func has_result(match_id: String) -> bool:
	return _results.has(match_id)


static func get_result(match_id: String) -> Dictionary:
	return _results.get(match_id, {})


static func put(match_id: String, result: Dictionary) -> void:
	_results[match_id] = result


static func clear() -> void:
	_results.clear()
