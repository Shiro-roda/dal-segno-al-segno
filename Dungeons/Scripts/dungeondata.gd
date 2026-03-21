extends Resource
class_name DungeonData


@export var default_battle_track : BattleTrack
@export var dungeon_track : BattleTrack  # ambient music played while exploring
@export var rooms : Array[RoomData]
@export var start_room : RoomData
@export var recruit_room : RoomData  # pre-placed adjacent to start; omit to skip
# @export var base_field_effects : Array[FieldEffectData]
# @export var lens_rules : LensRuleData
# @export var dungeon_modifiers : Array[ModifierData]
