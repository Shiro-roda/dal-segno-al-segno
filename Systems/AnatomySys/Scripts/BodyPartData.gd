extends Resource
class_name BodyPartData

@export var part_name : String
@export var required_removed_mask : int = 0
@export var base_visible : bool = false
@export var damage_multiplier : float = 1.0
@export var is_cognitohazard : bool = false

## Part HP pool. 0 = no part HP (legacy behaviour, fully backward compatible).
## When > 0, hitting this part depletes its own HP pool in addition to main HP.
## When part HP reaches 0 the part is broken and removed from the targetable list.
@export var max_part_hp : int = 0

## Bit set in the actor's broken_parts_mask when this part breaks.
## Should match the bit used in required_removed_mask of parts it would unlock.
@export var break_mask_bit : int = 0

## Optional status applied to the actor when this part breaks.
@export var on_break_status   : String = ""
@export var on_break_duration : int    = 2

## Optional stat changes applied permanently (for the battle) when this part breaks.
## Negative values are debuffs, positive are buffs.
@export var on_break_sharp_delta : int = 0  # applied via modify_attack()
@export var on_break_flat_delta  : int = 0  # applied via modify_flat()

## Path to the reticle anchor Node3D on the actor, relative to the actor root.
## Leave empty to fall back to CameraAnchor.
## Swap the target node for a BoneAttachment3D child at any time — code is unchanged.
@export var anchor_path : NodePath = NodePath("")

## Runtime state — not @export so not saved to disk, but must be
## manually copied in duplicate_for_battle() since Resource.duplicate()
## only copies @export properties.
var current_part_hp : int = 0
var is_broken       : bool = false
var already_seen    : bool = false
var encased         : bool = false


func _init() -> void:
	current_part_hp = max_part_hp


## Returns a fresh copy with runtime state reset to initial values.
## Use this instead of duplicate() when starting a new battle.
func duplicate_for_battle() -> BodyPartData:
	var d := duplicate() as BodyPartData
	d.current_part_hp = max_part_hp
	d.is_broken       = false
	d.already_seen    = false
	d.encased         = false
	return d


func has_part_hp() -> bool:
	return max_part_hp > 0


func take_part_damage(amount: int) -> bool:
	## Deal damage to part HP. Returns true if this damage breaks the part.
	if not has_part_hp() or is_broken:
		return false
	current_part_hp = max(0, current_part_hp - amount)
	if current_part_hp <= 0:
		is_broken = true
		return true
	return false


func apply_status(effect_id: String, _duration: int = 0) -> void:
	if effect_id == "encased":
		encased = true


func clear_encased() -> void:
	encased = false
