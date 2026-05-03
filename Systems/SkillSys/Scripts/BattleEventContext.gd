extends RefCounted
class_name BattleEventContext
## Mutable payload passed through BattleEventBus.event.
## Hooks read and write these fields to redirect, cancel, or reshape events
## before ConditionRunner commits them.

## Actor that caused the event (attacker, healer, caster, etc.).
var source : BattleActor = null
## Actor the event is directed at. Hooks may redirect this (e.g. Cover).
var target : BattleActor = null
## Primary numeric value — damage dealt, HP restored, etc. Float so formulas
## can do fractional math; ConditionRunner casts to int on commit.
var value  : float = 0.0
## Semantic tags for filtering. e.g. ["physical"], ["bleed_tick"], ["counter"].
var tags   : Array[String] = []
## If set to true by any hook, ConditionRunner skips the commit step entirely.
var cancelled : bool = false
## Open dictionary for hooks that need to stash extra data (e.g. Cover's will ratio).
var extra  : Dictionary = {}
