extends Control
## Full-screen live match view: scoreboard, pitch strip, commentary feed, live
## stats and playback controls. It only presents a MatchPlayback owned by the
## MatchDirector; closing it leaves the match running in the background.

signal closed

const UITheme = preload("res://scripts/ui_theme.gd")
const TeamBadge = preload("res://scripts/team_badge.gd")
const StatBar = preload("res://scripts/stat_bar.gd")
const PitchStrip = preload("res://scripts/pitch_strip.gd")
const Commentary = preload("res://scripts/match_commentary.gd")
const T = preload("res://scripts/engine/match_types.gd")

const MAX_FEED_LINES := 120
const STAT_ROWS := [
	["possession", "Possession", "%"],
	["shots", "Shots", ""],
	["shots_on_target", "On Target", ""],
	["corners", "Corners", ""],
	["fouls", "Fouls", ""],
	["yellow_cards", "Yellow Cards", ""],
	["red_cards", "Red Cards", ""],
]

var match_id := ""
var playback: RefCounted

var _fixture: Dictionary
var _score_label: Label
var _clock_label: Label
var _status_label: Label
var _pitch: Control
var _feed: VBoxContainer
var _stats_box: VBoxContainer
var _stat_values: Dictionary = {}
var _play_button: Button
var _speed_buttons: Dictionary = {}
var _half_time_button: Button
var _finish_button: Button
var _close_button: Button


## Opens the screen on an existing session; returns false if there is none.
func setup(p_match_id: String) -> bool:
	playback = MatchDirector.get_session(p_match_id)
	if playback == null:
		return false
	match_id = p_match_id
	_fixture = MatchDirector.find_fixture(match_id)
	_build()
	for event in playback.live.events:
		_add_feed_line(event)
	playback.minute_played.connect(_on_minute_played)
	playback.half_time.connect(_refresh_controls)
	playback.finished.connect(_refresh_controls)
	_refresh_all()
	return true


func _process(delta: float) -> void:
	if playback != null:
		playback.advance(delta)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = UITheme.BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_scoreboard())
	_pitch = PitchStrip.new()
	column.add_child(_pitch)
	column.add_child(_build_body())
	column.add_child(_build_controls())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	var title := _label("Live Match  ·  %s" % match_id, &"DimLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.theme_type_variation = &"IconButton"
	_close_button.custom_minimum_size = Vector2(38, 38)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "Close (the match keeps its progress)"
	_close_button.pressed.connect(close)
	row.add_child(_close_button)
	return row


func _build_scoreboard() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(_team_box(_fixture.home))

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(200, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_label = _label("0 - 0", &"DisplayLabel")
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label = _label("0'", &"SectionLabel")
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label = _label("", &"MutedLabel")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for label in [_score_label, _clock_label, _status_label]:
		center.add_child(label)
	row.add_child(center)
	row.add_child(_team_box(_fixture.away))
	return panel


func _team_box(team: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var badge := CenterContainer.new()
	badge.add_child(TeamBadge.new(team, 64))
	box.add_child(badge)
	var name_label := _label(team, &"StrongLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	return box


func _build_body() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)

	var feed_panel := PanelContainer.new()
	feed_panel.theme_type_variation = &"CardPanel"
	feed_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_panel.size_flags_stretch_ratio = 1.4
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.add_theme_constant_override("separation", 8)
	scroll.add_child(_feed)
	feed_panel.add_child(scroll)
	row.add_child(feed_panel)

	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"CardPanel"
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 12)
	stats_panel.add_child(_stats_box)
	row.add_child(stats_panel)
	_build_stat_rows()
	return row


func _build_stat_rows() -> void:
	for row in STAT_ROWS:
		var header := HBoxContainer.new()
		var home_value := _label("0", &"StatValue")
		var title := _label(row[1], &"DimLabel")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var away_value := _label("0", &"StatValue")
		away_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for node in [home_value, title, away_value]:
			header.add_child(node)
		var bar := StatBar.new(0.0, 0.0)
		bar.progress = 1.0
		_stats_box.add_child(header)
		_stats_box.add_child(bar)
		_stat_values[row[0]] = {"home": home_value, "away": away_value, "bar": bar, "suffix": row[2]}


func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_play_button = _control_button("⏸ Pause", _on_play_pressed)
	row.add_child(_play_button)
	var group := ButtonGroup.new()
	for speed in playback.SPEEDS:
		var button := _control_button("%dx" % speed, _on_speed_pressed.bind(speed))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = speed == playback.speed
		_speed_buttons[speed] = button
		row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_half_time_button = _control_button("Skip to half time", _on_skip_half_time_pressed)
	_finish_button = _control_button("Sim to full time", _on_finish_pressed)
	row.add_child(_half_time_button)
	row.add_child(_finish_button)
	return row


func _control_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"ChipButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(callback)
	return button


func close() -> void:
	closed.emit()
	queue_free()


func _on_play_pressed() -> void:
	if playback.is_finished():
		close()
	elif playback.live.phase == T.Phase.HALF_TIME:
		playback.resume()
	else:
		playback.paused = not playback.paused
	_refresh_controls()


func _on_speed_pressed(speed: int) -> void:
	playback.set_speed(speed)


func _on_skip_half_time_pressed() -> void:
	playback.skip_to_half_time()


func _on_finish_pressed() -> void:
	playback.skip_to_end()


func _on_minute_played(_minute: int, events: Array) -> void:
	for event in events:
		_add_feed_line(event)
	_refresh_all()


func _refresh_all() -> void:
	var live: RefCounted = playback.live
	_score_label.text = "%d - %d" % [live.score[0], live.score[1]]
	_clock_label.text = "%d'" % live.minute
	_pitch.show_state(live.ball_zone, live.possession)
	_refresh_stats()
	_refresh_controls()


func _refresh_stats() -> void:
	var stats: Dictionary = playback.live.build_report().to_stats_dict()
	for key in _stat_values:
		var entry: Dictionary = _stat_values[key]
		var values: Array = stats[key]
		entry.home.text = "%d%s" % [values[0], entry.suffix]
		entry.away.text = "%d%s" % [values[1], entry.suffix]
		entry.bar.home_value = float(values[0])
		entry.bar.away_value = float(values[1])
		entry.bar.queue_redraw()


func _refresh_controls() -> void:
	var live: RefCounted = playback.live
	var finished: bool = playback.is_finished()
	var at_half_time: bool = live.phase == T.Phase.HALF_TIME
	if finished:
		_status_label.text = "FULL TIME"
		_play_button.text = "Close"
	elif at_half_time:
		_status_label.text = "HALF TIME"
		_play_button.text = "▶ Start 2nd half"
	else:
		_status_label.text = "PAUSED" if playback.paused else "LIVE"
		_play_button.text = "▶ Play" if playback.paused else "⏸ Pause"
	_half_time_button.visible = not finished and live.phase != T.Phase.SECOND_HALF and not at_half_time
	_finish_button.visible = not finished


func _add_feed_line(event: RefCounted) -> void:
	if not Commentary.is_notable(event):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var minute := _label("%d'" % event.minute, &"MutedLabel")
	minute.custom_minimum_size = Vector2(36, 0)
	var text := _label(Commentary.line(event, playback.live), &"StrongLabel" if _is_key_moment(event) else &"DimLabel")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", _event_color(event))
	row.add_child(minute)
	row.add_child(text)
	_feed.add_child(row)
	_feed.move_child(row, 0)
	if _feed.get_child_count() > MAX_FEED_LINES:
		_feed.get_child(_feed.get_child_count() - 1).queue_free()


func _is_key_moment(event: RefCounted) -> bool:
	return event.type in [T.EventType.GOAL, T.EventType.RED_CARD, T.EventType.PENALTY_AWARDED]


## Colour is paired with the line's wording, so it is never the only signal.
func _event_color(event: RefCounted) -> Color:
	match event.type:
		T.EventType.GOAL:
			return UITheme.POSITIVE
		T.EventType.RED_CARD:
			return UITheme.DANGER
		T.EventType.YELLOW_CARD, T.EventType.PENALTY_AWARDED:
			return UITheme.WARNING
	return UITheme.TEXT_DIM


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
