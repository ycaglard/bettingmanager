extends RefCounted
## Statistics derived from a finished (or running) match's event list.

const T = preload("res://scripts/engine/match_types.gd")

var score: Array[int] = [0, 0]
## The score when the half-time whistle went; [0, 0] until the half has ended.
var half_time_score: Array[int] = [0, 0]
## Side of the first goal, or -1 while the match is goalless.
var first_scoring_side := -1
var minutes_played := 0
## Per-side [home, away] counters; see to_stats_dict() for the key names.
var shots: Array[int] = [0, 0]
var shots_on_target: Array[int] = [0, 0]
var corners: Array[int] = [0, 0]
var fouls: Array[int] = [0, 0]
var offsides: Array[int] = [0, 0]
var yellow_cards: Array[int] = [0, 0]
var red_cards: Array[int] = [0, 0]
var passes: Array[int] = [0, 0]
var passes_completed: Array[int] = [0, 0]
var possession_ticks: Array[int] = [0, 0]
## One entry per goal: {minute, side, scorer_id, assister_id, penalty}.
var goals: Array[Dictionary] = []
## player_id -> {goals, assists, yellow_cards, red_cards}.
var player_stats: Dictionary = {}


static func from_events(events: Array, ticks: Array, minutes: int) -> RefCounted:
	var report := new()
	report.minutes_played = minutes
	report.possession_ticks = [int(ticks[0]), int(ticks[1])]
	for event in events:
		report._count(event)
	return report


## The same shape as data/match_stats.json so the Matches tab can show it as is.
func to_stats_dict() -> Dictionary:
	var total_ticks := possession_ticks[0] + possession_ticks[1]
	var home_possession := 50 if total_ticks == 0 else int(round(100.0 * possession_ticks[0] / total_ticks))
	return {
		"possession": [home_possession, 100 - home_possession],
		"shots": shots.duplicate(),
		"shots_on_target": shots_on_target.duplicate(),
		"corners": corners.duplicate(),
		"fouls": fouls.duplicate(),
		"offsides": offsides.duplicate(),
		"yellow_cards": yellow_cards.duplicate(),
		"red_cards": red_cards.duplicate(),
		"passes": passes.duplicate(),
		"pass_accuracy": [_accuracy(T.Side.HOME), _accuracy(T.Side.AWAY)],
	}


func _accuracy(side: int) -> int:
	if passes[side] == 0:
		return 0
	return int(round(100.0 * passes_completed[side] / passes[side]))


func _count(event: RefCounted) -> void:
	var side: int = event.side
	match event.type:
		T.EventType.PASS:
			passes[side] += 1
			passes_completed[side] += 1
		T.EventType.PASS_INTERCEPTED:
			passes[side] += 1
		T.EventType.OFFSIDE:
			passes[side] += 1
			offsides[side] += 1
		T.EventType.SHOT_OFF_TARGET, T.EventType.SHOT_BLOCKED:
			shots[side] += 1
		T.EventType.SHOT_SAVED:
			shots[side] += 1
			shots_on_target[side] += 1
		T.EventType.GOAL:
			_count_goal(event)
		T.EventType.HALF_TIME:
			half_time_score = score.duplicate()
		T.EventType.CORNER:
			corners[side] += 1
		T.EventType.FOUL:
			fouls[side] += 1
		T.EventType.YELLOW_CARD:
			yellow_cards[side] += 1
			_player(event.player_id).yellow_cards += 1
		T.EventType.RED_CARD:
			red_cards[side] += 1
			_player(event.player_id).red_cards += 1


func _count_goal(event: RefCounted) -> void:
	var side: int = event.side
	var is_penalty: bool = event.detail.get("penalty", false)
	if first_scoring_side == -1:
		first_scoring_side = side
	score[side] += 1
	# A penalty is a goal but not an open-play shot in the shot count.
	if not is_penalty:
		shots[side] += 1
		shots_on_target[side] += 1
	goals.append({
		"minute": event.minute,
		"side": side,
		"scorer_id": event.player_id,
		"assister_id": event.secondary_id,
		"penalty": is_penalty,
	})
	_player(event.player_id).goals += 1
	if event.secondary_id != "":
		_player(event.secondary_id).assists += 1


func _player(player_id: String) -> Dictionary:
	if not player_stats.has(player_id):
		player_stats[player_id] = {"goals": 0, "assists": 0, "yellow_cards": 0, "red_cards": 0}
	return player_stats[player_id]
