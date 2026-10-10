extends SceneTree
## Engine tests. Run with:
##   godot --headless --path . -s scripts/engine/engine_tests.gd
## Exits with a non-zero code if any check fails.

const T = preload("res://scripts/engine/match_types.gd")
const Shared = preload("res://scripts/engine/match_shared.gd")
const LiveMatch = preload("res://scripts/engine/live_match.gd")
const SquadFactory = preload("res://scripts/engine/squad_factory.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_contest_is_a_bounded_ratio()
	_test_condition_never_zeroes_skill()
	_test_same_seed_replays_the_same_match()
	_test_different_seeds_differ()
	_test_match_runs_to_full_time_with_plausible_length()
	_test_score_matches_goal_events()
	_test_report_matches_stats_shape()
	_test_stronger_team_wins_more_often()
	_test_stamina_depletes_but_squads_are_not_mutated()
	_test_sent_off_players_never_act_again()
	_test_substitution_swaps_players_and_enforces_limit()
	_test_substitution_rejects_unavailable_players()
	_test_play_style_command_changes_the_team()
	_test_squad_factory_is_deterministic_and_complete()
	_test_offsides_are_flagged_and_handed_to_the_defence()
	_test_offside_rate_is_realistic_and_configurable()

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _play(home_id: String, away_id: String, seed_value: int, home_strength := -1.0, away_strength := -1.0) -> RefCounted:
	var match_run := LiveMatch.new(
		SquadFactory.generate(home_id, home_strength),
		SquadFactory.generate(away_id, away_strength),
		seed_value)
	match_run.simulate_to_end()
	return match_run


func _signature(match_run: RefCounted) -> String:
	var parts: PackedStringArray = []
	for event in match_run.events:
		parts.append("%d:%d:%d:%s" % [event.minute, event.type, event.side, event.player_id])
	return ",".join(parts)


func _test_contest_is_a_bounded_ratio() -> void:
	_check(is_equal_approx(Shared.contest(50.0, 50.0), 0.5), "equal values give 50%")
	_check(Shared.contest(80.0, 20.0) > 0.5, "stronger attacker is favoured")
	_check(Shared.contest(99.0, 1.0) < 1.0, "a contest is never a certainty")
	_check(Shared.contest(0.0, 0.0) == 0.5, "two zero values do not divide by zero")


func _test_condition_never_zeroes_skill() -> void:
	_check(is_equal_approx(Shared.condition_factor(100.0), 1.0), "full condition is full skill")
	_check(Shared.condition_factor(0.0) > 0.6, "empty condition still keeps most skill")
	_check(Shared.condition_factor(50.0) < Shared.condition_factor(90.0), "tired plays worse")


func _test_same_seed_replays_the_same_match() -> void:
	var first := _play("a", "b", 7)
	var second := _play("a", "b", 7)
	_check(_signature(first) == _signature(second), "same seed and squads replay identically")


func _test_different_seeds_differ() -> void:
	var signatures := {}
	for seed_value in 10:
		signatures[_signature(_play("a", "b", seed_value))] = true
	_check(signatures.size() > 1, "different seeds produce different matches")


func _test_match_runs_to_full_time_with_plausible_length() -> void:
	var match_run := _play("a", "b", 1)
	_check(match_run.is_finished(), "match reaches FINISHED")
	_check(match_run.minute >= 90 and match_run.minute <= 98, "match lasts 90 plus stoppage (got %d)" % match_run.minute)
	var types: Array = match_run.events.map(func(e): return e.type)
	_check(types.count(T.EventType.HALF_TIME) == 1, "exactly one half-time")
	_check(types.count(T.EventType.FULL_TIME) == 1, "exactly one full-time")
	var last_minute := -1
	var ordered := true
	for event in match_run.events:
		if event.minute < last_minute:
			ordered = false
		last_minute = event.minute
	_check(ordered, "events are chronological")


func _test_score_matches_goal_events() -> void:
	for seed_value in 30:
		var match_run := _play("g-home", "g-away", seed_value)
		var goals := [0, 0]
		for event in match_run.events:
			if event.type == T.EventType.GOAL:
				goals[event.side] += 1
		_check(goals[0] == match_run.score[0] and goals[1] == match_run.score[1], "score equals goal events (seed %d)" % seed_value)


func _test_report_matches_stats_shape() -> void:
	var stats: Dictionary = _play("a", "b", 3).build_report().to_stats_dict()
	for key in ["possession", "shots", "shots_on_target", "corners", "fouls", "offsides", "yellow_cards", "red_cards", "passes", "pass_accuracy"]:
		_check(stats.has(key) and stats[key].size() == 2, "stats has a [home, away] pair for %s" % key)
	_check(stats.possession[0] + stats.possession[1] == 100, "possession sums to 100")
	_check(stats.shots_on_target[0] <= stats.shots[0], "on-target shots never exceed shots")


func _test_stronger_team_wins_more_often() -> void:
	var strong_wins := 0
	var weak_wins := 0
	for seed_value in 200:
		var report: RefCounted = _play("s-%d" % seed_value, "w-%d" % seed_value, seed_value, 70.0, 45.0).build_report()
		if report.score[0] > report.score[1]:
			strong_wins += 1
		elif report.score[1] > report.score[0]:
			weak_wins += 1
	_check(strong_wins > weak_wins * 2, "a much stronger home side wins far more (%d v %d)" % [strong_wins, weak_wins])


func _test_stamina_depletes_but_squads_are_not_mutated() -> void:
	var home := SquadFactory.generate("home")
	var away := SquadFactory.generate("away")
	var starter = home.players[5]
	var before: float = starter.condition
	var match_run := LiveMatch.new(home, away, 1)
	match_run.simulate_to_end()
	_check(match_run.condition_of(starter.id) < before, "in-match condition drops")
	_check(starter.condition == before, "the squad's own condition is untouched")


func _test_sent_off_players_never_act_again() -> void:
	var match_run := LiveMatch.new(SquadFactory.generate("home"), SquadFactory.generate("away"), 1)
	var victim = match_run.home.players[8]
	match_run.sent_off[victim.id] = true
	match_run.simulate_to_end()
	var acted := false
	for event in match_run.events:
		if event.player_id == victim.id or event.secondary_id == victim.id:
			acted = true
	_check(not acted, "a sent-off player appears in no event")


func _test_substitution_swaps_players_and_enforces_limit() -> void:
	var match_run := LiveMatch.new(SquadFactory.generate("home"), SquadFactory.generate("away"), 1)
	var off = match_run.home.players[1]
	var on = match_run.home.bench[1]
	var error := match_run.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": off.id, "player_on": on.id})
	_check(error == "", "a valid substitution succeeds")
	_check(match_run.home.find_on_pitch(on.id) != null and match_run.home.find_on_pitch(off.id) == null, "players are swapped")
	_check(match_run.home.find_on_bench(off.id) != null, "the replaced player goes to the bench")

	var made := 1
	while made < match_run.config.max_subs:
		var next_off = match_run.home.players[made + 1]
		var next_on = match_run.home.bench[made + 1]
		match_run.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": next_off.id, "player_on": next_on.id})
		made += 1
	var extra := match_run.apply_command({"type": "substitute", "side": T.Side.HOME,
		"player_off": match_run.home.players[0].id, "player_on": match_run.home.bench[0].id})
	_check(extra == "sub_limit_reached", "the substitution limit is enforced")


func _test_substitution_rejects_unavailable_players() -> void:
	var match_run := LiveMatch.new(SquadFactory.generate("home"), SquadFactory.generate("away"), 1)
	var unknown_off := match_run.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": "nobody", "player_on": match_run.home.bench[0].id})
	_check(unknown_off == "player_off_unavailable", "unknown player_off is rejected")
	var on_pitch_as_on := match_run.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": match_run.home.players[1].id, "player_on": match_run.home.players[2].id})
	_check(on_pitch_as_on == "player_on_unavailable", "a player already on the pitch cannot come on")


func _test_play_style_command_changes_the_team() -> void:
	var match_run := LiveMatch.new(SquadFactory.generate("home"), SquadFactory.generate("away"), 1)
	_check(match_run.apply_command({"type": "play_style", "side": T.Side.AWAY, "style": T.PlayStyle.COUNTER}) == "", "play style command succeeds")
	_check(match_run.away.play_style == T.PlayStyle.COUNTER, "away play style changed")
	_check(match_run.apply_command({"type": "nonsense"}) == "unknown_command", "unknown commands are reported")


func _test_offsides_are_flagged_and_handed_to_the_defence() -> void:
	var seen := 0
	var stats_agree := true
	var handed_over := true
	for seed_value in 60:
		var match_run := _play("o-home", "o-away", seed_value)
		var counted := [0, 0]
		for i in match_run.events.size():
			var event = match_run.events[i]
			if event.type != T.EventType.OFFSIDE:
				continue
			seen += 1
			counted[event.side] += 1
			var next = match_run.events[i + 1]
			if next.type != T.EventType.FREE_KICK or next.side == event.side:
				handed_over = false
		var stats: Dictionary = match_run.build_report().to_stats_dict()
		if stats.offsides[0] != counted[0] or stats.offsides[1] != counted[1]:
			stats_agree = false
	_check(seen > 0, "offsides occur across 60 matches")
	_check(handed_over, "every offside is followed by a free kick for the other side")
	_check(stats_agree, "the stats offsides equal the OFFSIDE events")


func _test_offside_rate_is_realistic_and_configurable() -> void:
	var total := 0
	for seed_value in 100:
		var offsides: Array = _play("r-home", "r-away", seed_value).build_report().to_stats_dict().offsides
		total += offsides[0] + offsides[1]
	var per_team := total / 200.0
	_check(per_team >= 1.0 and per_team <= 4.5, "about 1 to 4 offsides per team per match (got %.2f)" % per_team)
	var config := preload("res://scripts/engine/match_config.gd").new()
	config.offside_base = 0.0
	var quiet := LiveMatch.new(SquadFactory.generate("r-home"), SquadFactory.generate("r-away"), 5, config)
	quiet.simulate_to_end()
	_check(quiet.events.all(func(e): return e.type != T.EventType.OFFSIDE), "a zero offside rate never flags anyone")


func _test_squad_factory_is_deterministic_and_complete() -> void:
	var first := SquadFactory.generate("alpha")
	var second := SquadFactory.generate("alpha")
	_check(first.players.size() == 11 and first.bench.size() == 7, "11 starters and 7 on the bench")
	_check(first.players[3].passing == second.players[3].passing, "same team id gives the same players")
	_check(first.players[0].position == T.Position.GOALKEEPER and first.players[0].goalkeeping > 50, "slot 0 is a real goalkeeper")
