extends Resource
class_name SkillEffect
## One atomic effect that fires when a skill is used.
## Chain multiple SkillEffects on a single SkillData to compose complex skills.
## All fields have safe defaults — fill only what the chosen effect_type needs.

enum EffectType {
	DAMAGE,       ## Deal damage_mult * attacker.attack_power to each target.
	STATUS,       ## Apply status_id for status_duration turns to each target.
	HEAL,         ## Restore heal_amount HP to each target (flat) or heal_mult * max_hp (if heal_flat=false).
	DRAIN,        ## Deal damage, then restore a fraction (drain_ratio) of damage dealt to self.
	SELF_DAMAGE,  ## Deal self_damage_amount to self (flat).
	SELF_STATUS,  ## Apply status_id to self for status_duration turns.
	SELF_HEAL,    ## Restore heal_amount HP to self.
	AOE_DAMAGE,   ## Same as DAMAGE but ignores the is_aoe flag — always hits all opponents.
}

@export var effect_type   : EffectType = EffectType.DAMAGE

## ── DAMAGE / AOE_DAMAGE / DRAIN ──────────────────────────────────────────────
## Multiplier applied to attacker.attack_power. 1.0 = full damage.
@export var damage_mult   : float = 1.0
## Flat bonus damage added after the multiplier. 0 = none.
@export var damage_bonus  : int   = 0

## ── DRAIN ────────────────────────────────────────────────────────────────────
## Fraction of damage dealt that is restored to self as HP. 0.5 = 50%.
@export var drain_ratio   : float = 0.5

## ── STATUS / SELF_STATUS ─────────────────────────────────────────────────────
## Status effect ID matching BattleActor constants (e.g. "slow", "bleeding").
@export var status_id     : String = ""
## Number of turns the status lasts.
@export var status_duration : int = 2
## Probability (0.0–1.0) that the status is applied. 1.0 = always.
@export var status_chance : float = 1.0

## ── HEAL / SELF_HEAL ─────────────────────────────────────────────────────────
## Flat HP to restore. If heal_flat is false, treated as a percentage of max_hp.
@export var heal_amount   : int   = 0
@export var heal_flat     : bool  = true

## ── SELF_DAMAGE ──────────────────────────────────────────────────────────────
@export var self_damage_amount : int = 0

## ── Timing ───────────────────────────────────────────────────────────────────
## Small delay in seconds inserted BEFORE this effect fires. Useful for stagger.
@export var pre_delay     : float = 0.0
## Small delay inserted AFTER this effect fires.
@export var post_delay    : float = 0.0
