extends RefCounted
## A side in a match: the eleven on the pitch, the bench and the play style.

const T = preload("res://scripts/engine/match_types.gd")

var id := ""
var display_name := ""
var play_style: int = T.PlayStyle.BALANCED
## Players on the pitch. Substitutions swap entries with the bench.
var players: Array = []
var bench: Array = []


func find_on_pitch(player_id: String) -> RefCounted:
	for player in players:
		if player.id == player_id:
			return player
	return null


func find_on_bench(player_id: String) -> RefCounted:
	for player in bench:
		if player.id == player_id:
			return player
	return null
