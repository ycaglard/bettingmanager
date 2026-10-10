extends Control
## Five-zone pitch strip: the home side attacks to the right. Shows where the ball
## is and who has it, mirroring the engine's zone model.

const UITheme = preload("res://scripts/ui_theme.gd")
const T = preload("res://scripts/engine/match_types.gd")

const ZONE_COUNT := 5
const BALL_RADIUS := 9.0

var _zone: int = T.Zone.MIDFIELD
var _possession: int = T.Side.HOME
var _ball_x := 0.5:
	set(value):
		_ball_x = value
		queue_redraw()
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(0, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_state(zone: int, possession: int) -> void:
	_possession = possession
	if zone != _zone:
		_zone = zone
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_ball_x", _zone_center(zone), 0.25)
	queue_redraw()


func _zone_center(zone: int) -> float:
	return (zone + 0.5) / ZONE_COUNT


func _draw() -> void:
	var zone_width := size.x / ZONE_COUNT
	for i in ZONE_COUNT:
		var shade := 0.05 if i % 2 == 0 else 0.1
		var color := Color(UITheme.POSITIVE, shade + (0.08 if i == _zone else 0.0))
		draw_rect(Rect2(i * zone_width, 0, zone_width, size.y), color)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.BORDER, false, 2.0)
	draw_line(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y), UITheme.BORDER, 1.5)
	draw_arc(size * 0.5, size.y * 0.22, 0.0, TAU, 40, UITheme.BORDER, 1.5, true)
	var box_height := size.y * 0.6
	for x in [0.0, size.x - zone_width * 0.7]:
		draw_rect(Rect2(x, (size.y - box_height) * 0.5, zone_width * 0.7, box_height), UITheme.BORDER, false, 1.5)
	var side_color := UITheme.HOME if _possession == T.Side.HOME else UITheme.AWAY
	var center := Vector2(size.x * _ball_x, size.y * 0.5)
	draw_circle(center, BALL_RADIUS + 5.0, Color(side_color, 0.25), true, -1.0, true)
	draw_circle(center, BALL_RADIUS, side_color, true, -1.0, true)
	draw_arc(center, BALL_RADIUS, 0.0, TAU, 24, Color.WHITE, 1.5, true)
