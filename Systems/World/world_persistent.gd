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
