extends RefCounted
## Squads for the engine, by team id. Generated deterministically for now;
## swap the body of get_team for real rosters once they exist.

const SquadFactory = preload("res://scripts/engine/squad_factory.gd")

## Squads carry mutable condition, so each match gets a fresh copy.
static func get_team(team_id: String) -> RefCounted:
	return SquadFactory.generate(team_id)
