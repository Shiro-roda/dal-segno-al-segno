extends Node
## SkillDirectory — single source of truth for all SkillData definitions.
## Autoload singleton. Actors call get_skill() / get_dict() by name.
##
## Skills with full SkillEffect chains can be data-driven (enemy skills, items).
## Player skills that need complex async logic stay in actor scripts and only
## store metadata here (summary, description, will_cost, etc.).

var _skills : Dictionary = {}   # skill_name → SkillData

func _ready() -> void:
	_register_all()


# ── Public API ─────────────────────────────────────────────────────────────────

func get_skill(sname: String) -> SkillData:
	return _skills.get(sname, null)


## Returns a Dictionary for battle_manager / UI consumption.
## `overrides` is merged on top (callers can patch ai_weight, anchor_path, etc.).
func get_dict(sname: String, overrides: Dictionary = {}) -> Dictionary:
	var sd : SkillData = get_skill(sname)
	var d  : Dictionary
	if sd:
		d = sd.to_dict()
	else:
		d = {"name": sname, "key": overrides.get("key", "attack"), "description": ""}
	d.merge(overrides, true)
	return d


# ── Registration ────────────────────────────────────────────────────────────────

func _register_all() -> void:

	# ── Kendall ────────────────────────────────────────────────────────────────
	_sd("Shoot", "attack", "Fire your equipped weapon at a single target.",
		"Blasphemous lethality lies in your hands. Take aim and dispel the fantasias that take refuge here.")

	_sd("Pistol Whip", "struggle", "Attack at random for a weak blow. 35% miss chance.",
		"Short of arms, yet not devoid of alternatives.")

	_sd("Unveil", "special", "Reveal weak points at the risk of uncovering memetic hazards.",
		"Strip away the pretenses of perception itself.\n\nUnderstand that the price of understanding may be more than you can afford.")

	_sd("Augur", "support", "Grants 50% dodge and +5 TEMPO to all allies. Reveals enemy stats.",
		"Portentious signs only you can see are all around you.", 0, 0, 1)

	_sd("Evade", "support", "Gain 50% dodge and +10 TEMPO for 2 turns.", "")

	# ── Hue ────────────────────────────────────────────────────────────────────
	_sd("Rebuke", "attack",
		"Hit all enemies for 100% SHARP. 45% chance to slow each target.",
		"Hue stymies the enemy with a chilling mist and admonishment.", 2, 0, 2)

	_sd("Cling", "struggle",
		"Latch onto a random enemy. 35% miss chance, 25% self-harm, 75% slow.",
		" ")

	_sd("Calcify", "special",
		"Encase one enemy in ice for 1–3 turns. They take 50% reduced damage while frozen.",
		"Hue buries the foe in a glacial tomb.", 3, 0, 3)

	_sd("Shelter", "support",
		"Grant an ally +8 temporary CORP and +4 FLAT while it holds.",
		"Hue shields a companion with a wall of ice.", 1, 0, 1)

	_sd("Embrace", "support",
		"Redirect attacks against target to Hue with 50% reduced damage, for 2 turns.",
		"")

	# ── Indra ──────────────────────────────────────────────────────────────────
	_sd("Crucify", "attack",
		"Attack for 100% SHARP. 50% chance to inflict Bleeding (10% max CORP/turn, 2 turns).",
		"The zealot lunges forth to assail the enemy.", 2, 0, 2)

	_sd("Clobber", "struggle",
		"Attack at random for 50% SHARP. 35% miss, 25% self-harm.",
		" ")

	_sd("Fulminate", "special",
		"Strike all enemies for 170% SHARP.",
		"The mountains quake before him, and the hills melt away.", 3, 0, 3)

	_sd("Galvanize", "support",
		"Grant +2 SHARP to allies, restore will, and give Kendall a free shot.",
		"Indra fills his comrades with electric pride.", 1, 0, 1)

	_sd("Martyr", "support",
		"Bleed self. Store incoming damage as bonus on next attack for 3 turns.",
		"")

	# ── Vritra ─────────────────────────────────────────────────────────────────
	_sd("Vice", "support",
		"Grant an ally 50% Lifesteal for 4 turns.",
		"Vritra envenoms their ally with worldly delights.", 1, 0, 1)

	_sd("Malice", "support",
		"Chosen ally counters every hit and restores Vritra 50% AP per counter.",
		"The serpent invites its fellows to writhe together in vitriol.", 2, 0, 2)

	_sd("Devour", "special",
		"Attack for 180% SHARP. Permanently gain +1 MAX CORP if the target dies.",
		"The serpent unfetters its yawning maw.", 3, 0, 3)

	_sd("Wither", "attack",
		"Attack for 100% SHARP. 60% chance to reduce target SHARP by 2.",
		"Vritra sharpens its tongue upon the enemy.", 2, 0, 2)

	_sd("Waste", "struggle",
		"Shed stored CORP from Devour kills to restore will and HP.",
		"")

	_sd("Autophagy", "struggle", " ", "")
	_sd("Anthropophagy", "special", " ", "")


# ── Helper ──────────────────────────────────────────────────────────────────────
## _sd: register a SkillData by name. Effects can be added after via get_skill().
func _sd(sname: String, key: String, summary: String, desc: String,
		will: int = 0, ammo: int = 0, ai: int = 1) -> void:
	var sd := SkillData.new()
	sd.skill_name   = sname
	sd.command_key  = key
	sd.summary      = summary
	sd.description  = desc
	sd.will_cost    = will
	sd.ammo_cost    = ammo
	sd.ai_weight    = ai
	_skills[sname]  = sd
