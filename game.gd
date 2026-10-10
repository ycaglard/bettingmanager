extends Control

const UITheme = preload("res://scripts/ui_theme.gd")

@onready var date_label: Label = %DateLabel
@onready var balance_label: Label = %BalanceLabel
@onready var day_label: Label = %DayLabel
@onready var nav_bar: HBoxContainer = %NavBar
@onready var tabs: TabContainer = %Tabs
@onready var continue_button: Button = %ContinueButton

var _nav_buttons: Array[Button] = []
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	theme = UITheme.build()
	_build_background()
	_update_date()
	GameCalendar.date_changed.connect(_update_date)
	_update_balance(BetManager.balance)
	BetManager.balance_changed.connect(_update_balance)
	BetManager.bet_placed.connect(_on_bet_placed)
	_build_toast()
	_build_nav()
	tabs.tab_changed.connect(_on_tab_changed)
	continue_button.pressed.connect(func(): GameCalendar.advance_day())


func _update_date() -> void:
	date_label.text = GameCalendar.formatted()
	day_label.text = GameCalendar.weekday()


func _update_balance(balance: float) -> void:
	balance_label.text = BetManager.format_money(balance)


func _build_nav() -> void:
	# One nav entry per tab, so adding a tab scene automatically adds navigation.
	var group := ButtonGroup.new()
	for i in tabs.get_tab_count():
		var button := Button.new()
		button.text = tabs.get_tab_title(i)
		button.theme_type_variation = &"NavButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = i == tabs.current_tab
		button.pressed.connect(tabs.set_current_tab.bind(i))
		nav_bar.add_child(button)
		_nav_buttons.append(button)


func _on_tab_changed(index: int) -> void:
	if index < _nav_buttons.size():
		_nav_buttons[index].button_pressed = true
	var page := tabs.get_tab_control(index)
	page.modulate.a = 0.0
	create_tween().tween_property(page, "modulate:a", 1.0, 0.25)


func _build_background() -> void:
	_add_glow(Color(UITheme.ACCENT_DEEP, 0.35), Vector2(0.1, 0.0), Vector2(0.75, 0.7))
	_add_glow(Color(UITheme.AWAY, 0.08), Vector2(1.0, 1.0), Vector2(0.45, 0.4))


func _add_glow(color: Color, from: Vector2, to: Vector2) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = from
	texture.fill_to = to
	texture.width = 256
	texture.height = 256
	var glow := TextureRect.new()
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	move_child(glow, 1)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.theme_type_variation = &"ToastPanel"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = Label.new()
	_toast_label.theme_type_variation = &"StrongLabel"
	_toast.add_child(_toast_label)
	add_child(_toast)


func _on_bet_placed(bet: Dictionary) -> void:
	var kind := "Single" if bet.type == "single" else "%d-leg parlay" % bet.legs.size()
	_toast_label.text = "✓  %s placed  ·  %s @ %.2f  ·  returns %s" % [
		kind, BetManager.format_money(bet.stake), bet.total_odds, BetManager.format_money(bet.potential_return)]
	_toast.size = _toast.get_combined_minimum_size()
	var rest := Vector2((size.x - _toast.size.x) * 0.5, size.y - _toast.size.y - 40.0)
	_toast.position = rest + Vector2(0, 30)
	_toast.modulate.a = 0.0
	_toast.visible = true
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(_toast, "position", rest, 0.3)
	_toast_tween.parallel().tween_property(_toast, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_toast.hide)