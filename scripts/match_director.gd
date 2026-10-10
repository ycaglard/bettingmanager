extends Node
## Plays matches (autoload "MatchDirector"). Every match is decided by exactly one
## LiveMatch with a random seed, so the same fixture can end differently each run.
## Results are recorded once; a finished match is never re-rolled.

signal match_finished(match_id: String, result: Dictionary)
## Fired after every minute of a watched match, for screens that mirror the score.
signal session_updated(match_id: String)

const MatchPlayback = preload("res://scripts/match_playback.gd")
const MatchManager = preload("res://scripts/engine/match_manager.gd")

## match_id -> MatchPlayback for matches that are being (or were) watched.
var _sessions: Dictionary = {}
const LiveMatch = preload("res://scripts/engine/live_match.gd")
const T = preload("res://scripts/engine/match_types.gd")
const TeamStore = preload("res://scripts/team_store.gd")
const MatchResultStore = preload("res://scripts/match_result_store.gd")
const MatchRepository = preload("res://scripts/match_repository.gd")


## A fresh, unplayed engine for a fixture, or null if the match is unknown.
## Each match gets a random seed; the outcome is fixed only once it is recorded.
func create_live_match(match_id: String, match_seed := -1) -> RefCounted:
	var fixture := MatchRepository.find_match(match_id)
	if fixture.is_empty():
		return null
	if match_seed < 0:
		match_seed = randi()
	var live := LiveMatch.new(TeamStore.get_team(fixture.home), TeamStore.get_team(fixture.away), match_seed)
	live.managers = [MatchManager.new(T.Side.HOME), MatchManager.new(T.Side.AWAY)]
	return live


## Plays a fixture to full time instantly. If it is being watched, the rest of
## that same match is played out. Returns the stored result, or {} if unknown.
func sim(match_id: String) -> Dictionary:
	if MatchResultStore.has_result(match_id):
		return MatchResultStore.get_result(match_id)
	if _sessions.has(match_id):
		_sessions[match_id].skip_to_end()
		return MatchResultStore.get_result(match_id)
	var fixture := MatchRepository.find_match(match_id)
	if fixture.is_empty() or fixture.get("status", "") != "NS":
		return {}
	var live := create_live_match(match_id)
	live.simulate_to_end()
	return finish(match_id, live)


## Starts (or returns the running) live session for a fixture, or null if it
## cannot be watched. The match is decided by this one session.
func watch(match_id: String) -> RefCounted:
	if _sessions.has(match_id):
		return _sessions[match_id]
	var fixture := MatchRepository.find_match(match_id)
	if fixture.is_empty() or fixture.get("status", "") != "NS":
		return null
	var playback: RefCounted = MatchPlayback.new(create_live_match(match_id))
	_sessions[match_id] = playback
	MatchRepository.set_live(match_id)
	playback.minute_played.connect(_on_minute_played.bind(match_id, playback))
	playback.finished.connect(func(): finish(match_id, playback.live))
	return playback


func get_session(match_id: String) -> RefCounted:
	return _sessions.get(match_id)


func find_fixture(match_id: String) -> Dictionary:
	return MatchRepository.find_match(match_id)


func _on_minute_played(_minute: int, _events: Array, match_id: String, playback: RefCounted) -> void:
	MatchRepository.update_score(match_id, playback.live.score)
	session_updated.emit(match_id)


## Plays every unplayed fixture on a dd/mm/yy date. Returns how many were played.
func sim_day(date: String) -> int:
	var played := 0
	for league in MatchRepository.get_leagues():
		for fixture in league.matches:
			if fixture.get("date", "") == date and fixture.get("status", "") in ["NS", "LIVE"]:
				if not sim(fixture.id).is_empty():
					played += 1
	return played


## Records a finished LiveMatch as the match's result and announces it.
func finish(match_id: String, live: RefCounted) -> Dictionary:
	if MatchResultStore.has_result(match_id):
		return MatchResultStore.get_result(match_id)
	var result := build_result(match_id, live)
	MatchResultStore.put(match_id, result)
	MatchRepository.apply_result(match_id, result)
	match_finished.emit(match_id, result)
	return result


func build_result(match_id: String, live: RefCounted) -> Dictionary:
	var report: RefCounted = live.build_report()
	return {
		"match_id": match_id,
		"score": report.score.duplicate(),
		"half_time_score": report.half_time_score.duplicate(),
		"first_scoring_side": report.first_scoring_side,
		"corners_total": report.corners[0] + report.corners[1],
		"cards_total": report.yellow_cards[0] + report.yellow_cards[1] + report.red_cards[0] + report.red_cards[1],
		"stats": report.to_stats_dict(),
		"goals": report.goals.duplicate(true),
		"seed": live.seed_used,
	}
