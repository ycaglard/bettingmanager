extends RefCounted
## One thing that happened in a match. The event list is the single source of
## truth: score, statistics and ratings are all derived from it.
##
## `side` is the side that performed the action: the passer for a PASS or
## PASS_INTERCEPTED, the interceptor for an INTERCEPTION, the offender for a FOUL,
## the side caught offside for an OFFSIDE (player_id is the receiver).

var minute := 0
var type := 0
var side := 0
var zone := 0
var player_id := ""
var secondary_id := ""
## Extra context, e.g. {"penalty": true} on a GOAL.
var detail: Dictionary = {}


func _init(p_minute: int, p_type: int, p_side: int, p_zone: int) -> void:
	minute = p_minute
	type = p_type
	side = p_side
	zone = p_zone
