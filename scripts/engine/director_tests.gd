extends SceneTree
## Headless tests for the sim path: director, result store, settlement, bets.
## Run: godot --headless --path . -s scripts/engine/director_tests.gd

const Settlement = preload("res://scripts/bet_settlement.gd")
const ResultStore = preload("res://scripts/match_result_store.gd")
const MatchRepository = preload("res://scripts/match_repository.gd")
const MatchStatsProvider = preload("res://scripts/match_stats_provider.gd")
const Commentary = preload("res://scripts/match_commentary.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_settlement()
	await _test_sim_flow()
	await _test_watch_flow()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)


func _result(home: int, away: int, ht := [0, 0], first := -1, corners := 10, cards := 4) -> Dictionary:
	return {"score": [home, away], "half_time_score": ht, "first_scoring_side": first,
		"corners_total": corners, "cards_total": cards}


func _outcome(market: String, selection: String, result: Dictionary) -> String:
	return Settlement.leg_outcome(market, selection, result)


func _test_settlement() -> void:
	var r := _result(2, 1, [1, 1], 0)
	_check(_outcome("match_result", "home", r) == "won", "1X2 home wins")
	_check(_outcome("match_result", "draw", r) == "lost", "1X2 draw loses")
	_check(_outcome("double_chance", "draw_away", r) == "lost", "double chance excludes home win")
	_check(_outcome("double_chance", "home_draw", r) == "won", "double chance includes home win")
	_check(_outcome("draw_no_bet", "away", r) == "lost", "DNB away loses")
	_check(_outcome("draw_no_bet", "home", _result(1, 1)) == "void", "DNB draw is void")
	_check(_outcome("total_goals", "over_2.5", r) == "won", "3 goals beats over 2.5")
	_check(_outcome("total_goals", "under_2.5", r) == "lost", "3 goals loses under 2.5")
	_check(_outcome("home_total_goals", "over_1.5", r) == "won", "home 2 beats over 1.5")
	_check(_outcome("away_total_goals", "over_1.5", r) == "lost", "away 1 loses over 1.5")
	_check(_outcome("btts", "yes", r) == "won", "both scored")
	_check(_outcome("btts", "yes", _result(2, 0)) == "lost", "clean sheet loses btts yes")
	_check(_outcome("odd_even", "odd", r) == "won", "3 goals is odd")
	_check(_outcome("first_to_score", "home", r) == "won", "home scored first")
	_check(_outcome("first_to_score", "none", _result(0, 0)) == "won", "goalless: no goal")
	_check(_outcome("handicap", "home_-1", r) == "lost", "2-1 with -1 is a draw, so home -1 loses")
	_check(_outcome("handicap", "draw_-1", r) == "won", "2-1 with -1 is a draw")
	_check(_outcome("handicap", "away_+1", r) == "lost", "away +1 does not hold at 2-1")
	_check(_outcome("handicap", "home_+1", r) == "won", "home +1 wins at 2-1")
	_check(_outcome("half_time_result", "draw", r) == "won", "level at half time")
	_check(_outcome("half_time_full_time", "draw_home", r) == "won", "draw / home")
	_check(_outcome("correct_score", "2-1", r) == "won", "correct score 2-1")
	_check(_outcome("correct_score", "other", _result(4, 0)) == "won", "4-0 is 'other'")
	_check(_outcome("correct_score", "3-3", _result(4, 0)) == "lost", "4-0 is not 3-3")
	_check(_outcome("total_corners", "over_9.5", r) == "won", "10 corners beats 9.5")
	_check(_outcome("total_cards", "under_3.5", _result(0, 0, [0, 0], -1, 8, 4)) == "lost", "4 cards loses under 3.5")

	var win := Settlement.settle(10.0, ["won", "won"], [2.0, 1.5])
	_check(win.status == "won" and is_equal_approx(win.payout, 30.0), "parlay multiplies odds")
	_check(Settlement.settle(10.0, ["won", "lost"], [2.0, 1.5]).status == "lost", "one lost leg loses the parlay")
	var voided := Settlement.settle(10.0, ["won", "void"], [2.0, 1.5])
	_check(is_equal_approx(voided.payout, 20.0), "void leg counts as odds 1")
	_check(Settlement.settle(10.0, ["void"], [2.0]).status == "void", "all void refunds")


func _test_sim_flow() -> void:
	await process_frame
	var director: Node = root.get_node("MatchDirector")
	var bets: Node = root.get_node("BetManager")
	var fixtures: Array = MatchRepository.get_leagues()[0].matches
	var upcoming: Array = fixtures.filter(func(m): return m.status == "NS")
	var target: Dictionary = upcoming[0]
	var id: String = target.id

	var first: Dictionary = director.sim(id)
	_check(not first.is_empty(), "sim returns a result")
	_check(target.status == "FT", "fixture is marked full time")
	_check(target.home_score == first.score[0] and target.away_score == first.score[1], "fixture holds the score")
	_check(director.sim(id) == first, "second sim does not re-roll")
	_check(MatchStatsProvider.get_stats(id) == first.stats, "stats come from the result store")

	var live: RefCounted = director.create_live_match(upcoming[1].id, 777)
	live.simulate_to_end()
	var same_seed_run: RefCounted = director.create_live_match(upcoming[1].id, 777)
	same_seed_run.simulate_to_end()
	_check(live.score == same_seed_run.score, "an explicit seed replays the same score")
	var varied := {}
	for i in 30:
		var run: RefCounted = director.create_live_match(upcoming[1].id)
		run.simulate_to_end()
		varied[str(run.score)] = true
	_check(varied.size() > 1, "the same fixture does not always end the same")

	var next_target: Dictionary = upcoming[2]
	var finished := []
	director.match_finished.connect(func(match_id, _result): finished.append(match_id))
	var bet_stake := 10.0
	bets.slip.clear()
	bets.slip[next_target.id] = {
		"match_id": next_target.id, "home": next_target.home, "away": next_target.away,
		"date": next_target.date, "kickoff": next_target.kickoff, "market_id": "btts",
		"market_name": "Both Teams To Score", "selection_id": "yes", "selection_name": "Yes", "odds": 2.0,
	}
	var before: float = bets.balance
	var bet: Dictionary = bets.place_bet(bet_stake, "test")
	_check(not bet.is_empty() and bets.balance == before - bet_stake, "bet placed and stake taken")
	var result: Dictionary = director.sim(next_target.id)
	var won: bool = result.score[0] > 0 and result.score[1] > 0
	_check(bet.status == ("won" if won else "lost"), "bet settled by result")
	_check(is_equal_approx(bets.balance, before + (bet_stake if won else -bet_stake)), "balance reflects the payout")
	var balance_after: float = bets.balance
	director.sim(next_target.id)
	_check(bets.balance == balance_after, "bet settles only once")
	_check(finished.size() == 1, "match_finished fires once per match")

	var played: int = director.sim_day(upcoming[3].date)
	_check(played > 0, "sim_day plays the remaining fixtures")
	_check(director.sim_day(upcoming[3].date) == 0, "sim_day is idempotent")
	ResultStore.clear()
	MatchRepository.reset()


func _test_watch_flow() -> void:
	var director: Node = root.get_node("MatchDirector")
	var bets: Node = root.get_node("BetManager")
	var fixture: Dictionary = MatchRepository.get_leagues()[0].matches.filter(func(m): return m.status == "NS")[0]
	var id: String = fixture.id
	var session: RefCounted = director.watch(id)
	_check(session != null and director.watch(id) == session, "watch returns one session per match")
	_check(fixture.status == "LIVE" and not bets.is_bettable(fixture), "a watched match is live and not bettable")
	_check(director.sim_day(fixture.date) > 0 and director.get_session(id) != null, "sim_day completes live sessions too")
	_check(fixture.status == "FT" and ResultStore.has_result(id), "finished session is recorded")

	var other: Dictionary = MatchRepository.get_leagues()[0].matches.filter(func(m): return m.status == "NS")[0]
	var watched: RefCounted = director.watch(other.id)
	var seen_minutes := []
	watched.minute_played.connect(func(m, _e): seen_minutes.append(m))
	watched.advance(0.5)
	_check(seen_minutes.is_empty(), "less than one match minute of time plays nothing")
	watched.advance(0.4)
	_check(seen_minutes.size() == 1, "a full match minute of time plays one minute")
	watched.set_speed(8)
	watched.advance(0.8)
	_check(seen_minutes.size() == 9, "8x speed plays eight minutes per 0.8s")
	watched.paused = true
	watched.advance(10.0)
	_check(seen_minutes.size() == 9, "paused playback does not advance")
	watched.paused = false
	var halted := []
	watched.half_time.connect(func(): halted.append(true))
	for i in 20:
		watched.advance(0.8)
	_check(watched.paused and halted.size() == 1 and watched.live.phase == 2, "playback pauses at half time")
	watched.resume()
	var final: Dictionary = director.sim(other.id)
	_check(not final.is_empty() and other.status == "FT", "sim finishes a watched match")
	_check(final.score == watched.live.score, "the finished result is the watched match's score")
	_check(final.score[0] == other.home_score, "fixture score matches the result")

	var events: Array = watched.live.events
	var lines := events.filter(func(e): return Commentary.is_notable(e)).map(func(e): return Commentary.line(e, watched.live))
	_check(not lines.is_empty() and not lines.has(""), "every notable event has a commentary line")
	var goals := events.filter(func(e): return e.type == 11)
	_check(goals.size() == final.score[0] + final.score[1], "commentary covers every goal event")
	ResultStore.clear()
	MatchRepository.reset()
