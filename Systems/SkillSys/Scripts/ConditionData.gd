extends Resource
class_name ConditionData
## Data resource describing one battle condition (status effect).
## Instances live in res://Systems/SkillSys/Resources/Conditions/ as .tres files.
## All behaviour is expressed as GDScript formula strings evaluated by ConditionRunner.

## ── Identity ─────────────────────────────────────────────────────────────────

## Unique string key matching BattleActor STATUS_* constants. e.g. "bleeding".
@export var condition_id : String = ""
## Human-readable name for logs and HUD.
@export var display_name : String = ""

## ── Lifecycle formulas ────────────────────────────────────────────────────────
## All formulas are evaluated with: a=holder, t=ctx.target (if any), s=ctx.source (if any).
## ConditionRunner helpers available: resolve(name,ctx), ctx_new(src,tgt,val,tags), apply(), remove().

## Runs once when this condition is applied to an actor.
@export_multiline var on_apply_formula : String = ""
## Runs once when this condition is removed (duration expired or manually cleared).
@export_multiline var on_remove_formula : String = ""
## Runs each time the holder's tick_status_effects() fires (once per turn).
@export_multiline var on_tick_formula : String = ""

## ── Reactive hooks ────────────────────────────────────────────────────────────
## Each hook subscribes to one BattleEventBus signal and runs when that event fires.
## ConditionRunner connects/disconnects these automatically on apply/remove.
@export var signal_hooks : Array[ConditionSignalHook] = []

## ── Duration ─────────────────────────────────────────────────────────────────
## Default duration (in turns) when applied without an explicit override.
## 0 = permanent (must be removed explicitly, e.g. "encased").
@export var default_duration : int = 2
