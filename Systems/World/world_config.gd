class_name WorldConfig
extends Resource
## Tuning for the day loop. Every number that shapes the greed-versus-survival
## tension lives here, so balance is edited in the Inspector, not in code.

@export_group("Resources")
## Resource ids for the three note colours, in red, green, blue order. Notes are the
## building material: dropped by remnants, kept between days, spent on room colours.
@export var note_ids: Array[StringName] = [&"red_notes", &"green_notes", &"blue_notes"]
## The resource hub tiles produce passively (list it under a tile's income). It buys
## items and upgrades, and it is one way to pay the tithe.
@export var cuts_id: StringName = &"cuts"
## What the player has at the start of each run (resource id -> amount).
@export var starting_resources: Dictionary = {&"red_notes": 10, &"green_notes": 10, &"blue_notes": 10}
## Colour points per note. A room's colour divided by this is its note cost, and each
## note dropped in a room raises its matching colour channel by this much.
@export var color_per_note := 10
## Colour points a room gains for each note looted in it. Deliberately separate from
## color_per_note (which prices rooms): a room that cost 14 red notes to place only
## shifts one point of red for each red note taken out of it.
@export var color_gain_per_note := 1

@export_group("Tithe")
## What the tithe is paid with, first to last. Each unit of tithe is one of any of these.
@export var tithe_order: Array[StringName] = [&"cuts", &"red_notes", &"green_notes", &"blue_notes"]
## Tithe due at the start of day N is tithe_base + tithe_per_day * (N - 1).
@export var tithe_base := 0
@export var tithe_per_day := 1
## Unpaid tithe adds to a debt that makes remnants stronger.
@export var debt_per_level := 4

@export_group("Pressure")

## Enemy levels gained per day. Fractions accumulate: 0.5 means +1 every second day.
@export var level_per_day := 0.5
## Extra levels for a tile that still holds remnants you left alive yesterday.
@export var carried_level_bonus := 1

@export_group("Segno and main path")
## A day cannot start until the Segno (the party's spawn on the Bass Clef) is placed on a
## standing tile that connects to the exit. Off: the party spawns at the exit instead
## and nothing is scored.
@export var require_segno := true
## The main path is the longest walk from the Segno to the exit. Loot from encounter
## rooms ON it is multiplied by 1 + (this * its length in steps - loop_penalty * loops).
## Greed lever: a long spine pays, and is a longer walk back to safety.
@export var main_path_bonus_per_step := 0.25
## Subtracted from that bonus for every loop where the layout rejoins the main path.
@export var loop_penalty := 0.25
## Loot multiplier for rooms with no walking route to the Segno along standing tiles.
@export_range(0.0, 1.0) var disconnected_loot_multiplier := 0.5
## Search budget for the longest-path search, so a huge dungeon cannot stall planning.
## If it runs out, the best path found so far is used.
@export var main_path_search_limit := 200000

@export_group("Ruins")
## Cost multiplier for rebuilding a ruined Treble Clef tile after a defeat.
@export_range(0.0, 1.0) var ruin_discount := 0.5

@export_group("Blueprints")
## Dungeon tiles can only be placed from a blueprint offered today, on top of
## their notes cost. Village tiles never need one.
@export var require_blueprints := true
## Blueprints offered at the start of each planning phase. Unused ones expire.
@export var blueprints_per_day := 3
## A blueprint's draw weight is divided by (1 + this * copies already drawn today).
@export var blueprint_repeat_penalty := 1.0

@export_group("Recovery")
## Restore the party's Corpus and Anima when they return to the exit.
@export var rest_on_return := true

@export_group("Rooms")
## A dungeon room's enemies are picked at random; ones of the room's lowest colour(s)
## have their chance multiplied by this. 1 = colour has no effect.
@export_range(1.0, 20.0, 0.1) var affinity_multiplier := 4.0
## Allow erasing any tile while planning. Off: only a spent room (every channel at
## 250) can be erased.
@export var erase_any_tile := false
