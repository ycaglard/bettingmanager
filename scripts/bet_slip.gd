extends PanelContainer
## Floating bet slip. Mirrors BetManager.slip; one selection per match,
## two or more matches form a parlay.

const UITheme = preload("res://scripts/ui_theme.gd")

const LEG_HEIGHT := 64.0
const MAX_VISIBLE_LEGS := 4
const QUICK_STAKES := [10, 25, 50, 100]

var collapsed := false:
	set(value):
		collapsed = value
		if is_node_ready():
			_body.visible = not collapsed
			_chevron.text = "▴" if collapsed else "▾"

var _title_count: Label
var _type_label: Label
var _chevron: Label
var _body: VBoxContainer
var _legs_scroll: ScrollContainer
var _legs_list: VBoxContainer
var _stake_input: LineEdit
var _odds_value: Label
var _return_value: Label
var _error_label: Label
var _place_button: Button


func _ready() -> void:
	theme_type_variation = &"SlipPanel"
	custom_minimum_size = Vector2(400, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	BetManager.slip_changed.connect(_refresh)
	BetManager.balance_changed.connect(func(_b): _update_totals())
	_refresh()


func get_stake() -> float:
	return maxf(_stake_input.text.to_float(), 0.0)


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# Header doubles as the collapse toggle.
	var header := Button.new()
	header.theme_type_variation = &"MarketHeader"
	header.focus_mode = Control.FOCUS_NONE
	header.custom_minimum_size = Vector2(0, 32)
	header.pressed.connect(func(): collapsed = not collapsed)
	root.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_theme_constant_override("separation", 10)
	header.add_child(header_row)

	var title := _label("Bet Slip", &"HeadingLabel")
	title.add_theme_font_size_override("font_size", 24)
	header_row.add_child(title)

	var count_pill := PanelContainer.new()
	count_pill.theme_type_variation = &"AccentPill"
	count_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_count = _label("0", &"AccentPillLabel")
	count_pill.add_child(_title_count)
	header_row.add_child(count_pill)

	_type_label = _label("", &"DimLabel")
	_type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_type_label)

	_chevron = _label("▾", &"DimLabel")
	header_row.add_child(_chevron)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	root.add_child(_body)

	_legs_scroll = ScrollContainer.new()
	_legs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_legs_scroll)
	_legs_list = VBoxContainer.new()
	_legs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legs_list.add_theme_constant_override("separation", 6)
	_legs_scroll.add_child(_legs_list)

	var clear := Button.new()
	clear.theme_type_variation = &"TextButton"
	clear.text = "Clear all"
	clear.focus_mode = Control.FOCUS_NONE
	clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	clear.pressed.connect(BetManager.clear_slip)
	_body.add_child(clear)

	_body.add_child(HSeparator.new())

	var stake_row := HBoxContainer.new()
	stake_row.add_theme_constant_override("separation", 10)
	var stake_caption := _label("Stake", &"StrongLabel")
	stake_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stake_row.add_child(stake_caption)
	_stake_input = LineEdit.new()
	_stake_input.theme_type_variation = &"StakeInput"
	_stake_input.text = "10"
	_stake_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stake_input.custom_minimum_size = Vector2(150, 44)
	_stake_input.select_all_on_focus = true
	_stake_input.text_changed.connect(_on_stake_text_changed)
	_stake_input.text_submitted.connect(func(_t): _on_place_pressed())
	stake_row.add_child(_stake_input)
	_body.add_child(stake_row)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 6)
	for amount in QUICK_STAKES:
		quick_row.add_child(_quick_button(BetManager.format_money(amount).trim_suffix(".00"), float(amount)))
	quick_row.add_child(_quick_button("Max", -1.0))
	_body.add_child(quick_row)

	_odds_value = _summary_row("Total odds", &"OddsValue")
	_return_value = _summary_row("Potential return", &"MoneyLabel")

	_error_label = _label("", &"ErrorLabel")
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_error_label)

	_place_button = Button.new()
	_place_button.theme_type_variation = &"PrimaryButton"
	_place_button.focus_mode = Control.FOCUS_NONE
	_place_button.custom_minimum_size = Vector2(0, 54)
	_place_button.pressed.connect(_on_place_pressed)
	_body.add_child(_place_button)


func _quick_button(text: String, amount: float) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"ChipButton"
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		var value := BetManager.balance if amount < 0.0 else amount
		_stake_input.text = _format_stake(value)
		_update_totals())
	return button


func _summary_row(caption: String, value_variation: StringName) -> Label:
	var row := HBoxContainer.new()
	var caption_label := _label(caption, &"DimLabel")
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption_label)
	var value := _label("", value_variation)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_body.add_child(row)
	return value


func _refresh() -> void:
	for child in _legs_list.get_children():
		child.queue_free()
	var legs: Array = BetManager.slip.values()
	for leg in legs:
		_legs_list.add_child(_make_leg_row(leg))
	var visible_legs := mini(legs.size(), MAX_VISIBLE_LEGS)
	_legs_scroll.custom_minimum_size.y = visible_legs * LEG_HEIGHT + maxf(visible_legs - 1, 0) * 6.0

	_title_count.text = str(legs.size())
	if legs.size() <= 1:
		_type_label.text = "Single"
	else:
		_type_label.text = "Parlay  ·  %d legs" % legs.size()
	_update_totals()


func _make_leg_row(leg: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PillPanel"
	panel.custom_minimum_size = Vector2(0, LEG_HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var accent := ColorRect.new()
	accent.color = UITheme.ACCENT
	accent.custom_minimum_size = Vector2(3, 0)
	row.add_child(accent)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	var pick := _label(leg.selection_name, &"StrongLabel")
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.clip_text = true
	text.add_child(pick)
	var detail := _label("%s  ·  %s vs %s" % [leg.market_name, leg.home, leg.away], &"MutedLabel")
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.clip_text = true
	detail.tooltip_text = detail.text
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(detail)
	row.add_child(text)

	row.add_child(_label("%.2f" % float(leg.odds), &"OddsValue"))

	var remove := Button.new()
	remove.theme_type_variation = &"TextButton"
	remove.text = "✕"
	remove.tooltip_text = "Remove from slip"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(BetManager.remove_from_slip.bind(leg.match_id))
	row.add_child(remove)
	return panel


func _on_stake_text_changed(text: String) -> void:
	var cleaned := ""
	var has_dot := false
	for character in text.replace(",", "."):
		if character.is_valid_int():
			cleaned += character
		elif character == "." and not has_dot:
			cleaned += character
			has_dot = true
	if cleaned != text:
		var caret := _stake_input.caret_column
		_stake_input.text = cleaned
		_stake_input.caret_column = mini(caret, cleaned.length())
	_update_totals()


func _update_totals() -> void:
	if not is_node_ready():
		return
	var stake := get_stake()
	var total_odds := BetManager.slip_total_odds()
	_odds_value.text = "%.2f" % total_odds
	_return_value.text = BetManager.format_money(stake * total_odds)
	var error := BetManager.validate_stake(stake)
	_error_label.text = error if not BetManager.slip.is_empty() else ""
	_error_label.visible = not _error_label.text.is_empty()
	_place_button.disabled = not error.is_empty()
	var kind := "Single" if BetManager.slip.size() <= 1 else "Parlay"
	_place_button.text = "Place %s  ·  %s" % [kind, BetManager.format_money(stake)]


func _on_place_pressed() -> void:
	var bet := BetManager.place_bet(get_stake(), GameCalendar.formatted())
	if bet.is_empty():
		_update_totals()


func _format_stake(value: float) -> String:
	value = snappedf(value, 0.01)
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.2f" % value


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
