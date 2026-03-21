extends Resource
class_name BattleContext


@export var encounter : EncounterData
@export var dungeon : DungeonData
@export var run_state : RunState
## The live dungeon run state — used to check phase (al segno, al fine, etc.).
## Null during the tutorial or out-of-dungeon battles.
var dungeon_run_state : DungeonRunState = null
