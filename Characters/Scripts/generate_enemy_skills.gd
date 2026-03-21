@tool
extends EditorScript
## Run once from the Godot Editor (Script menu -> Run) to generate all enemy
## SkillData + SkillEffect .tres resource files.
## Safe to run multiple times — existing files are overwritten.

const OUT := "res://Characters/Resources/Skills/"

func _run() -> void:
	_make_banal_shadow_skills()
	_make_sturdy_shadow_skills()
	_make_tall_shadow_skills()
	_make_dog_skills()
	print("[SkillGen] Done.")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _effect(type: SkillEffect.EffectType, opts: Dictionary = {}) -> SkillEffect:
	var e := SkillEffect.new()
	e.effect_type = type
	for k in opts:
		e.set(k, opts[k])
	return e

func _skill(sname: String, key: String, summary: String,
		effects: Array, opts: Dictionary = {}) -> SkillData:
	var s := SkillData.new()
	s.skill_name  = sname
	s.command_key = key
	s.summary     = summary
	s.effects     = effects
	for k in opts:
		s.set(k, opts[k])
	return s

func _save(res: Resource, fname: String) -> void:
	var path := OUT + fname
	ResourceSaver.save(res, path)
	print("[SkillGen] saved ", path)


# ── Banal Shadow ──────────────────────────────────────────────────────────────
# ATTACK  — Gnaw:    0.8× damage, 35% bleed (2t)
# SUPPORT — Fester:  SELF: bleed(2t) + malice(2t). AoE flag so no target ring.

func _make_banal_shadow_skills() -> void:
	# Gnaw
	var gnaw_dmg := _effect(SkillEffect.EffectType.DAMAGE,    {"damage_mult": 0.8})
	var gnaw_bleed := _effect(SkillEffect.EffectType.STATUS,  {
		"status_id": "bleeding", "status_duration": 2, "status_chance": 0.35
	})
	_save(_skill("Gnaw", "attack", "Bite for moderate damage with a chance to cause bleeding.",
		[gnaw_dmg, gnaw_bleed]), "gnaw.tres")

	# Fester — self bleed + self malice
	var fest_bleed := _effect(SkillEffect.EffectType.SELF_STATUS, {
		"status_id": "bleeding", "status_duration": 2, "status_chance": 1.0
	})
	var fest_malice := _effect(SkillEffect.EffectType.SELF_STATUS, {
		"status_id": "malice", "status_duration": 2, "status_chance": 1.0
	})
	_save(_skill("Fester", "support",
		"Inflict bleeding on self and enter a retaliating counter-stance.",
		[fest_bleed, fest_malice], {"is_aoe": true}), "fester.tres")


# ── Sturdy Shadow ─────────────────────────────────────────────────────────────
# ATTACK  — Smother:  0.7× damage + slow (2t) on target
# SUPPORT — Brace:    Self-heal 25% max HP. (heal_flat=false, heal_amount=25)

func _make_sturdy_shadow_skills() -> void:
	# Smother
	var sm_dmg  := _effect(SkillEffect.EffectType.DAMAGE, {"damage_mult": 0.7})
	var sm_slow := _effect(SkillEffect.EffectType.STATUS, {
		"status_id": "slow", "status_duration": 2, "status_chance": 1.0
	})
	_save(_skill("Smother", "attack", "Deal reduced damage and slow the target.",
		[sm_dmg, sm_slow]), "smother.tres")

	# Brace — self heal 25% max HP
	var brace_heal := _effect(SkillEffect.EffectType.SELF_HEAL, {
		"heal_amount": 25, "heal_flat": false   # treated as % of max_hp
	})
	_save(_skill("Brace", "support", "Recover 25% of max HP.",
		[brace_heal], {"is_aoe": true}), "brace.tres")


# ── Tall Shadow ───────────────────────────────────────────────────────────────
# ATTACK — Loom:  1.4× damage, single target
# SPECIAL — Oppress: AoE 0.6× + apply slow (2t) to all

func _make_tall_shadow_skills() -> void:
	var loom_dmg := _effect(SkillEffect.EffectType.DAMAGE, {"damage_mult": 1.4})
	_save(_skill("Loom", "attack", "A crushing blow.",
		[loom_dmg]), "loom.tres")

	var opp_dmg  := _effect(SkillEffect.EffectType.AOE_DAMAGE, {"damage_mult": 0.6})
	var opp_slow := _effect(SkillEffect.EffectType.STATUS, {
		"status_id": "slow", "status_duration": 2, "status_chance": 0.7
	})
	_save(_skill("Oppress", "special", "Lash out at all enemies with a chance to slow each.",
		[opp_dmg, opp_slow], {"is_aoe": true}), "oppress.tres")


# ── Dog ───────────────────────────────────────────────────────────────────────
# ATTACK — Bite:   0.9× damage, 50% bleed (1t)
# SUPPORT — Frenzy: self-status dodging (2t), then AoE 0.5× damage

func _make_dog_skills() -> void:
	var bite_dmg   := _effect(SkillEffect.EffectType.DAMAGE, {"damage_mult": 0.9})
	var bite_bleed := _effect(SkillEffect.EffectType.STATUS, {
		"status_id": "bleeding", "status_duration": 1, "status_chance": 0.5
	})
	_save(_skill("Bite", "attack", "A vicious bite that may cause bleeding.",
		[bite_dmg, bite_bleed]), "bite.tres")

	var frenzy_dodge := _effect(SkillEffect.EffectType.SELF_STATUS, {
		"status_id": "dodging", "status_duration": 2, "status_chance": 1.0
	})
	var frenzy_dmg   := _effect(SkillEffect.EffectType.AOE_DAMAGE, {"damage_mult": 0.5})
	_save(_skill("Frenzy", "support",
		"Enter a frenzied dodge-stance and tear at all enemies.",
		[frenzy_dodge, frenzy_dmg], {"is_aoe": true}), "frenzy.tres")
