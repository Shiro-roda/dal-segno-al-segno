class_name WorldPersistent
extends RefCounted
## What survives a defeat. Everything on DayCycle is wiped each run; everything here is not.
## Kept deliberately small: it becomes the permanent half of the save file.

## Every tile id the player has ever built (for unlocking blueprints later).
var built_ids: Array[StringName] = []
var runs := 0
var best_day := 0
## Village tiles left standing when the last run ended: [{pos: Vector2i, def: TileDef}].
## They come back next run as ruins that are cheaper to rebuild.
var ruins: Array[Dictionary] = []
## Ids of every blueprint that has ever been drawn. Only these can be made the standing
## pick. Starts with the default pick so it is always available.
var seen_blueprints: Array[StringName] = [&"small_room"]
## The blueprint that gets one extra copy in every day's hand, at a higher note cost.
## Empty = none. Survives a defeat.
var standing_blueprint: StringName = &"small_room"
## Seed of the hex world's terrain (HexDayCycle only), so a run's ruins sit on the same
## board next time. -1 until the first run picks one.
var board_seed := -1
