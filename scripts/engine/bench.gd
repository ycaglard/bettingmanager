extends SceneTree
## Balance bench: plays many seeded matches and prints averages, so tuning
## changes can be judged on numbers instead of a feel.
##
##   godot --headless --path . -s scripts/engine/bench.gd -- [matches]
##
## Reference targets for a typical league: about 2.5-2.8 goals per match, a home
## win rate near 45%, ~25% draws, and roughly 10-14 shots per side.

const T = preload("res://scripts/engine/match_types.gd")
const LiveMatch = preload("res://scripts/engine/live_match.gd")
const SquadFactory = preload("res://scripts/engine/squad_factory.gd")

const DEFAULT_MATCHES := 1000


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else DEFAULT_MATCHES

	print("== Even teams (strength 55 v 55), %d matches ==" % matches)
	_report(_run(matches, 55.0, 55.0))
	print("== Favourite v underdog (62 v 48), %d matches ==" % matches)
	_report(_run(matches, 62.0, 48.0))
	quit()


func _run(matches: int, home_strength: float, away_strength: float) -> Dictionary:
	var totals := {
		"goals": 0.0, "home_wins": 0, "draws": 0, "away_wins": 0,
		"shots": 0.0, "on_target": 0.0, "possession": 0.0, "fouls": 0.0,
		"yellows": 0.0, "reds": 0.0, "corners": 0.0, "passes": 0.0, "minutes": 0.0,
		"matches": matches,
	}
	for index in matches:
		var home := SquadFactory.generate("bench-home-%d" % index, home_strength)
		var away := SquadFactory.generate("bench-away-%d" % index, away_strength)
		var match_run := LiveMatch.new(home, away, index)
		var report: RefCounted = match_run.simulate_to_end()
		var stats: Dictionary = report.to_stats_dict()
		var goal_diff: int = report.score[0] - report.score[1]
		totals.goals += report.score[0] + report.score[1]
		totals.home_wins += 1 if goal_diff > 0 else 0
		totals.draws += 1 if goal_diff == 0 else 0
		totals.away_wins += 1 if goal_diff < 0 else 0
		totals.shots += stats.shots[0] + stats.shots[1]
		totals.on_target += stats.shots_on_target[0] + stats.shots_on_target[1]
		totals.possession += stats.possession[0]
		totals.fouls += stats.fouls[0] + stats.fouls[1]
		totals.yellows += stats.yellow_cards[0] + stats.yellow_cards[1]
		totals.reds += stats.red_cards[0] + stats.red_cards[1]
		totals.corners += stats.corners[0] + stats.corners[1]
		totals.passes += stats.passes[0] + stats.passes[1]
		totals.minutes += report.minutes_played
	return totals


func _report(totals: Dictionary) -> void:
	var n: float = totals.matches
	print("  goals/match        %.2f" % (totals.goals / n))
	print("  home / draw / away %.0f%% / %.0f%% / %.0f%%" % [
		100.0 * totals.home_wins / n, 100.0 * totals.draws / n, 100.0 * totals.away_wins / n])
	print("  shots/match        %.1f (on target %.1f)" % [totals.shots / n, totals.on_target / n])
	print("  home possession    %.1f%%" % (totals.possession / n))
	print("  fouls/match        %.1f" % (totals.fouls / n))
	print("  yellows / reds     %.2f / %.3f" % [totals.yellows / n, totals.reds / n])
	print("  corners/match      %.1f" % (totals.corners / n))
	print("  passes/match       %.0f" % (totals.passes / n))
	print("  avg length (min)   %.1f" % (totals.minutes / n))
