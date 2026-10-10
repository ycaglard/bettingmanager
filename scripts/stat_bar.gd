extends Control
## Head-to-head comparison bar: home share grows from the left, away from the right.

const UITheme = preload("res://scripts/ui_theme.gd")
const GAP := 4.0

var home_value := 0.0
var away_value := 0.0
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()


func _init(home := 0.0, away := 0.0) -> void:
	home_value = home
	away_value = away
	custom_minimum_size = Vector2(0, 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_style_box(_pill(Color(1, 1, 1, 0.06)), Rect2(Vector2.ZERO, size))
	var total := home_value + away_value
	if total <= 0.0:
		return
	var usable := size.x - GAP
	var home_width := usable * (home_value / total) * progress
	var away_width := usable * (away_value / total) * progress
	var home_color := UITheme.HOME if home_value >= away_value else Color(UITheme.HOME, 0.4)
	var away_color := UITheme.AWAY if away_value >= home_value else Color(UITheme.AWAY, 0.4)
	if home_width > 0.5:
		draw_style_box(_pill(home_color), Rect2(0, 0, home_width, size.y))
	if away_width > 0.5:
		draw_style_box(_pill(away_color), Rect2(size.x - away_width, 0, away_width, size.y))


func _pill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(size.y * 0.5))
	sb.anti_aliasing = true
	return sb
