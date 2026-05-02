extends Resource
class_name AutobattleCondition
## A single evaluable condition used inside an AutobattleRule.
##
## Each condition tests a property of a battle subject against a threshold
## using one of several comparison operators.  Multiple conditions inside a
## rule are AND-ed together.
##
## ── Subject ──────────────────────────────────────────────────────────────────
##   SELF      — the actor executing the rule
##   ANY_ENEMY — true if ANY living enemy satisfies the condition
##   ALL_ENEMY — true if ALL living enemies satisfy the condition
##   ANY_ALLY  — true if ANY living ally (other than self) satisfies it
##   ALL_ALLY  — true if ALL living allies (other than self) satisfy it
##
## ── Property ─────────────────────────────────────────────────────────────────
##   HP_PCT          — current hp / max_hp  (0.0–1.0)
##   HP_ABS          — current hp (integer)
##   HAS_STATUS      — 1.0 if actor has status_id, 0.0 otherwise
##   MISSING_STATUS  — 1.0 if actor does NOT have status_id, 0.0 otherwise
##   ATTACK_MOD      — current attack_modifier (signed int)
##   FLAT_MOD        — current flat_modifier (signed int)
##   TEMPO_PCT       — tempo_pool / 100  (0.0–1.0)
##   ALLY_COUNT      — number of living allies (non-self players)
##   ENEMY_COUNT     — number of living enemies
##   TURN_NUMBER     — current battle turn count (read from manager)
##
## ── Operator ─────────────────────────────────────────────────────────────────
##   LT / LTE / EQ / GTE / GT

enum Subject {
	SELF,
	ANY_ENEMY,
	ALL_ENEMY,
	ANY_ALLY,
	ALL_ALLY,
}

enum Property {
	HP_PCT,
	HP_ABS,
	HAS_STATUS,
	MISSING_STATUS,
	ATTACK_MOD,
	FLAT_MOD,
	TEMPO_PCT,
	ALLY_COUNT,
	ENEMY_COUNT,
	TURN_NUMBER,
}

enum Operator { LT, LTE, EQ, GTE, GT }

@export var subject  : Subject  = Subject.SELF
@export var property : Property = Property.HP_PCT
@export var op       : Operator = Operator.LTE
## Numeric threshold. For boolean properties (HAS_STATUS, MISSING_STATUS) use 1.0.
@export var value    : float    = 0.5
## Status ID string — only used when property is HAS_STATUS or MISSING_STATUS.
@export var status_id : String  = ""

## Human-readable label for the editor / UI.  Auto-generated if left empty.
@export var label : String = ""

func get_label() -> String:
	if label != "":
		return label
	var subj_str: String = Subject.keys()[subject]
	var prop_str: String = Property.keys()[property]
	var op_str: String = ["<", "<=", "==", ">=", ">"][op]
	var val_str  := status_id if property in [Property.HAS_STATUS, Property.MISSING_STATUS] else str(value)
	return "%s.%s %s %s" % [subj_str, prop_str, op_str, val_str]
