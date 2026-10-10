extends RefCounted
## A rule-based manager for one side. Between minutes the match asks it for
## commands (see LiveMatch.apply_command); it never touches match state itself,
## so the same rules drive a watched match and an instant sim.
##
## Style follows the scoreline, and substitutions replace tired players,
## chase or protect a result, in that order of urgency.

const T = preload("res://scripts/engine/match_types.gd")
const MatchPlayer = preload("res://scripts/engine/match_player.gd")

## Decide once every this many minutes, offset by side so both managers do not act together.
const DECISION_INTERVAL := 3
const CHASING_FROM_MINUTE := 60
const PROTECTING_FROM_MINUTE := 70
const TACTICAL_SUB_FROM_MINUTE := 65
## Below this, a first-half substitution is forced rather than tactical.
const FIRST_HALF_EMERGENCY_CONDITION := 35.0
## Condition (0-100) drains about 0.2 a minute, so "tired" is relative: the bar
## starts at FRESHNESS_FLOOR after half time and rises as the match wears on.
const FRESHNESS_FLOOR := 88.0
const FRESHNESS_RISE_PER_MINUTE := 0.15
## Below this a player comes off whatever the pacing of changes.
const EXHAUSTED_CONDITION := 40.0
const FIRST_SUBSTITUTION_MINUTE := 55
const SUBSTITUTION_SPACING := 10

var side: int
var _base_style := -1


func _init(p_side: int) -> void:
	side = p_side


## Commands to issue now, in order. Empty when the manager stands pat.
func decide(live: RefCounted) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var team: RefCounted = live.home if side == T.Side.HOME else live.away
	if _base_style < 0:
		_base_style = team.play_style
	if live.minute % DECISION_INTERVAL != side:
		return commands
	var style := _wanted_style(live, team)
	if style != team.play_style:
		commands.append({"type": "play_style", "side": side, "style": style})
	var substitution := _wanted_substitution(live, team)
	if not substitution.is_empty():
		commands.append(substitution)
	return commands


func _goal_difference(live: RefCounted) -> int:
	return live.score[side] - live.score[T.opposite(side)]


func _men_down(live: RefCounted, team: RefCounted) -> int:
	var count := 0
	for player in team.players:
		if live.sent_off.has(player.id):
			count += 1
	return count


func _wanted_style(live: RefCounted, team: RefCounted) -> int:
	var difference := _goal_difference(live)
	if difference < 0 and live.minute >= CHASING_FROM_MINUTE:
		return T.PlayStyle.ATTACKING
	if difference > 0 and live.minute >= PROTECTING_FROM_MINUTE:
		return T.PlayStyle.DEFENSIVE
	if difference > 0 and _men_down(live, team) > 0 and live.minute >= CHASING_FROM_MINUTE - 5:
		return T.PlayStyle.DEFENSIVE
	return _base_style


func _wanted_substitution(live: RefCounted, team: RefCounted) -> Dictionary:
	var made: int = live.subs_made[side]
	if made >= live.config.max_subs:
		return {}
	var allowed := _substitutions_allowed_by(live.minute)
	var tired := _most_tired(live, team)
	if tired != null and (made < allowed or live.condition_of(tired.id) < EXHAUSTED_CONDITION):
		var replacement := _best_bench_player(live, team, tired.position)
		if replacement == null:
			replacement = _best_bench_player(live, team, -1)
		if replacement != null:
			return _substitution(tired, replacement)
	if made >= allowed:
		return {}
	return _tactical_substitution(live, team)


## Managers spread their changes through the second half rather than spending them at once.
func _substitutions_allowed_by(minute: int) -> int:
	if minute < FIRST_SUBSTITUTION_MINUTE:
		return 0
	return (minute - FIRST_SUBSTITUTION_MINUTE) / SUBSTITUTION_SPACING + 1


## The tiredest outfield player, if he is worn out for this stage of the match.
func _most_tired(live: RefCounted, team: RefCounted) -> RefCounted:
	var limit := FRESHNESS_FLOOR + maxf(0.0, live.minute - 45.0) * FRESHNESS_RISE_PER_MINUTE
	if live.minute <= 45:
		limit = FIRST_HALF_EMERGENCY_CONDITION
	var tired: RefCounted = null
	for player in team.players:
		if player.position == T.Position.GOALKEEPER or live.sent_off.has(player.id):
			continue
		var condition: float = live.condition_of(player.id)
		if condition < limit and (tired == null or condition < live.condition_of(tired.id)):
			tired = player
	return tired


## Trailing late: swap a midfielder or defender for a forward. Protecting a lead
## late: swap a forward for a defender.
func _tactical_substitution(live: RefCounted, team: RefCounted) -> Dictionary:
	if live.minute < TACTICAL_SUB_FROM_MINUTE:
		return {}
	var difference := _goal_difference(live)
	if difference < 0:
		return _swap(live, team, [T.Position.DEFENDER, T.Position.MIDFIELDER], T.Position.FORWARD)
	if difference > 0 and live.minute >= PROTECTING_FROM_MINUTE + 5:
		return _swap(live, team, [T.Position.FORWARD], T.Position.DEFENDER)
	return {}


func _swap(live: RefCounted, team: RefCounted, off_positions: Array, on_position: int) -> Dictionary:
	var replacement := _best_bench_player(live, team, on_position)
	if replacement == null:
		return {}
	var weakest: RefCounted = null
	for player in team.players:
		if player.position in off_positions and not live.sent_off.has(player.id):
			if weakest == null or _rating(player) < _rating(weakest):
				weakest = player
	if weakest == null:
		return {}
	return _substitution(weakest, replacement)


## Best fresh bench player in `position` (-1 = any outfielder). A player who
## was already taken off cannot return.
func _best_bench_player(live: RefCounted, team: RefCounted, position: int) -> RefCounted:
	var best: RefCounted = null
	for player in team.bench:
		if live.subbed_off.has(player.id) or player.position == T.Position.GOALKEEPER:
			continue
		if position >= 0 and player.position != position:
			continue
		if best == null or _rating(player) > _rating(best):
			best = player
	return best


func _substitution(player_off: RefCounted, player_on: RefCounted) -> Dictionary:
	return {"type": "substitute", "side": side, "player_off": player_off.id, "player_on": player_on.id}


func _rating(player: RefCounted) -> float:
	var total := 0.0
	for attribute in MatchPlayer.ATTRIBUTES:
		if attribute != "goalkeeping":
			total += float(player.get(attribute))
	return total / (MatchPlayer.ATTRIBUTES.size() - 1)
