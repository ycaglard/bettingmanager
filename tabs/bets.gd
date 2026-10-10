extends Control
## "My Bets": summary tiles plus a card per placed bet (singles and parlays).

const UITheme = preload("res://scripts/ui_theme.gd")

const CARD_MIN_WIDTH := 520.0

var _filter := ""
var _metric_labels := {}

@onready var chip_bar: HBoxContainer = %ChipBar
@onready var summary_row: HBoxContainer = %SummaryRow
@onready var scroll: ScrollContainer = %Scroll
@onready var grid: GridContainer = %BetGrid
@onready var empty_state: Control = %EmptyState
@onready var empty_title: Label = %EmptyTitle
@onready var browse_button: Button = %BrowseButton


func _ready() -> void:
	var group := ButtonGroup.new()
	for entry in [["All", ""], ["Singles", "single"], ["Parlays", "parlay"]]:
		var chip := Button.new()
		chip.text = entry[0]
		chip.theme_type_variation = &"ChipButton"
		chip.toggle_mode = true
		chip.button_group = group
		chip.focus_mode = Control.FOCUS_NONE
		chip.button_pressed = entry[1] == ""
		chip.pressed.connect(func():
			_filter = entry[1]
			_refresh())
		chip_bar.add_child(chip)

	for metric in [["open", "Open Bets"], ["staked", "Total Staked"], ["returns", "Potential Returns"], ["balance", "Balance"]]:
		summary_row.add_child(_make_tile(metric[0], metric[1]))

	browse_button.pressed.connect(func():
		var container := get_parent() as TabContainer
		if container:
			container.current_tab = 0)
	scroll.resized.connect(_update_columns)
	BetManager.bets_changed.connect(_refresh)
	BetManager.balance_changed.connect(func(_b): _refresh_summary())
	_refresh()


func _make_tile(key: String, caption: String) -> Control:
	var tile := PanelContainer.new()
	tile.theme_type_variation = &"InsetPanel"
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label(caption.to_upper(), &"MutedLabel"))
	var value := _label("", &"MetricLabel")
	if key == "returns":
		value.add_theme_color_override("font_color", UITheme.POSITIVE)
	box.add_child(value)
	tile.add_child(box)
	_metric_labels[key] = value
	return tile


func _refresh() -> void:
	_refresh_summary()
	for child in grid.get_children():
		child.queue_free()

	var shown := BetManager.bets.filter(func(b): return _filter.is_empty() or b.type == _filter)
	for bet in shown:
		grid.add_child(_make_bet_card(bet))

	var has_bets := not shown.is_empty()
	grid.visible = has_bets
	empty_state.visible = not has_bets
	if BetManager.bets.is_empty():
		empty_title.text = "No bets placed yet"
	else:
		empty_title.text = "No %s yet" % ("singles" if _filter == "single" else "parlays")
	_update_columns()


func _refresh_summary() -> void:
	var open := BetManager.open_bets()
	var staked := 0.0
	var returns := 0.0
	for bet in open:
		staked += float(bet.stake)
		returns += float(bet.potential_return)
	_metric_labels.open.text = str(open.size())
	_metric_labels.staked.text = BetManager.format_money(staked)
	_metric_labels.returns.text = BetManager.format_money(returns)
	_metric_labels.balance.text = BetManager.format_money(BetManager.balance)


func _update_columns() -> void:
	var available := scroll.size.x - 16.0
	grid.columns = clampi(int(available / CARD_MIN_WIDTH), 1, 3)


func _make_bet_card(bet: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"InsetPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(_pill(bet.type.to_upper(), &"AccentPill", &"AccentPillLabel"))
	var legs: Array = bet.legs
	var legs_label := _label("%d leg%s" % [legs.size(), "" if legs.size() == 1 else "s"], &"DimLabel")
	legs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(legs_label)
	top.add_child(_pill(String(bet.status).to_upper(), &"WarningPill", &"WarningPillLabel"))
	body.add_child(top)

	body.add_child(_label("#%s  ·  Placed %s" % [bet.id, bet.placed_on], &"MutedLabel"))
	body.add_child(HSeparator.new())

	for leg in legs:
		body.add_child(_make_leg_row(leg))

	body.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.add_child(_figure("Stake", BetManager.format_money(bet.stake), &"StrongLabel", HORIZONTAL_ALIGNMENT_LEFT))
	footer.add_child(_figure("Total Odds", "%.2f" % float(bet.total_odds), &"OddsValue", HORIZONTAL_ALIGNMENT_CENTER))
	footer.add_child(_figure("Potential Return", BetManager.format_money(bet.potential_return), &"MoneyLabel", HORIZONTAL_ALIGNMENT_RIGHT))
	body.add_child(footer)
	return card


func _make_leg_row(leg: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var accent := ColorRect.new()
	accent.color = UITheme.ACCENT
	accent.custom_minimum_size = Vector2(3, 0)
	row.add_child(accent)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var pick := _label(leg.selection_name, &"StrongLabel")
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(pick)
	var when := "%s %s %s" % [GameCalendar.short_weekday(leg.date), String(leg.date).left(5), leg.kickoff]
	var detail := _label("%s  ·  %s vs %s  ·  %s" % [leg.market_name, leg.home, leg.away, when], &"MutedLabel")
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(detail)
	row.add_child(text)

	row.add_child(_label("%.2f" % float(leg.odds), &"OddsValue"))
	return row


func _figure(caption: String, value: String, variation: StringName, align: HorizontalAlignment) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var caption_label := _label(caption.to_upper(), &"MutedLabel")
	caption_label.horizontal_alignment = align
	box.add_child(caption_label)
	var value_label := _label(value, variation)
	value_label.horizontal_alignment = align
	box.add_child(value_label)
	return box


func _pill(text: String, panel_variation: StringName, label_variation: StringName) -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = panel_variation
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(_label(text, label_variation))
	return pill


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
