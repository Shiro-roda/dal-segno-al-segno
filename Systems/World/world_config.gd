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

## Loot per kill is multiplied by (1 + this * steps from the exit). Greed lever.
@export var loot_distance_bonus := 0.25

## Cost multiplier for rebuilding a ruined village tile after a defeat.
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
