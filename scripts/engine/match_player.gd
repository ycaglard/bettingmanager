extends RefCounted
## A player as the match engine sees him. Deliberately independent of any
## future game-wide player model; an adapter builds these from game data.

const T = preload("res://scripts/engine/match_types.gd")

const ATTRIBUTES := [
	"passing", "shooting", "tackling", "defending", "pace",
	"stamina", "composure", "goalkeeping", "aggression",
]

var id := ""
var display_name := ""
var position: int = T.Position.MIDFIELDER
var passing := 50
var shooting := 50
var tackling := 50
var defending := 50
var pace := 50
var stamina := 50
var composure := 50
var goalkeeping := 20
var aggression := 50
## Condition (0-100) at kick-off; the match tracks the in-game value itself.
var condition := 100.0


## Stand-in used when a side has nobody left to pick, so the engine never
## indexes an empty squad.
static func nobody() -> RefCounted:
	var player := new()
	player.display_name = "Nobody"
	player.passing = 30
	player.shooting = 30
	player.tackling = 30
	player.defending = 30
	player.pace = 30
	player.stamina = 30
	player.composure = 30
	player.goalkeeping = 10
	player.aggression = 30
	return player


static func from_dict(data: Dictionary) -> RefCounted:
	var player := new()
	player.id = str(data.get("id", ""))
	player.display_name = str(data.get("name", player.id))
	player.position = int(data.get("position", T.Position.MIDFIELDER))
	player.condition = float(data.get("condition", 100.0))
	for attribute in ATTRIBUTES:
		if data.has(attribute):
			player.set(attribute, int(data[attribute]))
	return player
