extends RefCounted
## Shared enums and side/zone helpers for the match engine.
##
## The pitch is five zones seen from a neutral viewpoint; HOME attacks towards
## AWAY_BOX and AWAY attacks towards HOME_BOX:
##   HOME_BOX | HOME_THIRD | MIDFIELD | AWAY_THIRD | AWAY_BOX

enum Side { HOME, AWAY }
enum Zone { HOME_BOX, HOME_THIRD, MIDFIELD, AWAY_THIRD, AWAY_BOX }
enum Position { GOALKEEPER, DEFENDER, MIDFIELDER, FORWARD }
## Order matters: match_shared.gd indexes its modifier table by these values.
enum PlayStyle { BALANCED, ATTACKING, DEFENSIVE, POSSESSION, COUNTER, HIGH_PRESS }
enum Phase { PRE_KICK_OFF, FIRST_HALF, HALF_TIME, SECOND_HALF, FINISHED }
enum EventType {
	KICK_OFF,
	PASS,
	PASS_INTERCEPTED,
	INTERCEPTION,
	TACKLE,
	DRIBBLE,
	DRIBBLE_TACKLED,
	CLEARANCE,
	SHOT_OFF_TARGET,
	SHOT_BLOCKED,
	SHOT_SAVED,
	GOAL,
	CORNER,
	GOAL_KICK,
	FOUL,
	FREE_KICK,
	YELLOW_CARD,
	RED_CARD,
	PENALTY_AWARDED,
	PENALTY_MISSED,
	SUBSTITUTION,
	HALF_TIME,
	FULL_TIME,
	## Appended last so stored event type ints stay valid.
	OFFSIDE,
}


static func opposite(side: int) -> int:
	return Side.AWAY if side == Side.HOME else Side.HOME


## The box a side shoots at.
static func attacking_box(side: int) -> int:
	return Zone.AWAY_BOX if side == Side.HOME else Zone.HOME_BOX


## The third in front of the opposing box.
static func attacking_third(side: int) -> int:
	return Zone.AWAY_THIRD if side == Side.HOME else Zone.HOME_THIRD


## The side's own defensive third, where it builds up from.
static func own_third(side: int) -> int:
	return Zone.HOME_THIRD if side == Side.HOME else Zone.AWAY_THIRD


static func own_box(side: int) -> int:
	return Zone.HOME_BOX if side == Side.HOME else Zone.AWAY_BOX
