class_name DamageEvent
extends RefCounted
## One packet of damage moving through the pipeline. Mechanics may edit it.

var source: StatBlock           # null for condition ticks
var target: StatBlock
var action: ActionDef           # null for condition ticks
var amount: int = 0             # edit this to mitigate or amplify
var damage_type: StringName = &"physical"
var crit: bool = false
var cancelled: bool = false
var dealt: int = 0              # filled in after the target applies it
var notes: Array[String] = []   # short tags shown in the roll readout
