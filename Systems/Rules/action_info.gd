class_name ActionInfo
extends RefCounted
## Turns an ActionDef into text the player can read: cost, roll, reach, targets and what
## each effect does. Used by the party menu and the combat HUD.

const TARGET_NAMES := {
	EffectDef.Target.SELF: "self",
	EffectDef.Target.SINGLE_ENEMY: "one enemy",
	EffectDef.Target.SINGLE_ALLY: "one ally",
	EffectDef.Target.ALL_ENEMIES: "all enemies",
	EffectDef.Target.ALL_ALLIES: "all allies",
}


static func title(action: ActionDef) -> String:
	if action == null:
		return ""
	return action.display_name if action.display_name != "" else String(action.id)


## One short line: "Canto 2 · 2 Anima" / "Cantrip · free" / "Attack · free".
static func summary(action: ActionDef, level: int = 0) -> String:
	if action == null:
		return ""
	var cfg: RulesConfig = Rules.engine.config
	if action.is_canto():
		var lv := action.resolve_level(level)
		return "Canto %d · %d Anima" % [lv, cfg.canto_cost(lv)]
	if action.is_cantrip():
		return "Cantrip · free"
	if action.anima_cost > 0:
		return "%d Anima" % action.anima_cost
	return "free"


## Full multi-line description. `level` picks the Canto level shown (0 = the base level).
static func details(action: ActionDef, level: int = 0) -> String:
	if action == null:
		return ""
	var cfg: RulesConfig = Rules.engine.config
	var lines: Array[String] = []
	lines.append("%s  (%s)" % [title(action), summary(action, level)])
	if action.description != "":
		lines.append(action.description)
	if action.can_upcast():
		var levels: Array[String] = []
		for lv in action.castable_levels():
			levels.append("%d (%d Anima)" % [lv, cfg.canto_cost(lv)])
		lines.append("Castable at level: " + ", ".join(levels))

	match action.roll:
		ActionDef.Roll.ATTACK:
			var stat := String(action.attack_stat) if action.attack_stat != &"" else "weapon stat"
			lines.append("Roll: attack, using %s" % stat)
		ActionDef.Roll.SAVE:
			lines.append("Roll: target saves with %s against DC from your %s" % [
					_stat(action.save_stat), _stat(action.dc_stat)])
		_:
			lines.append("Roll: none, always lands")

	var targets: Array[String] = []
	for kind in action.target_kinds():
		targets.append(String(TARGET_NAMES.get(kind, "?")))
	lines.append("Targets: " + ", ".join(targets))
	if action.max_range > 0.0:
		lines.append("Range: %s m" % _num(action.max_range))

	var steps := action.effects.size()
	if steps > 0:
		lines.append("Effects:")
		var lv := action.resolve_level(level)
		var extra := maxi(0, lv - action.canto_level) if action.is_canto() else 0
		for effect in action.effects:
			if effect != null:
				lines.append("  - " + effect_line(effect, action.roll == ActionDef.Roll.SAVE, extra))

	if action.is_cantrip():
		var scales := false
		for effect in action.effects:
			if effect != null and (effect.upcast_dice != "" or effect.upcast_duration > 0):
				scales = true
		if scales:
			var tiers: Array[String] = []
			for lvl in cfg.cantrip_scale_levels:
				tiers.append(str(lvl))
			lines.append("Grows stronger at character levels " + ", ".join(tiers))
	if not action.tags.is_empty():
		lines.append("Tags: " + ", ".join(action.tags))
	return "\n".join(lines)


## What one effect does, e.g. "Deals 2d6+1 red damage to one enemy (save: half)".
static func effect_line(effect: EffectDef, has_save: bool = false, extra_levels: int = 0) -> String:
	var who: String = String(TARGET_NAMES.get(effect.target, "?"))
	var amount := _dice_text(effect, extra_levels)
	var text := ""
	match effect.kind:
		EffectDef.Kind.DAMAGE:
			text = "Deals %s %s damage to %s" % [amount, effect.damage_type, who]
		EffectDef.Kind.WEAPON_DAMAGE:
			text = "Weapon damage to %s" % who
			if amount != "":
				text += ", plus %s %s" % [amount, effect.damage_type]
		EffectDef.Kind.HEAL:
			text = "Heals %s Corpus for %s" % [amount, who]
		EffectDef.Kind.RESTORE_ANIMA:
			text = "Restores %s Anima to %s" % [amount, who]
		EffectDef.Kind.APPLY_CONDITION:
			text = "Applies %s to %s" % [_condition_text(effect, extra_levels), who]
	if has_save:
		match effect.on_save:
			EffectDef.OnSave.NEGATES:
				text += " (save: negates)"
			EffectDef.OnSave.HALF:
				text += " (save: half)"
	return text


static func _dice_text(effect: EffectDef, extra_levels: int) -> String:
	var text := effect.dice
	if effect.bonus_stat != &"" and text != "":
		text += " + %s" % _stat(effect.bonus_stat)
	elif effect.bonus_stat != &"":
		text = _stat(effect.bonus_stat)
	if extra_levels > 0 and effect.upcast_dice != "":
		text += " + %s x%d" % [effect.upcast_dice, extra_levels]
	return text


static func _condition_text(effect: EffectDef, extra_levels: int) -> String:
	var cond := effect.condition
	if cond == null:
		return "a condition"
	var name := cond.display_name if cond.display_name != "" else String(cond.id)
	var turns := effect.condition_duration if effect.condition_duration >= 0 else cond.duration_rounds
	if turns >= 0:
		turns += effect.upcast_duration * extra_levels
	var text := name if turns < 0 else "%s (%d round%s)" % [name, turns, "" if turns == 1 else "s"]
	var bits: Array[String] = []
	for stat in cond.modifiers:
		bits.append("%s %+d" % [_stat(stat), int(cond.modifiers[stat])])
	if not cond.advantage_on.is_empty():
		bits.append("advantage on " + ", ".join(cond.advantage_on))
	if not cond.disadvantage_on.is_empty():
		bits.append("disadvantage on " + ", ".join(cond.disadvantage_on))
	if cond.blocks_actions:
		bits.append("cannot act")
	if cond.tick_damage != "":
		bits.append("%s damage each round" % cond.tick_damage)
	if not bits.is_empty():
		text += " [" + "; ".join(bits) + "]"
	return text


static func _stat(id: StringName) -> String:
	return String(id).capitalize() if id != &"" else "?"


static func _num(value: float) -> String:
	return str(snappedf(value, 0.1))
