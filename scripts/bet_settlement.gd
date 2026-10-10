extends RefCounted
## Decides whether a bet leg won, lost or is void, from a finished match result.
## Market and selection ids match data/match_odds.json.

const WON := "won"
const LOST := "lost"
const VOID := "void"

const HOME := 0
const AWAY := 1


## result: {score, half_time_score, first_scoring_side, corners_total, cards_total}.
static func leg_outcome(market_id: String, selection_id: String, result: Dictionary) -> String:
	var score: Array = result.score
	var home: int = score[HOME]
	var away: int = score[AWAY]
	match market_id:
		"match_result":
			return _won_if(selection_id == _winner(home, away))
		"double_chance":
			return _won_if(_winner(home, away) in selection_id.split("_"))
		"draw_no_bet":
			if home == away:
				return VOID
			return _won_if(selection_id == _winner(home, away))
		"total_goals":
			return _line_outcome(selection_id, home + away)
		"home_total_goals":
			return _line_outcome(selection_id, home)
		"away_total_goals":
			return _line_outcome(selection_id, away)
		"total_corners":
			return _line_outcome(selection_id, int(result.corners_total))
		"total_cards":
			return _line_outcome(selection_id, int(result.cards_total))
		"btts":
			return _won_if((selection_id == "yes") == (home > 0 and away > 0))
		"odd_even":
			return _won_if((selection_id == "odd") == ((home + away) % 2 == 1))
		"first_to_score":
			return _won_if(selection_id == _first_scorer(result))
		"handicap":
			return _handicap_outcome(selection_id, home, away)
		"half_time_result":
			var ht: Array = result.half_time_score
			return _won_if(selection_id == _winner(ht[HOME], ht[AWAY]))
		"half_time_full_time":
			var half: Array = result.half_time_score
			return _won_if(selection_id == "%s_%s" % [_winner(half[HOME], half[AWAY]), _winner(home, away)])
		"correct_score":
			return _won_if(selection_id == _score_key(home, away))
	push_warning("Unknown market '%s'; voiding the leg." % market_id)
	return VOID


## Combines leg outcomes into {status, payout}. Void legs count as odds 1.0.
static func settle(stake: float, leg_outcomes: Array, leg_odds: Array) -> Dictionary:
	var multiplier := 1.0
	var any_won := false
	for i in leg_outcomes.size():
		match leg_outcomes[i]:
			LOST:
				return {"status": LOST, "payout": 0.0}
			WON:
				any_won = true
				multiplier *= float(leg_odds[i])
	if not any_won:
		return {"status": VOID, "payout": snappedf(stake, 0.01)}
	return {"status": WON, "payout": snappedf(stake * multiplier, 0.01)}


static func _won_if(condition: bool) -> String:
	return WON if condition else LOST


static func _winner(home: int, away: int) -> String:
	if home > away:
		return "home"
	return "away" if away > home else "draw"


static func _first_scorer(result: Dictionary) -> String:
	match int(result.first_scoring_side):
		HOME:
			return "home"
		AWAY:
			return "away"
	return "none"


static func _score_key(home: int, away: int) -> String:
	if home > 3 or away > 3:
		return "other"
	return "%d-%d" % [home, away]


## Selection ids look like "over_2.5" or "under_9.5"; lines end in .5 so no pushes.
static func _line_outcome(selection_id: String, total: int) -> String:
	var parts := selection_id.split("_")
	var line := float(parts[1])
	return _won_if((parts[0] == "over") == (float(total) > line))


## Selection ids look like "home_-1": the line is applied to the home goals.
static func _handicap_outcome(selection_id: String, home: int, away: int) -> String:
	var parts := selection_id.split("_")
	var adjusted := home + int(parts[1]) - away
	var outcome := "home" if adjusted > 0 else ("away" if adjusted < 0 else "draw")
	return _won_if(parts[0] == outcome)
