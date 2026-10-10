extends RefCounted
## Small pure helpers shared by the match engine: the contest primitive,
## condition scaling and play-style modifiers.

const T = preload("res://scripts/engine/match_types.gd")

enum StylePhase { MIDFIELD, ATTACK, DEFENSE, PRESS }

## Rows follow T.PlayStyle order; columns follow StylePhase order. Each style
## buys strength in one phase and pays for it in another.
const STYLE_MODS := [
	[1.00, 1.00, 1.00, 1.00],  # BALANCED
	[1.00, 1.08, 0.95, 1.00],  # ATTACKING
	[1.00, 0.95, 1.08, 1.00],  # DEFENSIVE
	[1.10, 0.98, 1.00, 1.00],  # POSSESSION
	[0.94, 1.12, 1.00, 1.00],  # COUNTER
	[1.00, 1.00, 0.96, 1.15],  # HIGH_PRESS
]


## Probability that the attacking value beats the defending one. Every duel in
## the engine goes through this so strength gives an edge but never a certainty.
## `sharpness` below 1 flattens the edge; it is needed because a possession
## chain compounds a small advantage at every step.
static func contest(attack: float, defence: float, sharpness := 1.0) -> float:
	var total := attack + defence
	if total <= 0.0:
		return 0.5
	if sharpness == 1.0:
		return attack / total
	var sharp_attack := pow(attack, sharpness)
	return sharp_attack / (sharp_attack + pow(defence, sharpness))


## A tired player keeps most of his skill: 100 condition is full skill, 0 is 65%.
static func condition_factor(condition: float) -> float:
	return 0.65 + 0.35 * clampf(condition, 0.0, 100.0) / 100.0


static func style_mod(style: int, phase: int) -> float:
	return STYLE_MODS[style][phase]
