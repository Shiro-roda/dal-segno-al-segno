class_name WorldConfig
extends Resource
## Tuning for the day loop. Every number that shapes the greed-versus-survival
## tension lives here, so balance is edited in the Inspector, not in code.

@export_group("Resources")
## Resource ids for the three note colours, in red, green, blue order. Notes are the
## building material: dropped by enemies, kept between days, spent on room colours.
@export var note_ids: Array[StringName] = [&"red_notes", &"green_notes", &"blue_notes"]
## The resource hub tiles produce passively (list it under a tile's income). It buys
## items and upgrades, and it is one way to pay the tithe.
@export var cuts_id: StringName = &"cuts"
## Grey notes: the building material for roads (HexDayCycle only). Uncoloured (neutral)
## enemies drop them; you can also convert coloured notes into them, and back.
@export var grey_note_id: StringName = &"grey_notes"
## Converting is reversible: one grey note becomes this many notes of EACH colour (red,
## green and blue), and this many of each colour become one grey note.
@export_range(1, 10) var grey_exchange_rate := 1
## What the player has at the start of each run (resource id -> amount).
@export var starting_resources: Dictionary = {&"red_notes": 10, &"green_notes": 10, &"blue_notes": 10, &"grey_notes": 10}
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
@export var tithe_per_day := 0.5
## Unpaid tithe adds to a debt that makes enemies stronger.
@export var debt_per_level := 4

@export_group("Pressure")

## Enemy levels gained per day. Fractions accumulate: 0.5 means +1 every second day.
@export var level_per_day := 0.5
## Extra levels for a tile that still holds enemies you left alive yesterday.
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

@export_group("Board")
## Radius, in hexes, of the hex world (HexDayCycle only). 2 is the standard Catan board.
## A Civilization standard map is about 4,000 tiles, which is radius 36 here.
@export_range(1, 60) var board_radius := 4
## Ignore board_radius: the world is an endless plane of hexes, dealt from the seed as
## they are looked at.
@export var infinite_board := false
## Resource id -> amount spent to build one road (HexDayCycle only). Empty = free. One
## grey note by default; grey notes are made by converting coloured ones.
@export var road_cost: Dictionary = {&"grey_notes": 1}

@export_group("Dawn")
## How many times the dice are rolled at the start of each segment of the day (HexDayCycle
## only; a day has three segments). Each roll is 2d6, and every hex carrying that number
## wakes for that segment only. With one roll, about 7 in 10 rooms have nothing awake
## beside them in a given segment; the enemies they gather pile up across segments.
@export_range(1, 6) var wake_rolls_per_segment := 1
## A roll of 7 is rolled again. No hex carries a 7: it is kept for rival raids later.
@export var reroll_sevens := true
## Enemies gathered by a room with no awake hex beside it, per segment. 0 = it stays quiet.
@export_range(0, 20) var idle_spawn_count := 0
## A room gathers its spawn_count for each awake hex beside it. When picking each enemy,
## its chance is multiplied by this for every awake hex of the enemy's own colour.
@export_range(1.0, 20.0, 0.1) var terrain_affinity_multiplier := 4.0

@export_group("Blueprints")
## Dungeon tiles can only be placed from a blueprint offered today, on top of
## their notes cost. Village tiles never need one.
@export var require_blueprints := true
## Blueprints offered at the start of each planning phase. Unused ones expire.
@export var blueprints_per_day := 1
## A blueprint's draw weight is divided by (1 + this * copies already drawn today).
@export var blueprint_repeat_penalty := 1.0
## The standing blueprint adds one extra copy to every day's hand. Placing that copy
## costs this many times the usual notes (the tile's other costs are unchanged).
@export_range(1, 10) var extra_blueprint_cost_multiplier := 2

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

@export_group("Rest and hazards")
## Hit dice each character can spend per day in rest rooms: level times this. The pool
## is shared by every rest room and refills when the next day begins.
@export_range(0, 10) var hit_dice_per_level := 1
## The most bonus blueprints hazards can add to a single day's hand.
@export_range(0, 20) var hazard_bonus_cap := 3

@export_group("Raids")
## Master switch for raids (HexDayCycle only). Off: rooms hold any number of enemies and
## nothing roams.
@export var raids_enabled := false
## Roaming enemies are drawn at random from these. Empty = no raiders spawn, though full
## rooms can still leak their own enemies.
@export var raider_templates: Array[EnemyTemplate] = []
## Raiders that spawn at a structure for each awake hex beside it.
@export_range(0, 10) var raiders_per_wake := 1
## A dungeon room's size comes from its spawn count: it is medium at the first number and
## large at the second. Below the first it is small.
@export var room_size_thresholds: Array[int] = [3, 6]
## Per size (small, medium, large): how many road steps a room's safe zone reaches.
@export var cover_radius_by_size: Array[int] = [1, 2, 3]
## Per size: how many enemies a room can hold. Raiders gather in a covering room until it
## is full; anything beyond that roams (or leaks) and attacks structures.
@export var capacity_by_size: Array[int] = [4, 8, 14]
## Health lost by a structure for each raider left unopposed on it at the end of a segment.
@export_range(0, 100) var raid_damage_per_raider := 1
## Health every damaged structure regains when a new day begins.
@export_range(0, 100) var raid_repair_per_day := 2
## Longest an off-screen fight between allies and raiders runs, in seconds of combat time.
## It is the real CombatSession, stepped without bodies or any presentation. A fight
## still going at the limit is left as it stands.
@export_range(5.0, 600.0, 1.0) var raid_fight_seconds := 120.0

@export_group("Exploration")
## HexDayCycle only. On: every vertex starts unexplored. Nothing can be built on, or road
## laid to, a vertex the party has not explored, and the hexes around a vertex only show
## once it is explored. Off: the board is as visible as the hex fog makes it.
@export var explore_vertices := false
## Road steps, from the vertex the party stands on, that are explored as it arrives. 0 =
## only the vertex itself.
@export_range(0, 5) var sight_radius := 0
## Vertices around the origin explored from the start of a run.
@export_range(0, 5) var start_explored_radius := 1

@export_group("Wild enemies")
## HexDayCycle only. On: enemies are scattered over the board at the start of a run. A
## vertex holding living wild enemies cannot be built on (nor roaded to) until they are
## cleared.
@export var wild_enemies_enabled := false
## Chance, per vertex, that a group of wild enemies is waiting there.
@export_range(0.0, 1.0, 0.005) var wild_density := 0.75
## Enemies in one wild group, picked between these two (inclusive).
@export_range(1, 20) var wild_group_min := 1
@export_range(1, 20) var wild_group_max := 3
## Vertices around the origin guaranteed free of wild enemies.
@export_range(0, 10) var wild_safe_radius := 2
## Wild groups are drawn at random from these.
@export var wild_templates: Array[EnemyTemplate] = []

@export_group("Party")
## Vertices the party can walk in one segment (HexDayCycle map movement). Refilled as each
## segment begins.
@export_range(1, 50) var party_moves_per_segment := 6
