extends Resource
class_name MotifNode
## MotifNode — a single node in the Motif skill upgrade tree.
## Motifs are permanent cross-run upgrades unlocked with Motif Points.
## They are earned by encountering new content for the first time.
##
## Every Motif belongs to one character and modifies one of their skills.
## Shoot is excluded — Kendall's weapon upgrades live on GunData resources.

## Unique string identifier, e.g. "hue_rebuke_upgrade".
@export var motif_id       : String = ""

## Display name shown in the tree UI, e.g. "Glacial Rebuke".
@export var motif_name     : String = ""

## Which character this belongs to ("Kendall", "Hue", "Indra", "Vritra").
@export var character      : String = ""

## The base skill this modifies, e.g. "Rebuke".
@export var skill_name     : String = ""

## EXTENSION = builds on base skill / prior module mechanics.
## VARIATION  = alternative mechanic to base skill / prior module.
enum UpgradeType { EXTENSION, VARIATION }
@export var upgrade_type   : UpgradeType = UpgradeType.EXTENSION

## Short flavour/mechanical description shown in the node tooltip.
@export var description    : String = ""

## Motif Point cost to unlock.
@export var cost           : int    = 2

## IDs of nodes that must be unlocked before this one becomes available.
@export var requires       : Array[String] = []

## Runtime flag — set by MetaProgress, NOT exported/persisted here.
var unlocked : bool = false
