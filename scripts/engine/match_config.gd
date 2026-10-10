extends RefCounted
## Tunable probabilities and multipliers for a match. Every default is a first
## guess to be calibrated with scripts/engine/bench.gd, not a measured value.

var home_advantage := 1.06
## Below 1 flattens every duel, so a strength gap matters less per step.
var duel_sharpness := 0.6
## Extra minutes at the end of each half are rolled in 0..stoppage_max.
var stoppage_max := 4
## Condition points lost per minute by an average-stamina player.
var fatigue_per_minute := 0.2
## Bias that makes a clean pass out of defence likelier than a midfield duel.
var buildup_edge := 1.5

var shot_on_target_base := 0.42
var goal_conversion_base := 0.33
var shot_blocked_share := 0.35
var save_to_corner_share := 0.35

var foul_base := 0.40
var yellow_base := 0.18
var red_base := 0.004
## Chance per shot that the defence fouls the shooter inside the box.
var box_foul_rate := 0.03
## Share of box fouls that are given as penalties.
var penalty_share := 0.25
var penalty_conversion := 0.76

var corner_after_failed_attack := 0.20
var corner_reaches_box := 0.30

## Chance that a completed forward pass into the attacking third catches the
## receiver offside when the defensive line and the receiver's awareness are level.
var offside_base := 0.10

var max_subs := 5
