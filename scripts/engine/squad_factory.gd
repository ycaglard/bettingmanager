extends RefCounted
## Builds squads for the match engine. Deterministic: the same team id and
## strength always produce the same players, so a fixture replays identically.
## A stand-in until the game has real player data.

const T = preload("res://scripts/engine/match_types.gd")
const MatchPlayer = preload("res://scripts/engine/match_player.gd")
const MatchTeam = preload("res://scripts/engine/match_team.gd")

## 4-4-2 starters, then a seven-man bench.
const STARTING_SLOTS := [
	T.Position.GOALKEEPER,
	T.Position.DEFENDER, T.Position.DEFENDER, T.Position.DEFENDER, T.Position.DEFENDER,
	T.Position.MIDFIELDER, T.Position.MIDFIELDER, T.Position.MIDFIELDER, T.Position.MIDFIELDER,
	T.Position.FORWARD, T.Position.FORWARD,
]
const BENCH_SLOTS := [
	T.Position.GOALKEEPER,
	T.Position.DEFENDER, T.Position.DEFENDER,
	T.Position.MIDFIELDER, T.Position.MIDFIELDER,
	T.Position.FORWARD, T.Position.FORWARD,
]

## Offsets from the team's strength for the attributes each position leans on.
const POSITION_BIAS := {
	T.Position.GOALKEEPER: {"passing": -8, "shooting": -25, "tackling": -20, "defending": -10, "pace": -10},
	T.Position.DEFENDER: {"defending": 8, "tackling": 8, "shooting": -15, "passing": -3},
	T.Position.MIDFIELDER: {"passing": 8, "composure": 4, "stamina": 6, "shooting": -5},
	T.Position.FORWARD: {"shooting": 10, "pace": 6, "composure": 3, "defending": -15, "tackling": -15},
}
const OUTFIELD_ATTRIBUTES := ["passing", "shooting", "tackling", "defending", "pace", "stamina", "composure"]


## A team's strength (roughly 40-70) derived from its id, when none is given.
static func strength_for(team_id: String) -> float:
	return 42.0 + posmod(team_id.hash(), 26)


static func generate(team_id: String, strength := -1.0, play_style := T.PlayStyle.BALANCED) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = team_id.hash()
	var base := strength if strength >= 0.0 else strength_for(team_id)

	var team := MatchTeam.new()
	team.id = team_id
	team.display_name = team_id
	team.play_style = play_style
	var number := 1
	for slot in STARTING_SLOTS:
		team.players.append(_make_player(team_id, number, slot, base, rng))
		number += 1
	for slot in BENCH_SLOTS:
		# The bench is a little weaker than the starters.
		team.bench.append(_make_player(team_id, number, slot, base - 6.0, rng))
		number += 1
	return team


static func _make_player(team_id: String, number: int, position: int, base: float, rng: RandomNumberGenerator) -> RefCounted:
	var player := MatchPlayer.new()
	player.id = "%s-p%02d" % [team_id, number]
	player.display_name = "%s P%d" % [team_id, number]
	player.position = position
	player.condition = rng.randf_range(90.0, 100.0)
	var bias: Dictionary = POSITION_BIAS[position]
	for attribute in OUTFIELD_ATTRIBUTES:
		player.set(attribute, _rate(base + bias.get(attribute, 0) + rng.randi_range(-7, 7)))
	player.aggression = _rate(rng.randi_range(30, 70))
	if position == T.Position.GOALKEEPER:
		player.goalkeeping = _rate(base + 15 + rng.randi_range(-5, 5))
	else:
		player.goalkeeping = _rate(rng.randi_range(10, 25))
	return player


static func _rate(value: float) -> int:
	return clampi(int(round(value)), 5, 99)
