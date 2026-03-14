extends Resource
class_name DungeonRunState

var dungeon_data : DungeonData
var run_state : RunState

var grid : Dictionary = {} # Vector2i -> RoomInstance

var current_pos : Vector2i = Vector2i.ZERO
# Legacy position-only segno (kept for fallback compatibility)
var last_segno_pos : Vector2i = Vector2i(-999, -999)

# Full snapshot taken when a Segno consumable is placed.
# Null when no segno has been placed this run.
var segno_snapshot : Resource = null  # SegnoSnapshot
