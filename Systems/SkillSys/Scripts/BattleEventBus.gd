extends Node
## Global signal bus for reactive battle events.
## All condition hooks connect to / emit through this single signal.
## Nothing in actor code should need to reference this directly —
## ConditionRunner is the only caller.

## Fired synchronously. All registered hook callables run before resolve() commits.
## ctx is a BattleEventContext — mutate it freely inside listeners.
## ctx is always a BattleEventContext — typed as Object to avoid class-load ordering issues.
signal event(event_name: String, ctx: Object)
