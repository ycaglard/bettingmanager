extends SceneTree
## Headless UI smoke test: Matches tab Watch/Sim buttons and the live screen.
## Run: godot --headless --path . -s scripts/engine/ui_tests.gd

const ResultStore = preload("res://scripts/match_result_store.gd")
const MatchRepository = preload("res://scripts/match_repository.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await _run()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var game: Control = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var matches: Control = game.get_node("Layout/Tabs/Matches")
	var director: Node = root.get_node("MatchDirector")
	var fixtures: Array = MatchRepository.get_leagues()[0].matches.filter(func(m): return m.status == "NS")
	var target: Dictionary = fixtures[0]

	matches._show_details(target, MatchRepository.get_leagues()[0])
	_check(matches._watch_button.visible and matches._sim_button.visible, "upcoming match shows Watch and Sim")
	matches._on_watch_pressed()
	await process_frame
	await process_frame
	_check(target.status == "LIVE", "watching marks the fixture live")
	var screen: Control = null
	for child in game.get_children():
		if child.has_method("setup"):
			screen = child
	_check(screen != null and screen.playback != null, "live screen opens on the session")
	_check(matches._current_match.status == "LIVE", "list refresh keeps the selected match")

	var before: int = screen.playback.live.minute
	await _advance(screen, 3.0)
	_check(screen.playback.live.minute > before, "the live screen advances with time")
	_check(screen._clock_label.text == "%d'" % screen.playback.live.minute, "clock shows the match minute")
	_check(screen._score_label.text == "%d - %d" % screen.playback.live.score, "scoreboard mirrors the score")

	screen._on_speed_pressed(8)
	await _advance(screen, 12.0)
	_check(screen.playback.paused and screen._status_label.text == "HALF TIME", "pauses at half time")
	_check(screen._play_button.text.contains("2nd half"), "play button offers the second half")
	screen._on_play_pressed()
	_check(not screen.playback.paused, "start 2nd half resumes play")

	screen._on_finish_pressed()
	await process_frame
	_check(screen._status_label.text == "FULL TIME" and ResultStore.has_result(target.id), "sim to full time records the result")
	_check(screen._feed.get_child_count() > 3, "the feed has commentary")
	var goals_in_feed := 0
	for row in screen._feed.get_children():
		if row.get_child(1).text.begins_with("GOAL"):
			goals_in_feed += 1
	_check(goals_in_feed == screen.playback.live.score[0] + screen.playback.live.score[1], "every goal is in the feed")
	_check(not screen._finish_button.visible, "sim button hides after full time")
	await process_frame
	await process_frame
	_check(matches._current_match.status == "FT" and not matches._watch_button.visible, "details show the final state")

	var other: Dictionary = fixtures[1]
	matches._show_details(other, MatchRepository.get_leagues()[0])
	matches._on_sim_pressed()
	await process_frame
	await process_frame
	_check(other.status == "FT" and not matches._sim_button.visible, "Sim finishes without opening a screen")
	screen.close()
	await process_frame
	ResultStore.clear()
	MatchRepository.reset()


func _advance(screen: Control, seconds: float) -> void:
	var step := 0.1
	for i in int(seconds / step):
		screen._process(step)
	await process_frame
