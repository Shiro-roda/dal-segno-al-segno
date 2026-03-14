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
	_add("Shoot",       "attack", "Fire your equipped weapon at a single target.", "Blasphemous lethality lies in your hands. Take aim and dispel the fantasias that take refuge here.")
	_add("Pistol Whip", "attack", "Attack at random for half damage. Has a chance to miss.", "Short of arms, yet not devoid of alternatives.", false, true)
	_add("Change Lens", "special", "Reveal weak points at the risk of uncovering memetic hazards.", "Strip away the layers of perception itself to expose your foe's most intimate and fragile disfigurements.\nUnderstand that the price of understanding may be more than you can afford.")
	_add("Augur",       "support", "Grants dodge chance and heightened tempo to all allies. Also reveals enemy specifications.", "Portentious signs only you can see are all around you, and your companions may benefit from your discernment.", true)
	_add("Evade",       "support", "Increase your tempo and dodge chance for a short time.", "", true)

	# Hue
	_add("Rebuke",  "attack", "Attack all enemies, with a chance to slow each one.", "Hue stymies the enemy with a chilling mist and admonishment.", true)
	_add("Cling",   "attack", "Attack at random for half damage. Has a chance to miss. Also has a chance to slow the enemy",  " ", false, true)
	_add("Calcify", "special", " ", "Hue buries the foe in a glacial tomb, leaving them unable to act but guarded from harm.")
	_add("Shelter", "support", "Grants temporary Corpus Portions.", "Hue shields a companion with a wall of ice.", false, false, true)
	_add("Embrace", "support", " ", "", false, false, true)

	# Indra
	_add("Crucify",   "attack", "Has a chance to perforate the target's flesh, spilling their ichor for two turns.",  "The zealot lunges forth to assail the enemy with a nail-adorned baton.")
	_add("Clobber",   "attack", "Attack at random for half damage. Has a chance to miss.",  " ", false, true)
	_add("Fulminate", "special", "Deals slightly increased damage to all enemies.", "The mountains quake before him, and the hills melt away.", true)
	_add("Galvanize", "support", "Restores Anima Portions to both companions and raises all allies' attack. Also grants you an additional Beat Bullet.", "Indra fills his comrades with the electric pride of leading the charge, restoring their will to fight and invigorating their attacks.", true)
	_add("Martyr",    "support", " ", "", true)

	# Vritra
	_add("Vice",        "support", " ",  "Vritra envenoms the ally with worldly delights. Transmutates the enemy's flesh into ambrosia, restoring vitality to allies who feast upon them.", false, false, true)
	_add("Malice", "support", "Chosen ally enters a counter stance, restoring AP to Vritra when they retaliate.",  " ", false, true)
	_add("Devour",      "special", "Increases Vritra's Corpus Portions by 1 if the attack kills their target.", "The serpent unfetters its yawning maw, and swallows their banquet whole. Their corpse grows stronger if their prey is left without a trace.")
	_add("Wither",      "attack", "Steals CORP from the target and lowers their ATK.", "Vritra inflicts the enemy with unbearable famine, lessening their strength and siphoning their vitality.")
	_add("Waste",       "attack", " ", "", true)
	_add("Unwilling",   "special", " ", "", false, false, true)


func _add(sname: String, key: String = "attack", summary: String = "", desc: String = "",
	aoe: bool = false, struggle: bool = false, ally: bool = false, enemy: bool = false) -> void:

	var sd := SkillData.new()
	sd.skill_name   = sname
	sd.command_key  = key
	sd.summary      = summary
	sd.description  = desc
	sd.is_aoe       = aoe
	sd.is_struggle  = struggle
	sd.ally_target  = ally
	sd.enemy_target = enemy
	_skills[sname]  = sd
