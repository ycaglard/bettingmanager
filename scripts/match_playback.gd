extends RefCounted
## Drives a LiveMatch in real time for watching. The owner calls advance(delta)
## every frame, so a test can feed a fake clock. It pauses itself at half time.

signal minute_played(minute: int, events: Array)
signal half_time
signal finished

const T = preload("res://scripts/engine/match_types.gd")
const SECONDS_PER_MINUTE := 0.8
const SPEEDS := [1, 2, 4, 8]

var live: RefCounted
var speed := 1
var paused := false

var _carry := 0.0


func _init(p_live: RefCounted) -> void:
	live = p_live


func is_finished() -> bool:
	return live.is_finished()


func set_speed(p_speed: int) -> void:
	if p_speed in SPEEDS:
		speed = p_speed


func advance(delta: float) -> void:
	if paused or live.is_finished():
		return
	_carry += delta * speed
	while _carry >= SECONDS_PER_MINUTE and not paused and not live.is_finished():
		_carry -= SECONDS_PER_MINUTE
		_step()


## Leaves half time (or any pause) and carries on playing.
func resume() -> void:
	paused = false


func skip_to_half_time() -> void:
	paused = false
	while not live.is_finished() and live.phase != T.Phase.HALF_TIME:
		_step(false)
	if not live.is_finished():
		paused = true
		half_time.emit()


func skip_to_end() -> void:
	paused = false
	while not live.is_finished():
		_step(false)


func _step(pause_at_half_time := true) -> void:
	var events: Array = live.step_minute()
	minute_played.emit(live.minute, events)
	if live.is_finished():
		finished.emit()
	elif pause_at_half_time and live.phase == T.Phase.HALF_TIME:
		paused = true
		half_time.emit()
