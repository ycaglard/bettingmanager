extends RefCounted
## Central palette, fonts and Theme for the game UI.

const BG := Color("0b0b1d")
const SURFACE := Color("131331")
const SURFACE_HI := Color("1b1b40")
const SURFACE_HOVER := Color("24244f")
const BORDER := Color("2a2a5a")
const BORDER_HI := Color("4a4a90")
const TEXT := Color("ececf6")
const TEXT_DIM := Color("9a9ac0")
const TEXT_MUTED := Color("62628c")
const ACCENT := Color("d93df5")
const ACCENT_DEEP := Color("6d2bd9")
const HOME := Color("d93df5")
const AWAY := Color("35c4f0")
const POSITIVE := Color("2fd27a")
const WARNING := Color("f5b83d")
const DANGER := Color("ff5d7a")

static var _heading_font: Font
static var _body_font: Font
static var _body_bold_font: Font


static func heading_font() -> Font:
	if _heading_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Bahnschrift", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
		base.font_weight = 700
		base.font_stretch = 75
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_opentype = {"wght": 700, "wdth": 75}
		_heading_font = variation
	return _heading_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = _system_font(400)
	return _body_font


static func body_bold_font() -> Font:
	if _body_bold_font == null:
		_body_bold_font = _system_font(600)
	return _body_bold_font


static func _system_font(weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Inter", "Roboto", "Helvetica", "Arial"])
	font.font_weight = weight
	return font


static func box(bg: Color, radius := 8, border := Color.TRANSPARENT, border_width := 1, margin := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 16

	t.set_color("font_color", "Label", TEXT)
	_build_base_buttons(t)
	_build_containers(t)
	_build_labels(t)
	_build_button_variations(t)
	_build_panel_variations(t)
	_build_inputs(t)
	return t


static func _build_inputs(t: Theme) -> void:
	var normal := box(BG, 6, BORDER, 1, 0)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var focus := normal.duplicate()
	focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", normal)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_type_variation("StakeInput", "LineEdit")
	t.set_font("font", "StakeInput", heading_font())
	t.set_font_size("font_size", "StakeInput", 22)

	t.set_stylebox("panel", "TooltipPanel", box(SURFACE_HI, 6, BORDER_HI, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)


static func _build_base_buttons(t: Theme) -> void:
	t.set_stylebox("normal", "Button", box(SURFACE_HI, 6, BORDER, 1, 10))
	t.set_stylebox("hover", "Button", box(SURFACE_HOVER, 6, BORDER_HI, 1, 10))
	t.set_stylebox("pressed", "Button", box(ACCENT_DEEP, 6, ACCENT, 1, 10))
	t.set_stylebox("hover_pressed", "Button", box(ACCENT_DEEP.lightened(0.1), 6, ACCENT, 1, 10))
	t.set_stylebox("disabled", "Button", box(SURFACE, 6, BORDER, 1, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_set_button_colors(t, "Button", TEXT, Color.WHITE, Color.WHITE)


static func _build_containers(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", box(SURFACE, 10, BORDER, 1, 0))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())

	var track := box(Color(1, 1, 1, 0.03), 3, Color.TRANSPARENT, 0, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	for state in [["grabber", BORDER_HI], ["grabber_highlight", ACCENT_DEEP], ["grabber_pressed", ACCENT]]:
		var grabber := box(state[1], 3, Color.TRANSPARENT, 0, 3)
		t.set_stylebox(state[0], "VScrollBar", grabber)

	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 8)


static func _build_labels(t: Theme) -> void:
	_label_variation(t, "HeadingLabel", heading_font(), 28, ACCENT)
	_label_variation(t, "TitleLabel", heading_font(), 32, TEXT)
	_label_variation(t, "DisplayLabel", heading_font(), 64, TEXT)
	_label_variation(t, "StatValue", heading_font(), 22, TEXT)
	_label_variation(t, "OddsValue", heading_font(), 20, ACCENT)
	_label_variation(t, "MoneyLabel", heading_font(), 26, POSITIVE)
	_label_variation(t, "MetricLabel", heading_font(), 30, TEXT)
	_label_variation(t, "ErrorLabel", body_font(), 13, DANGER)
	_label_variation(t, "AccentPillLabel", heading_font(), 14, ACCENT)
	_label_variation(t, "WarningPillLabel", heading_font(), 14, WARNING)
	_label_variation(t, "PillScore", heading_font(), 20, TEXT)
	_label_variation(t, "CrestLabel", heading_font(), 20, TEXT)
	_label_variation(t, "DateLabel", heading_font(), 26, TEXT)
	_label_variation(t, "SectionLabel", heading_font(), 17, TEXT)
	_label_variation(t, "StatusLabel", heading_font(), 14, POSITIVE)
	_label_variation(t, "StrongLabel", body_bold_font(), 16, TEXT)
	_label_variation(t, "DimLabel", body_font(), 14, TEXT_DIM)
	_label_variation(t, "MutedLabel", body_font(), 13, TEXT_MUTED)


static func _build_button_variations(t: Theme) -> void:
	# Large top navigation entries with an accent underline when active.
	t.set_type_variation("NavButton", "Button")
	var nav_idle := StyleBoxEmpty.new()
	nav_idle.content_margin_top = 4
	nav_idle.content_margin_bottom = 8
	var nav_active := StyleBoxFlat.new()
	nav_active.bg_color = Color.TRANSPARENT
	nav_active.border_color = ACCENT
	nav_active.border_width_bottom = 3
	nav_active.content_margin_top = 4
	nav_active.content_margin_bottom = 8
	for state in ["normal", "hover", "focus", "disabled"]:
		t.set_stylebox(state, "NavButton", nav_idle)
	t.set_stylebox("pressed", "NavButton", nav_active)
	t.set_stylebox("hover_pressed", "NavButton", nav_active)
	t.set_font("font", "NavButton", heading_font())
	t.set_font_size("font_size", "NavButton", 30)
	_set_button_colors(t, "NavButton", TEXT_DIM, TEXT, ACCENT)

	# Filter chips.
	t.set_type_variation("ChipButton", "Button")
	var chip := box(Color.TRANSPARENT, 6, BORDER, 1, 0)
	chip.content_margin_left = 14
	chip.content_margin_right = 14
	chip.content_margin_top = 5
	chip.content_margin_bottom = 5
	var chip_hover := chip.duplicate()
	chip_hover.bg_color = SURFACE_HOVER
	var chip_on := chip.duplicate()
	chip_on.bg_color = Color(ACCENT_DEEP, 0.55)
	chip_on.border_color = ACCENT
	t.set_stylebox("normal", "ChipButton", chip)
	t.set_stylebox("hover", "ChipButton", chip_hover)
	t.set_stylebox("pressed", "ChipButton", chip_on)
	t.set_stylebox("hover_pressed", "ChipButton", chip_on)
	t.set_stylebox("focus", "ChipButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "ChipButton", 14)
	_set_button_colors(t, "ChipButton", TEXT_DIM, TEXT, Color.WHITE)

	# Selectable list rows.
	t.set_type_variation("RowButton", "Button")
	var row := box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 0)
	var row_hover := box(Color(1, 1, 1, 0.045), 6, Color.TRANSPARENT, 0, 0)
	var row_on := box(Color(ACCENT_DEEP, 0.3), 6, Color.TRANSPARENT, 0, 0)
	row_on.border_color = ACCENT
	row_on.border_width_left = 3
	var row_on_hover := row_on.duplicate()
	row_on_hover.bg_color = Color(ACCENT_DEEP, 0.4)
	t.set_stylebox("normal", "RowButton", row)
	t.set_stylebox("hover", "RowButton", row_hover)
	t.set_stylebox("pressed", "RowButton", row_on)
	t.set_stylebox("hover_pressed", "RowButton", row_on_hover)
	t.set_stylebox("focus", "RowButton", StyleBoxEmpty.new())

	# Small square icon buttons (close, etc.).
	t.set_type_variation("IconButton", "Button")
	t.set_stylebox("normal", "IconButton", box(SURFACE_HI, 6, BORDER, 1, 6))
	t.set_stylebox("hover", "IconButton", box(SURFACE_HOVER, 6, BORDER_HI, 1, 6))
	t.set_stylebox("pressed", "IconButton", box(ACCENT_DEEP, 6, ACCENT, 1, 6))
	t.set_stylebox("focus", "IconButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "IconButton", 16)

	# Bookmaker price buttons.
	t.set_type_variation("OddsButton", "Button")
	t.set_stylebox("normal", "OddsButton", box(Color(BG, 0.7), 6, BORDER, 1, 0))
	t.set_stylebox("hover", "OddsButton", box(SURFACE_HOVER, 6, BORDER_HI, 1, 0))
	var odds_on := box(ACCENT_DEEP, 6, ACCENT, 1, 0)
	odds_on.shadow_color = Color(ACCENT, 0.35)
	odds_on.shadow_size = 8
	t.set_stylebox("pressed", "OddsButton", odds_on)
	t.set_stylebox("hover_pressed", "OddsButton", odds_on)
	t.set_stylebox("disabled", "OddsButton", box(Color(BG, 0.35), 6, Color(BORDER, 0.5), 1, 0))
	t.set_stylebox("focus", "OddsButton", StyleBoxEmpty.new())

	# Low-emphasis text button (Clear, etc.).
	t.set_type_variation("TextButton", "Button")
	var link := StyleBoxEmpty.new()
	link.content_margin_left = 6
	link.content_margin_right = 6
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "TextButton", link)
	t.set_font_size("font_size", "TextButton", 13)
	_set_button_colors(t, "TextButton", TEXT_MUTED, ACCENT, ACCENT)

	# Collapsible market title.
	t.set_type_variation("MarketHeader", "Button")
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(state, "MarketHeader", flat)
	t.set_font("font", "MarketHeader", heading_font())
	t.set_font_size("font_size", "MarketHeader", 19)
	_set_button_colors(t, "MarketHeader", TEXT, ACCENT, ACCENT)

	# Segmented view switcher (Odds / Stats).
	t.set_type_variation("SegmentButton", "ChipButton")
	t.set_font("font", "SegmentButton", heading_font())
	t.set_font_size("font_size", "SegmentButton", 20)

	# Glowing primary call-to-action.
	t.set_type_variation("PrimaryButton", "Button")
	for state in [["normal", ACCENT_DEEP, 0.35], ["hover", ACCENT_DEEP.lightened(0.12), 0.6], ["pressed", ACCENT, 0.7], ["hover_pressed", ACCENT, 0.7]]:
		var sb := box(state[1], 6, ACCENT.darkened(0.15), 1, 0)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = Color(ACCENT, state[2])
		sb.shadow_size = 12
		t.set_stylebox(state[0], "PrimaryButton", sb)
	t.set_stylebox("focus", "PrimaryButton", StyleBoxEmpty.new())
	t.set_font("font", "PrimaryButton", heading_font())
	t.set_font_size("font_size", "PrimaryButton", 24)
	_set_button_colors(t, "PrimaryButton", Color.WHITE, Color.WHITE, Color.WHITE)


static func _build_panel_variations(t: Theme) -> void:
	_panel_variation(t, "CardPanel", box(Color(SURFACE, 0.92), 12, BORDER, 1, 20))
	_panel_variation(t, "InsetPanel", box(Color(1, 1, 1, 0.03), 10, BORDER, 1, 18))
	_panel_variation(t, "SectionPanel", box(Color(1, 1, 1, 0.035), 6, Color.TRANSPARENT, 0, 8))
	_panel_variation(t, "PillPanel", box(BG, 6, BORDER, 1, 4))
	_panel_variation(t, "DateBox", box(SURFACE, 8, BORDER, 1, 10))
	_panel_variation(t, "CrestPanel", box(SURFACE_HI, 40, ACCENT, 2, 0))

	var status := box(Color(POSITIVE, 0.12), 12, Color(POSITIVE, 0.55), 1, 0)
	status.content_margin_left = 12
	status.content_margin_right = 12
	status.content_margin_top = 2
	status.content_margin_bottom = 2
	_panel_variation(t, "StatusPill", status)
	for variant in [["AccentPill", ACCENT], ["WarningPill", WARNING]]:
		var pill: StyleBoxFlat = status.duplicate()
		pill.bg_color = Color(variant[1], 0.12)
		pill.border_color = Color(variant[1], 0.55)
		_panel_variation(t, variant[0], pill)

	var slip := box(Color(SURFACE_HI, 0.98), 12, ACCENT_DEEP, 1, 16)
	slip.shadow_color = Color(0, 0, 0, 0.55)
	slip.shadow_size = 24
	_panel_variation(t, "SlipPanel", slip)

	var toast := box(Color(SURFACE_HI, 0.98), 10, POSITIVE, 1, 0)
	toast.content_margin_left = 20
	toast.content_margin_right = 20
	toast.content_margin_top = 12
	toast.content_margin_bottom = 12
	toast.shadow_color = Color(0, 0, 0, 0.5)
	toast.shadow_size = 18
	_panel_variation(t, "ToastPanel", toast)

	var top_bar := StyleBoxFlat.new()
	top_bar.bg_color = Color(BG.darkened(0.35), 0.9)
	top_bar.border_color = BORDER
	top_bar.border_width_bottom = 1
	_panel_variation(t, "TopBar", top_bar)


static func _label_variation(t: Theme, type_name: String, font: Font, size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, font)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)


static func _panel_variation(t: Theme, type_name: String, style: StyleBox) -> void:
	t.set_type_variation(type_name, "PanelContainer")
	t.set_stylebox("panel", type_name, style)


static func _set_button_colors(t: Theme, type_name: String, normal: Color, hover: Color, pressed: Color) -> void:
	t.set_color("font_color", type_name, normal)
	t.set_color("font_focus_color", type_name, normal)
	t.set_color("font_hover_color", type_name, hover)
	t.set_color("font_pressed_color", type_name, pressed)
	t.set_color("font_hover_pressed_color", type_name, pressed)
	t.set_color("font_disabled_color", type_name, TEXT_MUTED)
