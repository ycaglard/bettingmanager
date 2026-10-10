extends Node
## Global in-game date (autoload "GameCalendar"). Static for now; the
## Continue button will advance it once simulation exists.

signal date_changed

const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var current_date := {"day": 7, "month": 10, "year": 2026}


## Plays today's fixtures, then moves to the next day. Returns matches played.
func advance_day() -> int:
	var played := MatchDirector.sim_day(formatted())
	var unix := Time.get_unix_time_from_datetime_dict(current_date) + 86400
	var next := Time.get_datetime_dict_from_unix_time(unix)
	current_date = {"day": next.day, "month": next.month, "year": next.year}
	date_changed.emit()
	return played


func formatted() -> String:
	return "%02d/%02d/%02d" % [current_date.day, current_date.month, current_date.year % 100]


func weekday() -> String:
	var unix := Time.get_unix_time_from_datetime_dict(current_date)
	return WEEKDAYS[Time.get_datetime_dict_from_unix_time(unix).weekday]


## Short weekday ("Sat") for a dd/mm/yy date string.
static func short_weekday(date: String) -> String:
	var parts := date.split("/")
	if parts.size() != 3:
		return ""
	var unix := Time.get_unix_time_from_datetime_dict({
		"day": int(parts[0]), "month": int(parts[1]), "year": 2000 + int(parts[2]),
	})
	return WEEKDAYS[Time.get_datetime_dict_from_unix_time(unix).weekday].left(3)
