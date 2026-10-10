extends RefCounted
## Turns engine events into commentary lines. Routine events (passes, tackles)
## return "" so the feed only shows moments worth reading.

const T = preload("res://scripts/engine/match_types.gd")


## Whether an event deserves a line in the feed and a mark on the timeline.
static func is_notable(event: RefCounted) -> bool:
	match event.type:
		T.EventType.KICK_OFF, T.EventType.HALF_TIME, T.EventType.FULL_TIME, \
		T.EventType.GOAL, T.EventType.SHOT_SAVED, T.EventType.SHOT_OFF_TARGET, \
		T.EventType.SHOT_BLOCKED, T.EventType.CORNER, T.EventType.YELLOW_CARD, \
		T.EventType.RED_CARD, T.EventType.PENALTY_AWARDED, T.EventType.PENALTY_MISSED, \
		T.EventType.SUBSTITUTION, T.EventType.OFFSIDE:
			return true
	return false


## live: the LiveMatch, used to resolve player ids and team names.
static func line(event: RefCounted, live: RefCounted) -> String:
	var team := _team_name(live, event.side)
	var actor := _player_name(live, event.player_id)
	match event.type:
		T.EventType.KICK_OFF:
			return "We are underway."
		T.EventType.HALF_TIME:
			return "Half time. %s %d - %d %s." % [live.home.display_name, live.score[0], live.score[1], live.away.display_name]
		T.EventType.FULL_TIME:
			return "Full time. %s %d - %d %s." % [live.home.display_name, live.score[0], live.score[1], live.away.display_name]
		T.EventType.GOAL:
			return _goal_line(event, live, team, actor)
		T.EventType.SHOT_SAVED:
			return "%s tests the keeper, who saves it." % actor
		T.EventType.SHOT_OFF_TARGET:
			return "%s fires wide." % actor
		T.EventType.SHOT_BLOCKED:
			return "%s's shot is blocked." % actor
		T.EventType.CORNER:
			return "Corner to %s." % team
		T.EventType.YELLOW_CARD:
			return "Yellow card for %s." % actor
		T.EventType.RED_CARD:
			return "Red card! %s is sent off, %s are down to ten." % [actor, team]
		T.EventType.PENALTY_AWARDED:
			return "Penalty to %s!" % team
		T.EventType.PENALTY_MISSED:
			return "%s misses the penalty!" % actor
		T.EventType.OFFSIDE:
			return "%s is flagged offside." % actor
		T.EventType.SUBSTITUTION:
			return "%s substitution: %s replaces %s." % [team, _player_name(live, event.secondary_id), actor]
	return ""


static func _goal_line(event: RefCounted, live: RefCounted, team: String, scorer: String) -> String:
	var text := "GOAL! %s scores for %s." % [scorer, team]
	if event.detail.get("penalty", false):
		text = "GOAL! %s converts the penalty for %s." % [scorer, team]
	elif event.secondary_id != "":
		text += " Assisted by %s." % _player_name(live, event.secondary_id)
	return "%s (%d - %d)" % [text, live.score[0], live.score[1]]


static func _team_name(live: RefCounted, side: int) -> String:
	return (live.home if side == T.Side.HOME else live.away).display_name


static func _player_name(live: RefCounted, player_id: String) -> String:
	for team in [live.home, live.away]:
		for player in team.players + team.bench:
			if player.id == player_id:
				return player.display_name
	return "Someone"
