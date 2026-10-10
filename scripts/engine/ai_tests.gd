extends SceneTree
## Tests for the AI manager. Run:
##   godot --headless --path . -s scripts/engine/ai_tests.gd -- [matches]

const T = preload("res://scripts/engine/match_types.gd")
const LiveMatch = preload("res://scripts/engine/live_match.gd")
const MatchManager = preload("res://scripts/engine/match_manager.gd")
const SquadFactory = preload("res://scripts/engine/squad_factory.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_test_chasing_team_goes_attacking()
	_test_protecting_team_goes_defensive()
	_test_level_match_keeps_the_base_style()
	_test_tired_player_is_replaced_by_the_same_position()
	_test_substituted_player_cannot_return()
	_test_manager_respects_the_substitution_limit()
	_test_no_changes_before_the_decision_window()
	_test_managed_match_is_reproducible()
	_test_managed_matches_stay_plausible()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)


func _new_match(seed_value := 1) -> RefCounted:
	var live := LiveMatch.new(SquadFactory.generate("a", 55.0), SquadFactory.generate("b", 55.0), seed_value)
	live.managers = [MatchManager.new(T.Side.HOME), MatchManager.new(T.Side.AWAY)]
	return live


## Puts the match at `minute` with `score` without playing it.
func _at(minute: int, score: Array) -> RefCounted:
	var live := _new_match()
	live.minute = minute
	live.phase = T.Phase.SECOND_HALF
	live.score.assign(score)
	return live


## The minute a manager acts on: its side index modulo the interval.
func _decision_minute(base: int, side: int) -> int:
	return base - (base % MatchManager.DECISION_INTERVAL) + side


func _styles(commands: Array) -> Array:
	return commands.filter(func(c): return c.type == "play_style").map(func(c): return c.style)


func _test_chasing_team_goes_attacking() -> void:
	var live := _at(_decision_minute(66, T.Side.HOME), [0, 1])
	_check(_styles(live.managers[T.Side.HOME].decide(live)) == [T.PlayStyle.ATTACKING], "trailing late: home attacks")


func _test_protecting_team_goes_defensive() -> void:
	var live := _at(_decision_minute(80, T.Side.AWAY), [0, 1])
	_check(_styles(live.managers[T.Side.AWAY].decide(live)) == [T.PlayStyle.DEFENSIVE], "leading late: away defends")


func _test_level_match_keeps_the_base_style() -> void:
	var live := _at(_decision_minute(80, T.Side.HOME), [1, 1])
	_check(_styles(live.managers[T.Side.HOME].decide(live)).is_empty(), "level: no style change")
	var early := _at(_decision_minute(30, T.Side.HOME), [0, 2])
	early.phase = T.Phase.FIRST_HALF
	_check(_styles(early.managers[T.Side.HOME].decide(early)).is_empty(), "trailing early: no panic")


func _test_tired_player_is_replaced_by_the_same_position() -> void:
	var live := _at(_decision_minute(75, T.Side.HOME), [1, 1])
	var tired: RefCounted = live.home.players[6]
	live._conditions[tired.id] = 10.0
	var commands: Array = live.managers[T.Side.HOME].decide(live)
	var subs := commands.filter(func(c): return c.type == "substitute")
	_check(subs.size() == 1 and subs[0].player_off == tired.id, "the most tired player comes off")
	var on_player: RefCounted = live.home.find_on_bench(subs[0].player_on)
	_check(on_player != null and on_player.position == tired.position, "the replacement plays the same position")
	_check(live.apply_command(subs[0]) == "", "the engine accepts the substitution")


func _test_substituted_player_cannot_return() -> void:
	var live := _at(_decision_minute(75, T.Side.HOME), [1, 1])
	var off: RefCounted = live.home.players[6]
	var on: RefCounted = live.home.bench[3]
	live.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": off.id, "player_on": on.id})
	var back: String = live.apply_command({"type": "substitute", "side": T.Side.HOME, "player_off": on.id, "player_on": off.id})
	_check(back == "player_on_unavailable", "a player taken off cannot come back on")


func _test_manager_respects_the_substitution_limit() -> void:
	var live := _at(_decision_minute(80, T.Side.HOME), [0, 0])
	live.subs_made[T.Side.HOME] = live.config.max_subs
	live._conditions[live.home.players[6].id] = 5.0
	var subs: Array = live.managers[T.Side.HOME].decide(live).filter(func(c): return c.type == "substitute")
	_check(subs.is_empty(), "no substitution once the limit is used")


func _test_no_changes_before_the_decision_window() -> void:
	var live := _at(_decision_minute(80, T.Side.HOME) + 1, [0, 1])
	_check(live.managers[T.Side.HOME].decide(live).is_empty(), "the manager acts only on its own minutes")


func _test_managed_match_is_reproducible() -> void:
	var first := _new_match(99)
	first.simulate_to_end()
	var second := _new_match(99)
	second.simulate_to_end()
	_check(first.events.size() == second.events.size() and first.score == second.score, "same seed gives the same managed match")


func _test_managed_matches_stay_plausible() -> void:
	var runs := 300
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	var subs := 0
	var goals := 0
	var illegal := 0
	for i in runs:
		var live := _new_match(i + 1)
		live.simulate_to_end()
		subs += live.subs_made[0] + live.subs_made[1]
		goals += live.score[0] + live.score[1]
		for side in 2:
			if live.subs_made[side] > live.config.max_subs:
				illegal += 1
	var subs_per_team := subs / (2.0 * runs)
	print("AI bench: %.2f subs per team, %.2f goals per match" % [subs_per_team, float(goals) / runs])
	_check(illegal == 0, "no side exceeds the substitution limit")
	_check(subs_per_team >= 1.5 and subs_per_team <= 5.0, "teams use a realistic number of substitutions")
	_check(float(goals) / runs > 2.0 and float(goals) / runs < 3.8, "goals per match stay realistic")
