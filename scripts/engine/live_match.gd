extends RefCounted
## Minute-by-minute football match simulation.
##
## The whole match is (ball zone, possession side, minute). Each minute spends
## stamina, resolves one to three actions in the zone the ball is in, then runs
## a midfield possession contest. Every duel is a ratio contest (see
## match_shared.gd) rolled on one seeded RNG, so the same seed and squads always
## replay the same match. Everything that happens is an event in `events`;
## statistics are derived from that list by match_report.gd.
##
## Usage:
##   var match := LiveMatch.new(home_team, away_team, seed)
##   while not match.is_finished():
##       match.step_minute()
##   var stats := match.build_report().to_stats_dict()

const T = preload("res://scripts/engine/match_types.gd")
const Shared = preload("res://scripts/engine/match_shared.gd")
const MatchEvent = preload("res://scripts/engine/match_event.gd")
const MatchConfig = preload("res://scripts/engine/match_config.gd")
const MatchPlayer = preload("res://scripts/engine/match_player.gd")
const MatchReport = preload("res://scripts/engine/match_report.gd")

const HALF_LENGTH := 45
## Hard stop so a bug can never spin a headless run forever.
const MAX_STEPS := 400

var home: RefCounted
var away: RefCounted
var config: RefCounted
var rng := RandomNumberGenerator.new()
## Kept so a match can be replayed exactly (tests, bug reports).
var seed_used := 0

var phase: int = T.Phase.PRE_KICK_OFF
var minute := 0
var score: Array[int] = [0, 0]
var ball_zone: int = T.Zone.MIDFIELD
var possession: int = T.Side.HOME
var events: Array = []
var possession_ticks: Array[int] = [0, 0]
var subs_made: Array[int] = [0, 0]
## player_id -> yellow cards shown so far.
var yellows: Dictionary = {}
## player_id -> true once sent off.
var sent_off: Dictionary = {}
## player_id -> true once substituted off; he cannot return.
var subbed_off: Dictionary = {}
## One optional manager per side (index = Side); see match_manager.gd.
var managers: Array = [null, null]

## player_id -> in-match condition (0-100); the squad objects are never mutated.
var _conditions: Dictionary = {}
var _stoppage := 0
var _period_started_at := 0


func _init(p_home: RefCounted, p_away: RefCounted, p_seed: int, p_config: RefCounted = null) -> void:
	home = p_home
	away = p_away
	config = p_config if p_config != null else MatchConfig.new()
	rng.seed = p_seed
	seed_used = p_seed
	for team in [home, away]:
		for player in team.players:
			_conditions[player.id] = player.condition


func is_finished() -> bool:
	return phase == T.Phase.FINISHED


## Plays one minute (or one phase change) and returns the events it produced.
func step_minute() -> Array:
	var first_new_event := events.size()
	if phase != T.Phase.PRE_KICK_OFF and phase != T.Phase.FINISHED:
		_run_managers()
	match phase:
		T.Phase.PRE_KICK_OFF:
			_start_match()
		T.Phase.FIRST_HALF, T.Phase.SECOND_HALF:
			_play_minute()
		T.Phase.HALF_TIME:
			_start_second_half()
	return events.slice(first_new_event)


func simulate_to_end() -> RefCounted:
	var steps := 0
	while not is_finished() and steps < MAX_STEPS:
		step_minute()
		steps += 1
	return build_report()


func build_report() -> RefCounted:
	return MatchReport.from_events(events, possession_ticks, minute)


func condition_of(player_id: String) -> float:
	return float(_conditions.get(player_id, 100.0))


## Commands can be issued between minutes by the user or an AI manager.
##   {"type": "substitute", "side", "player_off", "player_on"}
##   {"type": "play_style", "side", "style"}
## Returns "" on success or an error code.
func apply_command(command: Dictionary) -> String:
	var side: int = command.get("side", T.Side.HOME)
	match command.get("type", ""):
		"substitute":
			return _substitute(side, str(command.get("player_off", "")), str(command.get("player_on", "")))
		"play_style":
			_team(side).play_style = int(command.get("style", T.PlayStyle.BALANCED))
			return ""
	return "unknown_command"


# --- Match flow ---------------------------------------------------------------

func _start_match() -> void:
	phase = T.Phase.FIRST_HALF
	minute = 0
	_period_started_at = 0
	ball_zone = T.Zone.MIDFIELD
	possession = T.Side.HOME
	_stoppage = rng.randi_range(0, config.stoppage_max)
	_emit(T.EventType.KICK_OFF, T.Side.HOME, T.Zone.MIDFIELD)


func _start_second_half() -> void:
	phase = T.Phase.SECOND_HALF
	# The clock runs on through stoppage, so the half is counted from here.
	_period_started_at = minute
	ball_zone = T.Zone.MIDFIELD
	possession = T.Side.AWAY
	_stoppage = rng.randi_range(0, config.stoppage_max)
	_emit(T.EventType.KICK_OFF, T.Side.AWAY, T.Zone.MIDFIELD)


func _play_minute() -> void:
	minute += 1
	possession_ticks[possession] += 1
	_deplete_stamina()
	for _action in rng.randi_range(1, 3):
		_resolve_action()
	_contest_possession()
	_check_period_end()


func _check_period_end() -> void:
	if minute - _period_started_at < HALF_LENGTH + _stoppage:
		return
	if phase == T.Phase.FIRST_HALF:
		phase = T.Phase.HALF_TIME
		_emit(T.EventType.HALF_TIME, T.Side.HOME, T.Zone.MIDFIELD)
	else:
		phase = T.Phase.FINISHED
		_emit(T.EventType.FULL_TIME, T.Side.HOME, T.Zone.MIDFIELD)


## Gives each side's manager, if any, the chance to act between minutes. A
## rejected command is dropped: the manager decides again at its next turn.
func _run_managers() -> void:
	for manager in managers:
		if manager == null:
			continue
		for command in manager.decide(self):
			apply_command(command)


# --- Stamina and ratings ------------------------------------------------------

func _deplete_stamina() -> void:
	for team in [home, away]:
		for player in team.players:
			if sent_off.has(player.id):
				continue
			# Higher stamina loses less; 50 stamina is the reference rate.
			var loss: float = config.fatigue_per_minute * (1.4 - player.stamina / 100.0 * 0.8)
			_conditions[player.id] = maxf(condition_of(player.id) - loss, 5.0)


func _skill(player: RefCounted, base: float) -> float:
	return base * Shared.condition_factor(condition_of(player.id))


func _venue(side: int) -> float:
	return config.home_advantage if side == T.Side.HOME else 1.0


func _duel(attack: float, defence: float) -> float:
	return Shared.contest(attack, defence, config.duel_sharpness)


func _style(side: int, style_phase: int) -> float:
	return Shared.style_mod(_team(side).play_style, style_phase)


## Average of `rate` over a side's available players in `position`.
func _average_rating(side: int, position: int, rate: Callable) -> float:
	var total := 0.0
	var count := 0
	for player in _team(side).players:
		if player.position == position and not sent_off.has(player.id):
			total += _skill(player, rate.call(player))
			count += 1
	return total / count if count > 0 else 0.0


func _midfield_rating(side: int) -> float:
	var rating := _average_rating(side, T.Position.MIDFIELDER, func(p): return (p.passing + p.tackling + p.composure) / 3.0)
	# A side with no midfielders left still plays, just much worse.
	return rating if rating > 0.0 else 25.0


func _press_rating(side: int) -> float:
	var rating := _average_rating(side, T.Position.MIDFIELDER, func(p): return (p.tackling + p.pace + p.stamina) / 3.0)
	return maxf(rating, 25.0) * _style(side, Shared.StylePhase.PRESS) * _venue(side)


# --- Possession ---------------------------------------------------------------

func _contest_possession() -> void:
	var defending := T.opposite(possession)
	var keeps := _midfield_rating(possession) * _style(possession, Shared.StylePhase.MIDFIELD) * _venue(possession)
	var wins := _midfield_rating(defending) * _style(defending, Shared.StylePhase.MIDFIELD) \
		* _style(defending, Shared.StylePhase.PRESS) * _venue(defending)
	if rng.randf() >= _duel(keeps, wins):
		possession = defending
		ball_zone = T.Zone.MIDFIELD


# --- Action resolution --------------------------------------------------------

func _resolve_action() -> void:
	var attacking := possession
	var defending := T.opposite(attacking)
	if ball_zone == T.attacking_box(attacking):
		_resolve_shot(attacking)
	elif ball_zone == T.attacking_third(attacking):
		_resolve_attacking_third(attacking, defending)
	elif ball_zone == T.Zone.MIDFIELD:
		_resolve_midfield(attacking, defending)
	else:
		_resolve_buildup(attacking, defending)


## Playing out from the back against the opposing midfield's press. A turnover
## here hands the opponent the ball in their attacking third.
func _resolve_buildup(attacking: int, defending: int) -> void:
	var passer := _pick(attacking, T.Position.DEFENDER)
	var skill := _skill(passer, (passer.passing * 0.6 + passer.composure * 0.4)) \
		* _style(attacking, Shared.StylePhase.MIDFIELD) * _venue(attacking)
	if rng.randf() < _duel(skill * config.buildup_edge, _press_rating(defending)):
		_emit(T.EventType.PASS, attacking, ball_zone, passer.id)
		ball_zone = T.Zone.MIDFIELD
		return
	var interceptor := _pick(defending, T.Position.MIDFIELDER)
	_emit(T.EventType.PASS_INTERCEPTED, attacking, ball_zone, passer.id)
	_emit(T.EventType.INTERCEPTION, defending, ball_zone, interceptor.id)
	possession = defending


func _resolve_midfield(attacking: int, defending: int) -> void:
	var carrier := _pick(attacking, T.Position.MIDFIELDER)
	var challenger := _pick(defending, T.Position.MIDFIELDER)
	var attack := _skill(carrier, carrier.passing * 0.4 + carrier.composure * 0.3 + carrier.pace * 0.3) \
		* _style(attacking, Shared.StylePhase.MIDFIELD) * _venue(attacking)
	var defence := _skill(challenger, challenger.tackling * 0.4 + challenger.defending * 0.3 + challenger.composure * 0.3) \
		* _style(defending, Shared.StylePhase.MIDFIELD) * _venue(defending)
	if rng.randf() < _duel(attack, defence):
		if _maybe_offside(attacking, defending, T.Zone.MIDFIELD):
			return
		_emit(T.EventType.PASS, attacking, T.Zone.MIDFIELD, carrier.id)
		ball_zone = T.attacking_third(attacking)
		return
	if rng.randf() < 0.6:
		_emit(T.EventType.TACKLE, defending, T.Zone.MIDFIELD, challenger.id)
		if _maybe_foul(defending, challenger, carrier, T.Zone.MIDFIELD):
			# The fouled side keeps the ball for the free kick.
			possession = attacking
			ball_zone = T.Zone.MIDFIELD
			return
	else:
		_emit(T.EventType.INTERCEPTION, defending, T.Zone.MIDFIELD, challenger.id)
	possession = defending
	ball_zone = T.Zone.MIDFIELD


## A through ball played to a forward who started beyond the last defender.
## Sharp, organised defences and anxious receivers make it more likely. On a
## flag the pass counts as an attempt, and the defence takes a free kick.
func _maybe_offside(attacking: int, defending: int, from_zone: int) -> bool:
	var receiver := _pick(attacking, T.Position.FORWARD)
	var line := _average_rating(defending, T.Position.DEFENDER, func(p): return (p.defending + p.composure) / 2.0)
	var awareness := _skill(receiver, (receiver.composure + receiver.pace) / 2.0)
	if line <= 0.0 or awareness <= 0.0:
		return false
	var chance: float = config.offside_base * clampf(line / awareness, 0.5, 1.6)
	if rng.randf() >= chance:
		return false
	_emit(T.EventType.OFFSIDE, attacking, from_zone, receiver.id)
	_emit(T.EventType.FREE_KICK, defending, from_zone)
	possession = defending
	ball_zone = T.own_third(defending)
	return true


func _resolve_attacking_third(attacking: int, defending: int) -> void:
	var runner := _pick(attacking, T.Position.FORWARD)
	var marker := _pick(defending, T.Position.DEFENDER)
	var zone := T.attacking_third(attacking)
	var attack := _skill(runner, runner.pace * 0.4 + runner.composure * 0.3 + runner.shooting * 0.3) \
		* _style(attacking, Shared.StylePhase.ATTACK) * _venue(attacking)
	var defence := _skill(marker, marker.defending * 0.5 + marker.tackling * 0.3 + marker.pace * 0.2) \
		* _style(defending, Shared.StylePhase.DEFENSE) * _venue(defending)
	if rng.randf() < _duel(attack, defence):
		_emit(T.EventType.DRIBBLE, attacking, zone, runner.id)
		ball_zone = T.attacking_box(attacking)
		return
	if rng.randf() < 0.5:
		_emit(T.EventType.DRIBBLE_TACKLED, attacking, zone, runner.id, marker.id)
		_emit(T.EventType.TACKLE, defending, zone, marker.id)
		if _maybe_foul(defending, marker, runner, zone):
			possession = attacking
			ball_zone = zone
			return
	else:
		_emit(T.EventType.CLEARANCE, defending, zone, marker.id)
	if rng.randf() < config.corner_after_failed_attack:
		_emit(T.EventType.CORNER, attacking, zone)
		if rng.randf() < config.corner_reaches_box:
			ball_zone = T.attacking_box(attacking)
			return
	possession = defending
	ball_zone = T.Zone.MIDFIELD


func _resolve_shot(attacking: int) -> void:
	var defending := T.opposite(attacking)
	var zone := T.attacking_box(attacking)
	if rng.randf() < config.box_foul_rate and _resolve_box_foul(attacking, defending, zone):
		return

	var shooter := _pick(attacking, T.Position.FORWARD if rng.randf() < 0.8 else T.Position.MIDFIELDER)
	var assister := _pick(attacking, T.Position.MIDFIELDER)
	var keeper := _pick(defending, T.Position.GOALKEEPER)
	var shot := _skill(shooter, shooter.shooting * 0.6 + shooter.composure * 0.4) \
		* _style(attacking, Shared.StylePhase.ATTACK) * _venue(attacking)
	var save := _skill(keeper, keeper.goalkeeping) \
		* _style(defending, Shared.StylePhase.DEFENSE) * _venue(defending)

	var on_target := clampf(config.shot_on_target_base + (shot - 50.0) / 220.0, 0.15, 0.85)
	if rng.randf() >= on_target:
		_resolve_miss(attacking, defending, zone, shooter)
		return

	var conversion := clampf(config.goal_conversion_base + (shot - save) / 170.0, 0.08, 0.65)
	if rng.randf() < conversion:
		_score_goal(attacking, shooter, assister, zone, false)
		possession = defending
		ball_zone = T.Zone.MIDFIELD
		return
	_emit(T.EventType.SHOT_SAVED, attacking, zone, shooter.id)
	if rng.randf() < config.save_to_corner_share:
		_emit(T.EventType.CORNER, attacking, zone)
		ball_zone = zone
		return
	_emit(T.EventType.GOAL_KICK, defending, zone)
	possession = defending
	ball_zone = T.own_third(defending)


func _resolve_miss(attacking: int, defending: int, zone: int, shooter: RefCounted) -> void:
	possession = defending
	if rng.randf() < config.shot_blocked_share:
		_emit(T.EventType.SHOT_BLOCKED, attacking, zone, shooter.id)
		ball_zone = T.Zone.MIDFIELD
		return
	_emit(T.EventType.SHOT_OFF_TARGET, attacking, zone, shooter.id)
	_emit(T.EventType.GOAL_KICK, defending, zone)
	ball_zone = T.own_third(defending)


## A foul on the shooter. Returns true when it ended the attack (a penalty);
## otherwise advantage is played and the shot goes on.
func _resolve_box_foul(attacking: int, defending: int, zone: int) -> bool:
	var fouler := _pick(defending, T.Position.DEFENDER)
	var fouled := _pick(attacking, T.Position.FORWARD)
	_emit(T.EventType.FOUL, defending, zone, fouler.id, fouled.id)
	_maybe_card(defending, fouler, zone)
	if rng.randf() >= config.penalty_share:
		return false
	_emit(T.EventType.PENALTY_AWARDED, attacking, zone)
	_resolve_penalty(attacking, zone)
	possession = defending
	ball_zone = T.Zone.MIDFIELD
	return true


func _resolve_penalty(attacking: int, zone: int) -> void:
	var taker := _best_shooter(attacking)
	var keeper := _pick(T.opposite(attacking), T.Position.GOALKEEPER)
	var conversion := clampf(config.penalty_conversion + (taker.shooting - keeper.goalkeeping) / 400.0, 0.5, 0.92)
	if rng.randf() < conversion:
		_score_goal(attacking, taker, null, zone, true)
	else:
		_emit(T.EventType.PENALTY_MISSED, attacking, zone, taker.id)


func _best_shooter(side: int) -> RefCounted:
	var best: RefCounted = null
	for player in _team(side).players:
		if sent_off.has(player.id) or player.position == T.Position.GOALKEEPER:
			continue
		if best == null or player.shooting > best.shooting:
			best = player
	return best if best != null else _pick(side, T.Position.FORWARD)


func _score_goal(side: int, scorer: RefCounted, assister: RefCounted, zone: int, is_penalty: bool) -> void:
	var assister_id: String = assister.id if assister != null else ""
	var event := _emit(T.EventType.GOAL, side, zone, scorer.id, assister_id)
	event.detail = {"penalty": is_penalty}
	score[side] += 1


# --- Fouls and cards ----------------------------------------------------------

## Rolls a foul after a tackle. The fouled side gets a free kick; the offender
## may be booked. Returns true when a foul was given.
func _maybe_foul(fouling_side: int, fouler: RefCounted, fouled: RefCounted, zone: int) -> bool:
	var chance: float = config.foul_base * (0.6 + fouler.aggression / 125.0)
	if rng.randf() >= chance:
		return false
	_emit(T.EventType.FOUL, fouling_side, zone, fouler.id, fouled.id)
	_emit(T.EventType.FREE_KICK, T.opposite(fouling_side), zone)
	_maybe_card(fouling_side, fouler, zone)
	return true


func _maybe_card(side: int, player: RefCounted, zone: int) -> void:
	var aggression_scale: float = 0.6 + player.aggression / 125.0
	if rng.randf() < config.red_base * aggression_scale:
		_send_off(side, player, zone)
		return
	# A player already on a yellow plays more carefully, which keeps second
	# yellows from piling up on the few players who do most of the tackling.
	var caution := 0.4 if yellows.has(player.id) else 1.0
	if rng.randf() >= config.yellow_base * aggression_scale * caution:
		return
	yellows[player.id] = int(yellows.get(player.id, 0)) + 1
	_emit(T.EventType.YELLOW_CARD, side, zone, player.id)
	# A second yellow is a sending-off.
	if yellows[player.id] >= 2:
		_send_off(side, player, zone)


func _send_off(side: int, player: RefCounted, zone: int) -> void:
	sent_off[player.id] = true
	_emit(T.EventType.RED_CARD, side, zone, player.id)


# --- Substitutions ------------------------------------------------------------

func _substitute(side: int, player_off_id: String, player_on_id: String) -> String:
	if phase == T.Phase.FINISHED:
		return "match_finished"
	if subs_made[side] >= config.max_subs:
		return "sub_limit_reached"
	var team := _team(side)
	var off_player: RefCounted = team.find_on_pitch(player_off_id)
	var on_player: RefCounted = team.find_on_bench(player_on_id)
	if off_player == null or sent_off.has(player_off_id):
		return "player_off_unavailable"
	if on_player == null or subbed_off.has(player_on_id):
		return "player_on_unavailable"
	team.players[team.players.find(off_player)] = on_player
	team.bench[team.bench.find(on_player)] = off_player
	subbed_off[off_player.id] = true
	_conditions[on_player.id] = on_player.condition
	subs_made[side] += 1
	_emit(T.EventType.SUBSTITUTION, side, ball_zone, off_player.id, on_player.id)
	return ""


# --- Helpers ------------------------------------------------------------------

func _team(side: int) -> RefCounted:
	return home if side == T.Side.HOME else away


## A random available player in `position`, falling back to any available
## outfielder (or anyone, for a goalkeeper) so a side with a red card or no
## keeper still plays on.
func _pick(side: int, position: int) -> RefCounted:
	var pool: Array = []
	for player in _team(side).players:
		if not sent_off.has(player.id) and player.position == position:
			pool.append(player)
	if pool.is_empty():
		for player in _team(side).players:
			if sent_off.has(player.id):
				continue
			if position == T.Position.GOALKEEPER or player.position != T.Position.GOALKEEPER:
				pool.append(player)
	if pool.is_empty():
		return MatchPlayer.nobody()
	return pool[rng.randi_range(0, pool.size() - 1)]


func _emit(type: int, side: int, zone: int, player_id := "", secondary_id := "") -> RefCounted:
	var event := MatchEvent.new(minute, type, side, zone)
	event.player_id = player_id
	event.secondary_id = secondary_id
	events.append(event)
	return event
