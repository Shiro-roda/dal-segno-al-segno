extends Node
# SkillDirectory - single source of truth for all skill definitions.
# Autoload singleton: SkillDirectory.get_skill("Shoot") -> SkillData
# Actors call get_dict(name) to get the Dictionary battle_manager expects.

var _skills : Dictionary = {}

func _ready() -> void:
	_register_all()


# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

func get_skill(sname: String) -> SkillData:
	return _skills.get(sname, null)

func get_dict(sname: String, overrides: Dictionary = {}) -> Dictionary:
	var sd : SkillData = get_skill(sname)
	var d  : Dictionary
	if sd:
		d = sd.to_dict()
	else:
		d = {"name": sname, "key": overrides.get("key", "attack"), "description": ""}
	d.merge(overrides, true)
	return d


# ------------------------------------------------------------------------------
# Registration  (_add signature: sname, key, desc, aoe, struggle, ally, enemy)
# ------------------------------------------------------------------------------

func _register_all() -> void:
	# Kendall
	_add("Shoot",       "attack",  "Fire your equipped weapon at a single target for 100% SHARP.",                       "Blasphemous lethality lies in your hands. Take aim and dispel the fantasias that take refuge here.",
		false, false, false, false, "PartAnchors/Gun", "Pistol Whip")
	_add("Pistol Whip", "attack",  "Attack at random for 50% SHARP. Has a 35% chance to miss.",              "Short of arms, yet not devoid of alternatives.",
		false, true,  false, false, "PartAnchors/Gun")
	_add("Unveil", "special", "Reveal weak points at the risk of uncovering memetic hazards.",        "Strip away the pretenses of perception itself to expose your foe's most intimate and fragile disfigurements.\n\nUnderstand that the price of understanding may be more than you can afford.",
		false, false, false, false, "PartAnchors/Eyes")
	_add("Augur",       "support", "Grants 50% dodge chance for 4 turns and + 5 TEMPO to all allies. Also reveals enemy specifications.", "Portentious signs only you can see are all around you, and your companions may benefit from your discernment.",
		true,  false, false, false, "PartAnchors/Oracle")
	_add("Evade",       "support", "Gain a 50% dodge chance and + 10 TEMPO for 2 turns.",               "",
		true,  false, false, false, "PartAnchors/Oracle")

	# Hue
	_add("Rebuke",  "attack",  "Attack all enemies for 100% SHARP, with a chance to reduce their TEMPO stats to 40%.",                  "Hue stymies the enemy with a chilling mist and admonishment.",
		true,  false, false, false, "PartAnchors/Rebuke", "Cling", 2)
	_add("Cling",   "attack",  "Attack at random for 50% SHARP. Has a 35% chance to miss, and a 25% chance to harm Hue. Also has a 75% chance to slow the enemy to 40% TEMPO for one turn.", " ",
		false, true,  false, false, "PartAnchors/Rebuke")
	_add("Calcify", "special", "Paralyze the enemy for 1-3 turns, but reduce all damage to them by 50% until their next action.",                                                                    "Hue buries the foe in a glacial tomb, leaving them unable to act but guarded from harm.",
		false, false, false, false, "PartAnchors/Umbrella", "", 3)
	_add("Shelter", "support", "Grants 10 temporary CORP and increases the target's FLAT by 4 while the temporary CORP remains.",                                     "Hue shields a companion with a wall of ice.",
		false, false, true,  false, "PartAnchors/Canopy", "Embrace", 1)
	_add("Embrace", "support", "Redirect attacks against the target to Hue with 50% reduced damage, for 2 turns.",                                                                    "",
		false, false, true,  false, "PartAnchors/Canopy")

	# Indra
	_add("Crucify",   "attack",  "Attack the enemy for 100% SHARP. Has a 50% chance to bleed the enemy for 10% of their MAX CORP for 2 turns.", "The zealot lunges forth to assail the enemy with hammer and nail, perforating their flesh and spilling their ichor.",
		false, false, false, false, "PartAnchors/Hammer", "Clobber", 2)
	_add("Clobber",   "attack",  "Attack at random for 50% SHARP. Has a 35% chance to miss, and a 25% chance to harm Indra.",              " ",
		false, true,  false, false, "PartAnchors/Hammer")
	_add("Fulminate", "special", "Attack all enemies for 170% SHARP.",                      "The mountains quake before him, and the hills melt away.",
		true,  false, false, false, "PartAnchors/Storm", "", 3)
	_add("Galvanize", "support", "Grants + 2 SHARP to all allies and 2 AP to both companions. Also grants you an additional BB.", "Indra fills his comrades with the electric pride of leading the charge, restoring their will to fight and invigorating their attacks.",
		true,  false, false, false, "PartAnchors/Nails", "", 1)
	_add("Martyr",    "support", "Bleeds Indra for 10% MAX CORP and stores all damage done to him to add to his next attack for 3 turns.",                                                                   "",
		true,  false, false, false, "PartAnchors/Nails")

	# Vritra
	_add("Vice",      "support", "Grants an ally 50% lifesteal.",                                                                   "Vritra envenoms their ally with worldly delights.",
		false, false, true,  false, "PartAnchors/Snakes", "Malice", 1)
	_add("Malice",    "support", "Chosen ally enters a counter stance, restoring 50% of their attack's damage as AP to Vritra when they retaliate.", "The serpent invites its fellows to writhe together in vitriol.",
		false, true,  true, false, "PartAnchors/Snakes",)
	_add("Devour",    "special", "Attack for 180% SHARP. Siphons CORP from the target and increases Vritra's MAX CORP by 1 if the attack kills their target.", "The serpent unfetters its yawning maw, and swallows their banquet whole. Their proliferant corpse grows stronger if their prey is left without a trace.",
		false, false, false, false, "PartAnchors/Stomach", "", 3)
	_add("Wither",    "attack",  "Attack for 100% SHARP. Has a 60% chance to lower the target's SHARP by 2.",                  "Vritra sharpens its tongue upon the enemy, addling the mind and bringing strength to rot.",
		false, false, false, false, "PartAnchors/Mouth", "Waste", 2)
	_add("Autophagy",     "attack",  " ",                                                                   "",
		false,  true, false, false, "PartAnchors/Mouth")
	_add("Anthropophagy", "special", " ",                                                                   "",
		false, true, true,  false, "PartAnchors/Stomach")


func _add(sname: String, key: String = "attack", summary: String = "", desc: String = "",
	aoe: bool = false, struggle: bool = false, ally: bool = false, enemy: bool = false,
	anchor: String = "", struggle_alt: String = "",
	will_cost: int = 0, ammo_cost: int = 0) -> void:

	var sd := SkillData.new()
	sd.skill_name   = sname
	sd.command_key  = key
	sd.summary      = summary
	sd.description  = desc
	sd.is_aoe       = aoe
	sd.is_struggle  = struggle
	sd.ally_target  = ally
	sd.enemy_target = enemy
	sd.will_cost    = will_cost
	sd.ammo_cost    = ammo_cost
	if anchor != "":
		sd.anchor_path = NodePath(anchor)
	if struggle_alt != "":
		sd.struggle_name = struggle_alt
	_skills[sname]  = sd
