extends Control

const MatchRepository = preload("res://scripts/match_repository.gd")
const MatchStatsProvider = preload("res://scripts/match_stats_provider.gd")
const MatchOddsProvider = preload("res://scripts/match_odds_provider.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const TeamBadge = preload("res://scripts/team_badge.gd")
const StatBar = preload("res://scripts/stat_bar.gd")
const BetSlip = preload("res://scripts/bet_slip.gd")
const LiveMatchScreen = preload("res://tabs/live_match_screen.gd")

const SWIPE_DURATION := 0.45
const SLIP_DURATION := 0.3
const PADDING := 24.0
const GAP := 20.0
const SLIP_INSET := 16.0
const STAT_ROWS := [
	["possession", "Possession", "%"],
	["shots", "Shots", ""],
	["shots_on_target", "Shots on Target", ""],
	["corners", "Corners", ""],
	["passes", "Passes", ""],
	["pass_accuracy", "Pass Accuracy", "%"],
	["fouls", "Fouls", ""],
	["offsides", "Offsides", ""],
	["yellow_cards", "Yellow Cards", ""],
	["red_cards", "Red Cards", ""],
]

@onready var list_panel: Control = $ListPanel
@onready var match_list: VBoxContainer = %MatchList
@onready var filter_bar: Container = %FilterBar
@onready var count_label: Label = %CountLabel
@onready var stats_panel: Control = $StatsPanel
@onready var breadcrumb: Label = %Breadcrumb
@onready var headline: Label = %Headline
@onready var home_badge_slot: Container = %HomeBadge
@onready var away_badge_slot: Container = %AwayBadge
@onready var home_name: Label = %HomeName
@onready var away_name: Label = %AwayName
@onready var score_label: Label = %ScoreLabel
@onready var status_label: Label = %StatusLabel
@onready var status_pill: PanelContainer = %StatusLabel.get_parent()
@onready var kickoff_label: Label = %KickoffLabel
@onready var stats_list: VBoxContainer = %StatsList
@onready var stats_scroll: ScrollContainer = %StatsScroll
@onready var odds_list: VBoxContainer = %OddsList
@onready var odds_margin: MarginContainer = %OddsList.get_parent()
@onready var odds_scroll: ScrollContainer = %OddsScroll
@onready var odds_tab: Button = %OddsTab
@onready var stats_tab: Button = %StatsTab
@onready var close_button: Button = %CloseButton

# 0 = list fills the screen, 1 = screen split in half with details on the right.
var _split := 0.0
var _tween: Tween
var _row_group := ButtonGroup.new()
var _current_match: Dictionary = {}
var _current_league: Dictionary = {}
var _watch_button: Button
var _sim_button: Button
var _refresh_queued := false

var _league_filter := ""
var _status_filter := ""
## league_id -> {"section": Control, "upcoming": Control, "results": Control}
var _sections := {}
## match_id -> slip marker Control
var _slip_markers := {}
## "market_id/selection_id" -> {"button", "name", "price", "market", "selection"}
var _odds_buttons := {}

var _slip: PanelContainer
var _slip_spacer: Control
var _slip_reveal := 0.0
var _slip_tween: Tween


func _ready() -> void:
	_row_group.allow_unpress = true
	resized.connect(_layout)
	close_button.pressed.connect(_close_stats)
	var view_group := ButtonGroup.new()
	for tab in [odds_tab, stats_tab]:
		tab.button_group = view_group
		tab.pressed.connect(_render_detail_view)
	odds_tab.button_pressed = true
	_build_action_bar()
	_populate()
	_build_slip()
	BetManager.slip_changed.connect(_on_slip_changed)
	MatchDirector.match_finished.connect(_queue_refresh.unbind(2))
	_on_slip_changed()
	_layout()


# --- Match list --------------------------------------------------------------

func _populate() -> void:
	var league_group := ButtonGroup.new()
	_add_chip("All leagues", league_group, true, func(): _set_league_filter(""), "league:")
	var upcoming_total := 0
	var results_total := 0
	for league in MatchRepository.get_leagues():
		_add_chip(league.name, league_group, false, _set_league_filter.bind(league.id), "league:" + league.id)
		var upcoming: Array = league.matches.filter(func(m): return BetManager.is_bettable(m))
		var results: Array = league.matches.filter(func(m): return not BetManager.is_bettable(m))
		upcoming_total += upcoming.size()
		results_total += results.size()

		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		section.add_child(_make_section_header(league))
		var upcoming_block := _make_block("UPCOMING", upcoming, league)
		var results_block := _make_block("RESULTS", results, league)
		section.add_child(upcoming_block)
		section.add_child(results_block)
		match_list.add_child(section)
		_sections[league.id] = {"section": section, "upcoming": upcoming_block, "results": results_block}

	var separator := VSeparator.new()
	separator.custom_minimum_size = Vector2(12, 0)
	filter_bar.add_child(separator)
	var status_group := ButtonGroup.new()
	_add_chip("All", status_group, true, func(): _set_status_filter(""), "status:")
	_add_chip("Upcoming", status_group, false, func(): _set_status_filter("upcoming"), "status:upcoming")
	_add_chip("Results", status_group, false, func(): _set_status_filter("results"), "status:results")

	_slip_spacer = Control.new()
	_slip_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match_list.add_child(_slip_spacer)
	count_label.text = "%d upcoming  ·  %d results" % [upcoming_total, results_total]


func _add_chip(text: String, group: ButtonGroup, pressed: bool, callback: Callable, key := "") -> void:
	var chip := Button.new()
	chip.text = text
	chip.set_meta("filter", key)
	chip.theme_type_variation = &"ChipButton"
	chip.toggle_mode = true
	chip.button_group = group
	chip.focus_mode = Control.FOCUS_NONE
	chip.button_pressed = pressed
	chip.pressed.connect(callback)
	filter_bar.add_child(chip)


func _set_league_filter(league_id: String) -> void:
	_league_filter = league_id
	_apply_filters()


func _set_status_filter(status: String) -> void:
	_status_filter = status
	_apply_filters()


func _apply_filters() -> void:
	for id in _sections:
		var entry: Dictionary = _sections[id]
		entry.section.visible = _league_filter.is_empty() or id == _league_filter
		entry.upcoming.visible = _status_filter != "results" and entry.upcoming.get_meta("count") > 0
		entry.results.visible = _status_filter != "upcoming" and entry.results.get_meta("count") > 0


func _make_section_header(league: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SectionPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var marker := ColorRect.new()
	marker.color = UITheme.ACCENT
	marker.custom_minimum_size = Vector2(3, 0)
	row.add_child(marker)

	var title := _label(league.name.to_upper(), &"SectionLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_label("%d clubs" % league.teams.size(), &"MutedLabel"))
	return panel


func _make_block(title: String, matches: Array, league: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	block.set_meta("count", matches.size())
	block.visible = not matches.is_empty()
	if matches.is_empty():
		return block

	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 14)
	header.add_theme_constant_override("margin_top", 8)
	header.add_theme_constant_override("margin_bottom", 2)
	var round_number := int(matches[0].get("round", 1))
	var caption := _label("%s  ·  ROUND %d" % [title, round_number], &"MutedLabel")
	if title == "UPCOMING":
		caption.add_theme_color_override("font_color", UITheme.ACCENT)
	header.add_child(caption)
	block.add_child(header)

	for match_data in matches:
		block.add_child(_make_match_row(match_data, league))
	return block


func _make_match_row(match_data: Dictionary, league: Dictionary) -> Button:
	var upcoming := BetManager.is_bettable(match_data)
	var row := Button.new()
	row.theme_type_variation = &"RowButton"
	row.toggle_mode = true
	row.button_group = _row_group
	row.focus_mode = Control.FOCUS_NONE
	row.set_meta("match_id", match_data.id)
	row.custom_minimum_size = Vector2(0, 48)
	row.toggled.connect(_on_row_toggled.bind(match_data, league))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var marker := _label("●", &"MutedLabel")
	marker.add_theme_color_override("font_color", UITheme.ACCENT)
	marker.tooltip_text = "In your bet slip"
	marker.modulate.a = 0.0
	content.add_child(marker)
	_slip_markers[match_data.id] = marker

	var kickoff := _label(match_data.kickoff, &"MutedLabel")
	kickoff.custom_minimum_size = Vector2(44, 0)
	content.add_child(kickoff)

	var home_bright := true
	var away_bright := true
	var score_text := "vs"
	if not upcoming:
		var hs := int(match_data.home_score)
		var aws := int(match_data.away_score)
		home_bright = hs >= aws
		away_bright = aws >= hs
		score_text = "%d - %d" % [hs, aws]

	content.add_child(_team_label(match_data.home, home_bright, HORIZONTAL_ALIGNMENT_RIGHT))
	content.add_child(_centered(TeamBadge.new(match_data.home, 28)))

	var pill := PanelContainer.new()
	pill.theme_type_variation = &"PillPanel"
	pill.custom_minimum_size = Vector2(72, 0)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score := _label(score_text, &"PillScore")
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if upcoming:
		score.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	pill.add_child(score)
	content.add_child(pill)

	content.add_child(_centered(TeamBadge.new(match_data.away, 28)))
	content.add_child(_team_label(match_data.away, away_bright, HORIZONTAL_ALIGNMENT_LEFT))

	var status_text: String = match_data.status
	if upcoming:
		status_text = "%s %s" % [GameCalendar.short_weekday(match_data.date), match_data.date.left(5)]
	var status := _label(status_text, &"MutedLabel")
	status.custom_minimum_size = Vector2(84, 0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	content.add_child(status)
	return row


func _team_label(team: String, emphasised: bool, align: HorizontalAlignment) -> Label:
	var label := _label(team, &"StrongLabel")
	if not emphasised:
		label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	label.horizontal_alignment = align
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	return label


func _centered(control: Control) -> Control:
	var wrapper := CenterContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(control)
	return wrapper


func _on_row_toggled(pressed: bool, match_data: Dictionary, league: Dictionary) -> void:
	if pressed:
		_show_details(match_data, league)
		_animate_split(1.0)
	elif _row_group.get_pressed_button() == null:
		_animate_split(0.0)


func _close_stats() -> void:
	var selected := _row_group.get_pressed_button()
	if selected:
		selected.button_pressed = false
	_animate_split(0.0)


# --- Detail panel --------------------------------------------------------------

func _show_details(match_data: Dictionary, league: Dictionary) -> void:
	var upcoming := BetManager.is_bettable(match_data)
	breadcrumb.text = "Matches   ›   %s   ›   %s" % [league.name, match_data.id]
	home_name.text = match_data.home
	away_name.text = match_data.away
	var date: String = match_data.get("date", "")
	kickoff_label.text = "%s %s  ·  %s" % [GameCalendar.short_weekday(date), date, match_data.kickoff]
	if upcoming:
		headline.text = _preview_headline(match_data)
		score_label.text = "VS"
		status_label.text = "UPCOMING"
		status_pill.theme_type_variation = &"AccentPill"
		status_label.theme_type_variation = &"AccentPillLabel"
	else:
		var hs := int(match_data.home_score)
		var aws := int(match_data.away_score)
		headline.text = _headline(match_data.home, match_data.away, hs, aws)
		score_label.text = "%d - %d" % [hs, aws]
		status_label.text = "FULL TIME" if match_data.status == "FT" else str(match_data.status)
		status_pill.theme_type_variation = &"StatusPill"
		status_label.theme_type_variation = &"StatusLabel"
	_set_badge(home_badge_slot, match_data.home)
	_set_badge(away_badge_slot, match_data.away)
	_current_match = match_data
	_current_league = league
	_update_action_bar()
	_render_detail_view()


# --- Watch / sim -------------------------------------------------------------

func _build_action_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_watch_button = _action_button("▶ Watch live", _on_watch_pressed)
	_sim_button = _action_button("⏩ Sim to full time", _on_sim_pressed)
	bar.add_child(_watch_button)
	bar.add_child(_sim_button)
	var column: Control = $StatsPanel/VBox
	column.add_child(bar)
	column.move_child(bar, $StatsPanel/VBox/ViewTabs.get_index())


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"ChipButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(callback)
	return button


func _update_action_bar() -> void:
	var status: String = _current_match.get("status", "")
	var playable := status == "NS" or status == "LIVE"
	_watch_button.visible = playable
	_sim_button.visible = playable
	_watch_button.text = "▶ Resume watching" if status == "LIVE" else "▶ Watch live"
	_sim_button.text = "⏩ Finish instantly" if status == "LIVE" else "⏩ Sim to full time"


func _on_watch_pressed() -> void:
	if MatchDirector.watch(_current_match.id) == null:
		return
	_queue_refresh()
	var screen := LiveMatchScreen.new()
	get_tree().current_scene.add_child(screen)
	screen.setup(_current_match.id)


func _on_sim_pressed() -> void:
	MatchDirector.sim(_current_match.id)


## Rebuilds the list on the next idle frame; a whole day's results arrive as a burst.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_list.call_deferred()


func _refresh_list() -> void:
	_refresh_queued = false
	var selected_id: String = _current_match.get("id", "")
	var filters := []
	for chip in filter_bar.get_children():
		if chip is Button and chip.button_pressed:
			filters.append(chip.get_meta("filter"))
	for container in [filter_bar, match_list]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_sections.clear()
	_slip_markers.clear()
	_populate()
	for chip in filter_bar.get_children():
		if chip is Button:
			chip.button_pressed = chip.get_meta("filter") in filters
	_apply_filters()
	_on_slip_changed()
	if selected_id.is_empty():
		return
	for row in _row_group.get_buttons():
		if row.get_meta("match_id", "") == selected_id and not row.is_queued_for_deletion():
			row.button_pressed = true


func _render_detail_view() -> void:
	if _current_match.is_empty():
		return
	odds_scroll.visible = odds_tab.button_pressed
	stats_scroll.visible = stats_tab.button_pressed
	if odds_tab.button_pressed:
		_render_odds(_current_match)
		odds_scroll.scroll_vertical = 0
	else:
		_render_stats(_current_match)
		stats_scroll.scroll_vertical = 0


func _render_odds(match_data: Dictionary) -> void:
	_odds_buttons.clear()
	for child in odds_list.get_children():
		child.queue_free()

	var markets := MatchOddsProvider.get_markets(match_data.id)
	if markets.is_empty():
		odds_list.add_child(_label("No odds available.", &"DimLabel"))
		return

	var bettable := BetManager.is_bettable(match_data)
	if bettable:
		odds_list.add_child(_label("Pre-match odds  ·  %d markets  ·  tap a price to add it to your slip" % markets.size(), &"MutedLabel"))
	else:
		var note := _label("Betting closed  ·  match finished  ·  closing odds shown", &"MutedLabel")
		note.add_theme_color_override("font_color", UITheme.WARNING)
		odds_list.add_child(note)
	for market in markets:
		odds_list.add_child(_make_market_card(market, bettable))
	_sync_odds_buttons()


func _make_market_card(market: Dictionary, bettable: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"InsetPanel"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)

	var header := Button.new()
	header.theme_type_variation = &"MarketHeader"
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "▾   " + market.name
	body.add_child(header)

	var grid := GridContainer.new()
	grid.columns = _columns_for(market)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for selection in market.selections:
		grid.add_child(_make_odds_button(market, selection, bettable))
	body.add_child(grid)

	header.pressed.connect(func():
		grid.visible = not grid.visible
		header.text = ("▾   " if grid.visible else "▸   ") + market.name)
	return card


func _columns_for(market: Dictionary) -> int:
	var count: int = market.selections.size()
	if count <= 2 or market.selections[0].has("line") and not market.id == "handicap":
		return 2
	return 3


func _make_odds_button(market: Dictionary, selection: Dictionary, bettable: bool) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"OddsButton"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 44)
	button.disabled = not bettable
	button.tooltip_text = "%s  ·  %s" % [market.name, selection.name]

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var name_label := _label(selection.name, &"DimLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	content.add_child(name_label)
	var price := _label("%.2f" % float(selection.odds), &"OddsValue")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	content.add_child(price)
	if not bettable:
		name_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		price.add_theme_color_override("font_color", UITheme.TEXT_MUTED)

	var match_data := _current_match
	button.pressed.connect(func(): BetManager.toggle_selection(match_data, market, selection))
	_odds_buttons["%s/%s" % [market.id, selection.id]] = {
		"button": button, "name": name_label, "price": price,
		"market": market, "selection": selection,
	}
	return button


func _sync_odds_buttons() -> void:
	if _current_match.is_empty() or not BetManager.is_bettable(_current_match):
		return
	for key in _odds_buttons:
		var entry: Dictionary = _odds_buttons[key]
		if not is_instance_valid(entry.button):
			continue
		var selected := BetManager.is_in_slip(_current_match.id, entry.market.id, entry.selection.id)
		entry.button.set_pressed_no_signal(selected)
		entry.name.add_theme_color_override("font_color", Color.WHITE if selected else UITheme.TEXT_DIM)
		entry.price.add_theme_color_override("font_color", Color.WHITE if selected else UITheme.ACCENT)


func _render_stats(match_data: Dictionary) -> void:
	for child in stats_list.get_children():
		child.queue_free()

	var stats := MatchStatsProvider.get_stats(match_data.id)
	if stats.is_empty():
		var message := "Statistics will be available after kick-off." if BetManager.is_bettable(match_data) \
			else "No statistics available."
		stats_list.add_child(_label(message, &"DimLabel"))
		return

	var index := 0
	for row in STAT_ROWS:
		if stats.has(row[0]):
			_add_stat_row(row[1], stats[row[0]], row[2], 0.15 + index * 0.04)
			index += 1


func _set_badge(slot: Container, team: String) -> void:
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(TeamBadge.new(team, 84))


func _add_stat_row(title: String, values: Array, suffix: String, delay: float) -> void:
	var home := float(values[0])
	var away := float(values[1])
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	var home_label := _label("%d%s" % [int(home), suffix], &"StatValue")
	home_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label(title, &"DimLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var away_label := _label("%d%s" % [int(away), suffix], &"StatValue")
	away_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	away_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if home < away:
		home_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	if away < home:
		away_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	top.add_child(home_label)
	top.add_child(name_label)
	top.add_child(away_label)
	row.add_child(top)

	var bar := StatBar.new(home, away)
	row.add_child(bar)
	stats_list.add_child(row)

	create_tween().tween_property(bar, "progress", 1.0, 0.7) \
		.set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _headline(home: String, away: String, hs: int, aws: int) -> String:
	var diff := absi(hs - aws)
	if diff == 0:
		if hs == 0:
			return "Stalemate as %s and %s cancel each other out" % [home, away]
		return "%s and %s share the spoils in %d-%d thriller" % [home, away, hs, aws]
	var winner := home if hs > aws else away
	var loser := away if hs > aws else home
	if diff >= 3:
		return "%s run riot against %s" % [winner, loser]
	if diff == 2:
		return "%s ease past %s" % [winner, loser]
	return "%s edge %s in tight contest" % [winner, loser]


func _preview_headline(match_data: Dictionary) -> String:
	var market := MatchOddsProvider.get_market(match_data.id, "match_result")
	if market.is_empty():
		return "%s host %s" % [match_data.home, match_data.away]
	var home_odds := 0.0
	var away_odds := 0.0
	for selection in market.selections:
		if selection.id == "home":
			home_odds = float(selection.odds)
		elif selection.id == "away":
			away_odds = float(selection.odds)
	var ratio := maxf(home_odds, away_odds) / maxf(minf(home_odds, away_odds), 0.01)
	var favourite: String = match_data.home if home_odds < away_odds else match_data.away
	var underdog: String = match_data.away if home_odds < away_odds else match_data.home
	if ratio < 1.35:
		return "Evenly poised as %s welcome %s" % [match_data.home, match_data.away]
	if ratio > 3.0:
		return "%s heavy favourites against %s" % [favourite, underdog]
	return "%s fancied to get the better of %s" % [favourite, underdog]


# --- Bet slip ------------------------------------------------------------------

func _build_slip() -> void:
	_slip = BetSlip.new()
	_slip.visible = false
	add_child(_slip)
	_slip.minimum_size_changed.connect(_layout_slip)


func _on_slip_changed() -> void:
	for match_id in _slip_markers:
		var marker: Control = _slip_markers[match_id]
		marker.modulate.a = 1.0 if BetManager.slip.has(match_id) else 0.0
	_sync_odds_buttons()

	var target := 0.0 if BetManager.slip.is_empty() else 1.0
	if _slip_tween and _slip_tween.is_valid():
		_slip_tween.kill()
	if is_equal_approx(target, _slip_reveal):
		_layout_slip()
		return
	_slip_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slip_tween.tween_method(_set_slip_reveal, _slip_reveal, target, SLIP_DURATION)


func _set_slip_reveal(value: float) -> void:
	_slip_reveal = value
	_layout_slip()


func _layout_slip() -> void:
	if _slip == null:
		return
	var slip_size := _slip.get_combined_minimum_size()
	_slip.size = slip_size
	var resting_y := size.y - PADDING - SLIP_INSET - slip_size.y
	var hidden_y := size.y + 8.0
	_slip.position = Vector2(size.x - PADDING - SLIP_INSET - slip_size.x, lerpf(hidden_y, resting_y, _slip_reveal))
	_slip.modulate.a = _slip_reveal
	_slip.visible = _slip_reveal > 0.001

	# Leave room so the last rows / odds can scroll out from under the slip.
	var clearance := (slip_size.y + SLIP_INSET) * _slip_reveal
	_slip_spacer.custom_minimum_size.y = clearance
	odds_margin.add_theme_constant_override("margin_bottom", int(clearance))


# --- Layout --------------------------------------------------------------------

func _animate_split(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_split, _split, target, SWIPE_DURATION)


func _set_split(value: float) -> void:
	_split = value
	_layout()


func _layout() -> void:
	var inner := size - Vector2(PADDING, PADDING) * 2.0
	var stats_width := (inner.x - GAP) * 0.5
	var list_width := inner.x - (stats_width + GAP) * _split
	list_panel.position = Vector2(PADDING, PADDING)
	list_panel.size = Vector2(list_width, inner.y)
	stats_panel.position = Vector2(PADDING + list_width + GAP, PADDING)
	stats_panel.size = Vector2(stats_width, inner.y)
	stats_panel.modulate.a = clampf(_split * 1.6, 0.0, 1.0)
	stats_panel.visible = _split > 0.001
	_layout_slip()
