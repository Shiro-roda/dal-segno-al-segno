extends Resource
class_name ConditionSignalHook
## One reactive wire inside a ConditionData.
## Describes what event to listen for, an optional guard, the formula to run,
## and an optional follow-up event to emit.

## Signal name on BattleEventBus this hook subscribes to (e.g. "damage", "heal").
@export var listen_for : String = ""

## Optional guard expression. Evaluated with a=holder, src=source (applier), ctx=BattleEventContext.
## Hook body only runs when this returns true (or when guard is empty).
## Example: "ctx.target == a"  →  only intercept events targeting the holder.
@export var guard : String = ""

## Main formula. Runs with: a=holder, src=source (applier), ctx=BattleEventContext.
## May mutate ctx freely (ctx.value, ctx.target, ctx.cancelled, ctx.extra).
## May call ConditionRunner helpers via CR: CR.resolve(), CR.ctx_new(), CR.apply(), CR.remove().
@export var formula : String = ""

## Optional signal name to fire on BattleEventBus after formula completes.
## Leave empty to fire nothing.
@export var then_emit : String = ""

## Optional formula that builds and returns the BattleEventContext for then_emit.
## Evaluated with the same bindings as formula. If empty, the (possibly mutated)
## incoming ctx is reused as-is.
@export var emit_ctx_transform : String = ""
