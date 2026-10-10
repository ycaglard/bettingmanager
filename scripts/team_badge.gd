extends Control
## Circular placeholder crest generated from a team name.

const UITheme = preload("res://scripts/ui_theme.gd")

var team_name := "":
	set(value):
		team_name = value
		queue_redraw()


func _init(team := "", diameter := 32.0) -> void:
	team_name = team
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func color_for(team: String) -> Color:
	# Golden-ratio spacing keeps neighbouring team numbers visually distinct.
	var key := float(absi(team.hash()) % 1000) + team.get_slice("team", 1).to_float() * 7.0
	var hue := fposmod(key * 0.618034, 1.0)
	return Color.from_hsv(hue, 0.6, 0.95)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	var color := color_for(team_name)
	draw_circle(center, radius, color.darkened(0.6), true, -1.0, true)
	draw_arc(center, radius - 1.0, 0.0, TAU, 64, color, maxf(1.5, radius * 0.08), true)

	var font := UITheme.heading_font()
	var font_size := int(radius * 0.9)
	var text := _initials()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(center.x - text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.TEXT)


func _initials() -> String:
	var number := team_name.get_slice("team", 1)
	return number if not number.is_empty() else team_name.left(2).to_upper()
