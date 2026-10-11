class_name ShopOffer
extends Resource
## One thing a shop can sell. Listed on ShopDef.offers.

@export var item: ItemDef
## Resource id -> amount, paid from the run's stock (for example {&"cuts": 6}). An offer
## with an empty price is never stocked.
@export var price: Dictionary = {}
## Relative chance of being picked when the shop restocks. 0 = never.
@export_range(0.0, 100.0, 0.1) var weight := 1.0
## Not stocked before this day of a run.
@export var min_day := 1
## How many can be bought per day once stocked.
@export_range(1, 99) var copies := 1
