extends Node
## MotifRegistry — authoritative definition of the Motif module tree.
## Unlock state lives in MetaProgress; only node definitions live here.
##
## Shoot is absent — Kendall's weapon progression lives on GunData.
## Covers: Kendall (non-Shoot), Hue, Indra, Vritra.

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

var _nodes : Dictionary = {}

func _ready() -> void:
	_register_all()


func get_node_by_id(id: String) -> MotifNode:
	return _nodes.get(id, null)


func get_all() -> Array:
	return _nodes.values()


func get_for_character(char_name: String) -> Array:
	return _nodes.values().filter(func(n): return n.character == char_name)


# ─────────────────────────────────────────────────────────────────────────────
# Registration
# ─────────────────────────────────────────────────────────────────────────────

func _register_all() -> void:

	# ── Kendall ───────────────────────────────────────────────────────────────
	# Augur line
	_add("kendall_augur_ext",
		"Extended Augur", "Kendall", "Augur", MotifNode.UpgradeType.EXTENSION,
		"Augur now grants each ally a dodge charge in addition to its tempo bonus. Enemy resistances are revealed for one turn.",
		2, [])
	_add("kendall_augur_var",
		"Clair-Obscur", "Kendall", "Augur", MotifNode.UpgradeType.VARIATION,
		"Augur targets only Kendall. Her tempo bonus is doubled and she gains a free shot this turn — allies receive nothing.",
		3, ["kendall_augur_ext"])

	# Unveil line
	_add("kendall_unveil_ext",
		"Extended Unveil", "Kendall", "Unveil", MotifNode.UpgradeType.EXTENSION,
		"Unveiled weak points persist for two turns instead of one. The memetic hazard chance is halved.",
		2, [])
	_add("kendall_unveil_var",
		"Occult Eye", "Kendall", "Unveil", MotifNode.UpgradeType.VARIATION,
		"Unveil no longer reveals hazards. Instead it guarantees the next Shoot strike hits a weak point, consuming the mark.",
		3, ["kendall_unveil_ext"])

	# Evade line
	_add("kendall_evade_ext",
		"Extended Evade", "Kendall", "Evade", MotifNode.UpgradeType.EXTENSION,
		"Evade grants two dodge charges instead of one.",
		2, [])

	# ── Hue ───────────────────────────────────────────────────────────────────
	# Rebuke line
	_add("hue_rebuke_ext",
		"Extended Rebuke", "Hue", "Rebuke", MotifNode.UpgradeType.EXTENSION,
		"Rebuke's slow chance is increased and it now also reduces the target's attack for one turn.",
		2, [])
	_add("hue_rebuke_var",
		"Hoarfrost", "Hue", "Rebuke", MotifNode.UpgradeType.VARIATION,
		"Rebuke becomes single-target. It deals 1.4x damage with a high slow chance, trading breadth for concentrated force.",
		3, ["hue_rebuke_ext"])

	# Calcify line
	_add("hue_calcify_ext",
		"Extended Calcify", "Hue", "Calcify", MotifNode.UpgradeType.EXTENSION,
		"Calcify's freeze lasts one additional turn. The frozen enemy's FLAT is reduced while entombed.",
		2, [])

	# Shelter line
	_add("hue_shelter_ext",
		"Extended Shelter", "Hue", "Shelter", MotifNode.UpgradeType.EXTENSION,
		"Shelter now covers the whole party instead of a single ally.",
		2, [])
	_add("hue_shelter_var",
		"Permafrost", "Hue", "Shelter", MotifNode.UpgradeType.VARIATION,
		"Shelter targets one ally only. That ally receives double FLAT for two turns and reflects the next hit entirely.",
		3, ["hue_shelter_ext"])

	# ── Indra ─────────────────────────────────────────────────────────────────
	# Crucify line
	_add("indra_crucify_ext",
		"Extended Crucify", "Indra", "Crucify", MotifNode.UpgradeType.EXTENSION,
		"Crucify's bleed chance is increased. Bleeding enemies take bonus damage on Indra's subsequent turns.",
		2, [])
	_add("indra_crucify_var",
		"Stigmata", "Indra", "Crucify", MotifNode.UpgradeType.VARIATION,
		"Crucify deals reduced up-front damage but spreads its bleed to all enemies when it triggers on any of them.",
		3, ["indra_crucify_ext"])

	# Fulminate line
	_add("indra_fulminate_ext",
		"Extended Fulminate", "Indra", "Fulminate", MotifNode.UpgradeType.EXTENSION,
		"Fulminate's damage is increased by 20% and it now lowers all enemies' tempo on hit.",
		2, [])

	# Galvanize line
	_add("indra_galvanize_ext",
		"Extended Galvanize", "Indra", "Galvanize", MotifNode.UpgradeType.EXTENSION,
		"Galvanize restores an additional AP to each ally and also grants the party a reroll charge.",
		2, [])
	_add("indra_galvanize_var",
		"Lone Charge", "Indra", "Galvanize", MotifNode.UpgradeType.VARIATION,
		"Galvanize affects only Indra. In exchange he gains an immediate second action this turn.",
		3, ["indra_galvanize_ext"])

	# ── Vritra ────────────────────────────────────────────────────────────────
	# Wither line
	_add("vritra_wither_ext",
		"Extended Wither", "Vritra", "Wither", MotifNode.UpgradeType.EXTENSION,
		"Wither steals 2 CORP instead of 1 and its SHARP debuff lasts one additional turn.",
		2, [])
	_add("vritra_wither_var",
		"Desiccate", "Vritra", "Wither", MotifNode.UpgradeType.VARIATION,
		"Wither no longer steals CORP. Instead it reduces the target's FLAT to zero for two turns.",
		3, ["vritra_wither_ext"])

	# Devour line
	_add("vritra_devour_ext",
		"Extended Devour", "Vritra", "Devour", MotifNode.UpgradeType.EXTENSION,
		"Devour heals for 2 CORP on kill instead of 1. Vritra gains a tempo burst on the same turn.",
		2, [])

	# Vice line
	_add("vritra_vice_ext",
		"Extended Vice", "Vritra", "Vice", MotifNode.UpgradeType.EXTENSION,
		"Vice's transmutation lingers two turns. The ally regenerates 1 CORP per turn while the effect is active.",
		2, [])
	_add("vritra_vice_var",
		"Intoxicate", "Vritra", "Vice", MotifNode.UpgradeType.VARIATION,
		"Vice targets an enemy instead of an ally. It envenoms them — dealing damage over time — while siphoning health to Vritra.",
		3, ["vritra_vice_ext"])


func _add(id: String, motif_name: String, character: String, skill: String,
		upgrade_type: MotifNode.UpgradeType, desc: String, cost: int,
		requires: Array) -> void:
	var n := MotifNode.new()
	n.motif_id     = id
	n.motif_name   = motif_name
	n.character    = character
	n.skill_name   = skill
	n.upgrade_type = upgrade_type
	n.description  = desc
	n.cost         = cost
	n.requires.assign(requires)
	_nodes[id]     = n
