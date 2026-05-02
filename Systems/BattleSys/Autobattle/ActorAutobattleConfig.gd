extends Resource
class_name ActorAutobattleConfig
## Per-actor autobattle configuration resource.
##
## Attach one of these to a CharacterData (or assign at runtime via
## BattleSettings.set_actor_autobattle_config) to give that actor
## a personal autobattle script.
##
## ── Enrollment ───────────────────────────────────────────────────────────────
##   enabled = false  → actor always waits for player input (default)
##   enabled = true   → actor uses the AI_SCRIPT strategy each turn
##
## ── Rule evaluation order ────────────────────────────────────────────────────
##   Rules are checked top-to-bottom.  First passing rule fires.
##   Add an unconditional rule at the bottom as the default action.
##
## ── Fallback chain ───────────────────────────────────────────────────────────
##   1. First matching rule in `rules`
##   2. REPEAT_LAST (if a previous action exists and is still valid)
##   3. Player input

## Whether this actor is enrolled in autobattle.
@export var enabled : bool = false

## Ordered list of conditional rules.
@export var rules : Array[AutobattleRule] = []

## When true and no rule matches, fall back to repeating the last action.
## When false, fall back to player input immediately.
@export var fallback_repeat_last : bool = true
