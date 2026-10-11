class_name ShopDef
extends Resource
## Marks a Town (Treble Clef) tile as a shop. Set it on TileDef.shop.
##
## Every dawn, and when the tile is first built, the shop picks `slots` different offers
## at random (weighted, skipping any not yet available on the current day). Stock is
## per tile, so two shops of the same kind roll separately. Ruined shops sell nothing.
## Bought items go into the party's shared bag.

@export var offers: Array[ShopOffer] = []
## Different offers on the shelves at once.
@export_range(1, 12) var slots := 3
## Text on the interact prompt.
## [Write the interact prompt for opening this shop.]
@export var prompt := ""
