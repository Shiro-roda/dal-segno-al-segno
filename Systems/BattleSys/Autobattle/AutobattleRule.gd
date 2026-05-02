extends Resource
class_name AutobattleRule
## One rule in an actor's autobattle script.
##
## Rules are evaluated top-to-bottom in the actor's AutobattleConfig priority
## list.  The first rule whose ALL conditions pass fires its action.
## If no rule matches, the strategy falls back to REPEAT_LAST, then to player
## input if there is no last action to repeat.
##
## ── Action shape (mirrors BattleManager action dict) ─────────────────────────
##   command        : String  — skill key e.g. "attack", "special", "support"
##   target_mode    : TargetMode — how to pick the target
##   part_mode      : PartMode  — how to pick the body part
##   status_id      : String    — for TARGET_HAS_STATUS / TARGET_MISSING_STATUS
##
## ── Target modes ─────────────────────────────────────────────────────────────
##   LOWEST_HP_PCT  — enemy/ally with the lowest hp/max_hp ratio
##   HIGHEST_HP_PCT — enemy/ally with the highest hp/max_hp ratio
##   RANDOM         — random valid target
##   FIRST          — first in the target list (consistent, predictable)
##   HAS_STATUS     — first target that has status_id set on this rule
##   MISSING_STATUS — first target that does NOT have status_id
##   SELF           — self (support skills only)
##
## ── Part modes ────────────────────────────────────────────────────────────────
##   FIRST          — first visible, unbroken part
##   HIGHEST_MULT   — part with highest damage_multiplier
##   RANDOM         — random visible, unbroken part
##   NONE           — let the battle manager skip part selection (AoE / struggle)

enum TargetMode {
	LOWEST_HP_PCT,
	HIGHEST_HP_PCT,
	RANDOM,
	FIRST,
	HAS_STATUS,
	MISSING_STATUS,
	SELF,
}

enum PartMode {
	FIRST,
	HIGHEST_MULT,
	RANDOM,
	NONE,
}

## Human-readable name shown in the editor and any future visual scripting UI.
@export var rule_name : String = "New Rule"

## All conditions must pass for this rule to fire.
## An empty conditions array is always true (unconditional fallback).
@export var conditions : Array[AutobattleCondition] = []

## The skill key to execute when this rule fires.
@export var command : String = "attack"

## How to choose the skill's target.
@export var target_mode : TargetMode = TargetMode.LOWEST_HP_PCT

## Status ID used when target_mode is HAS_STATUS or MISSING_STATUS.
@export var target_status_id : String = ""

## How to choose the target's body part (if the skill needs one).
@export var part_mode : PartMode = PartMode.HIGHEST_MULT

## If true this rule is skipped during evaluation (quick disable without deleting).
@export var disabled : bool = false
