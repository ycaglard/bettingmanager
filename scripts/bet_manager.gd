extends Node
## Global betting state (autoload "BetManager"): wallet, bet slip and placed bets.
## The slip holds at most one selection per match; several matches form a parlay.

signal slip_changed
signal bets_changed
signal bet_placed(bet: Dictionary)
signal balance_changed(balance: float)

const BetSettlement = preload("res://scripts/bet_settlement.gd")
const CURRENCY := "€"
const STARTING_BALANCE := 1000.0
const MIN_STAKE := 1.0

var balance := STARTING_BALANCE
## match_id -> leg Dictionary (see _make_leg).
var slip: Dictionary = {}
## Placed bets, newest first.
var bets: Array[Dictionary] = []

var _next_bet_number := 1


func _ready() -> void:
	MatchDirector.match_finished.connect(_on_match_finished)


## Grades every open leg on the finished match; a bet pays out once all its legs
## are graded, or loses as soon as one leg loses.
func _on_match_finished(match_id: String, result: Dictionary) -> void:
	var changed := false
	for bet in open_bets():
		for leg in bet.legs:
			if leg.match_id == match_id and not leg.has("outcome"):
				leg["outcome"] = BetSettlement.leg_outcome(leg.market_id, leg.selection_id, result)
				changed = true
		_try_settle(bet)
	if changed:
		bets_changed.emit()


func _try_settle(bet: Dictionary) -> void:
	var outcomes: Array = []
	var odds: Array = []
	for leg in bet.legs:
		outcomes.append(leg.get("outcome", ""))
		odds.append(leg.odds)
	var lost: bool = BetSettlement.LOST in outcomes
	if not lost and "" in outcomes:
		return
	var settled := BetSettlement.settle(bet.stake, outcomes.map(func(o): return o if o != "" else BetSettlement.VOID), odds)
	bet["status"] = settled.status
	bet["payout"] = settled.payout
	if settled.payout > 0.0:
		balance = snappedf(balance + settled.payout, 0.01)
		balance_changed.emit(balance)


static func is_bettable(match_data: Dictionary) -> bool:
	return match_data.get("status", "") == "NS"


static func format_money(amount: float) -> String:
	var whole := int(floor(absf(amount)))
	var cents := int(round((absf(amount) - whole) * 100.0))
	if cents == 100:
		whole += 1
		cents = 0
	var digits := str(whole)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return "%s%s%s%s.%02d" % ["-" if amount < 0 else "", CURRENCY, digits, grouped, cents]


func get_slip_leg(match_id: String) -> Dictionary:
	return slip.get(match_id, {})


func is_in_slip(match_id: String, market_id: String, selection_id: String) -> bool:
	var leg := get_slip_leg(match_id)
	return not leg.is_empty() and leg.market_id == market_id and leg.selection_id == selection_id


## Adds a selection, replacing any other selection from the same match.
func add_to_slip(match_data: Dictionary, market: Dictionary, selection: Dictionary) -> bool:
	if not is_bettable(match_data):
		return false
	slip[match_data.id] = _make_leg(match_data, market, selection)
	slip_changed.emit()
	return true


func toggle_selection(match_data: Dictionary, market: Dictionary, selection: Dictionary) -> void:
	if is_in_slip(match_data.id, market.id, selection.id):
		remove_from_slip(match_data.id)
	else:
		add_to_slip(match_data, market, selection)


func remove_from_slip(match_id: String) -> void:
	if slip.erase(match_id):
		slip_changed.emit()


func clear_slip() -> void:
	if not slip.is_empty():
		slip.clear()
		slip_changed.emit()


func slip_total_odds() -> float:
	var total := 1.0
	for leg in slip.values():
		total *= float(leg.odds)
	return snappedf(total, 0.01) if not slip.is_empty() else 0.0


## Returns an error message, or an empty string when the slip can be placed.
func validate_stake(stake: float) -> String:
	if slip.is_empty():
		return "Add a selection to your slip."
	if stake < MIN_STAKE:
		return "Minimum stake is %s." % format_money(MIN_STAKE)
	if stake > balance + 0.0001:
		return "Insufficient balance."
	return ""


## Places the current slip as a single (1 leg) or parlay (2+ legs).
## Returns the created bet, or an empty Dictionary if validation failed.
func place_bet(stake: float, placed_on: String) -> Dictionary:
	stake = snappedf(stake, 0.01)
	if not validate_stake(stake).is_empty():
		return {}
	var legs: Array = slip.values().duplicate(true)
	var total_odds := slip_total_odds()
	var bet := {
		"id": "B%05d" % _next_bet_number,
		"type": "single" if legs.size() == 1 else "parlay",
		"placed_on": placed_on,
		"stake": stake,
		"total_odds": total_odds,
		"potential_return": snappedf(stake * total_odds, 0.01),
		"status": "open",
		"legs": legs,
	}
	_next_bet_number += 1
	bets.push_front(bet)
	balance = snappedf(balance - stake, 0.01)
	slip.clear()
	balance_changed.emit(balance)
	slip_changed.emit()
	bets_changed.emit()
	bet_placed.emit(bet)
	return bet


func open_bets() -> Array:
	return bets.filter(func(b): return b.status == "open")


func _make_leg(match_data: Dictionary, market: Dictionary, selection: Dictionary) -> Dictionary:
	return {
		"match_id": match_data.id,
		"home": match_data.home,
		"away": match_data.away,
		"date": match_data.get("date", ""),
		"kickoff": match_data.get("kickoff", ""),
		"market_id": market.id,
		"market_name": market.name,
		"selection_id": selection.id,
		"selection_name": selection.name,
		"odds": float(selection.odds),
	}
