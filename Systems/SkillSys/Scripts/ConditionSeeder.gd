@tool
extends EditorScript
## Run once via File > Run to generate all ConditionData .tres files.
## Each condition is fully described here. Re-run to regenerate.

const COND_DIR = "res://Systems/SkillSys/Resources/Conditions/"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(COND_DIR)
	_write_all()
	print("[ConditionSeeder] Done.")


func _write_all() -> void:
	# ── Bleeding ─────────────────────────────────────────────────────────────
	# Deals 10% max-HP damage per tick. Passes through the full resolve chain
	# so dodge, shield, cover, and martyr can all intercept bleed ticks.
	_save("bleeding", func(c: ConditionData):
		c.display_name    = "Bleeding"
		c.default_duration = 3
		c.on_tick_formula  = \
			'CR.resolve("damage", CR.ctx_new(src, a, max(1, int(a.max_hp * 0.1)), ["bleed_tick"]))'
	)

	# ── Slow ─────────────────────────────────────────────────────────────────
	# Reduces tempo gain to 40%. Stores the original bpm on apply so expire
	# can restore it without needing to know the original value in the formula.
	_save("slow", func(c: ConditionData):
		c.display_name    = "Slowed"
		c.default_duration = 2
		c.on_apply_formula  = 'a.extra_data["pre_slow_bpm"] = a.bpm; a.bpm = max(1, int(a.bpm * 0.4))'
		c.on_remove_formula = 'if a.extra_data.has("pre_slow_bpm"): a.bpm = a.extra_data["pre_slow_bpm"]; a.extra_data.erase("pre_slow_bpm")'
	)

	# ── Frozen ───────────────────────────────────────────────────────────────
	# Stops tempo gain entirely. BattleActor.tick_tempo() already checks
	# has_status("frozen"); until migration is complete we rely on that.
	# After migration: add a hook on "tick_tempo" signal if desired.
	_save("frozen", func(c: ConditionData):
		c.display_name    = "Frozen"
		c.default_duration = 2
		# Freeze is enforced by tick_tempo / FSM checks during migration.
		# No formula needed yet.
	)

	# ── Dodging ──────────────────────────────────────────────────────────────
	# 50% chance to cancel any incoming "damage" event targeting the holder.
	var dodge_hook := _hook(
		"damage",
		"ctx.target == a and randf() < 0.5",
		'ctx.cancelled = true; a.log_msg(a.get_log_name() + " dodges!")',
		"miss"
	)
	_save("dodging", func(c: ConditionData):
		c.display_name    = "Dodging"
		c.default_duration = 4
		c.signal_hooks    = [dodge_hook]
	)

	# ── Shield ───────────────────────────────────────────────────────────────
	# Absorbs incoming damage into shield_hp before it reaches real HP.
	# When shield_hp is depleted it removes itself.
	var shield_hook := _hook(
		"damage",
		"ctx.target == a and a.shield_hp > 0",
		'if ctx.value <= a.shield_hp:\n'
		+ '\ta.shield_hp -= int(ctx.value)\n'
		+ '\tctx.cancelled = true\n'
		+ '\ta.emit_signal("hp_changed")\n'
		+ 'else:\n'
		+ '\tctx.value -= a.shield_hp\n'
		+ '\ta.shield_hp = 0\n'
		+ '\tCR.remove(a, "shield")',
		"shield_break"
	)
	_save("shield", func(c: ConditionData):
		c.display_name    = "Shielded"
		c.default_duration = 999
		c.signal_hooks    = [shield_hook]
	)

	# ── Covered ──────────────────────────────────────────────────────────────
	# Redirects incoming damage from the holder to cover_source (Hue).
	# 35% damage reduction on redirect. Cover restores will proportional to
	# damage if in a tense phase (Hue's Embrace mechanic).
	var cover_hook := _hook(
		"damage",
		"ctx.target == a and is_instance_valid(a.cover_source) and a.cover_source.is_alive() and a.cover_source != ctx.source",
		'var hue = a.cover_source\n'
		+ 'ctx.target = hue\n'
		+ 'ctx.value = int(ctx.value * 0.65)\n'
		+ 'if hue.struggle_restores_will() and hue.party_member != null:\n'
		+ '\thue.party_member.restore_will(max(1, int(ctx.value * 0.5)))',
		""
	)
	_save("covered", func(c: ConditionData):
		c.display_name    = "Covered"
		c.default_duration = 2
		c.on_remove_formula = "a.cover_source = null"
		c.signal_hooks    = [cover_hook]
	)

	# ── Lifesteal ─────────────────────────────────────────────────────────────
	# When the holder (attacker) deals damage, heal them for 50% of damage dealt.
	# Guard checks ctx.source == a so we only fire when *this actor* is attacking.
	var lifesteal_hook := _hook(
		"damage",
		"ctx.source == a and not ctx.cancelled",
		'var heal = max(1, int(ctx.value * 0.5))\n'
		+ 'a.hp = min(a.hp + heal, a.max_hp)\n'
		+ 'a.emit_signal("hp_changed")\n'
		+ 'a.log_msg(a.get_log_name() + " drinks " + str(heal) + " CORP from the wound.")',
		"heal"
	)
	_save("lifesteal", func(c: ConditionData):
		c.display_name    = "Lifesteal"
		c.default_duration = 4
		c.signal_hooks    = [lifesteal_hook]
	)

	# ── Malice ───────────────────────────────────────────────────────────────
	# When the holder takes damage, they immediately counter the attacker.
	# After the counter, Vritra (stored as malice_source) gains will.
	# The counter itself fires a new resolve("damage") so all hooks apply to it.
	var malice_hook := _hook(
		"damage",
		"ctx.target == a and ctx.source != null and a.is_alive() and not ctx.cancelled",
		'var counter_dmg = max(1, a.attack_power)\n'
		+ 'a.log_msg(a.get_log_name() + " returns the blow.")\n'
		+ 'CR.resolve("damage", CR.ctx_new(a, ctx.source, float(counter_dmg), ["counter"]))\n'
		+ 'if is_instance_valid(a.malice_source) and a.malice_source.party_member != null:\n'
		+ '\tvar will_gain = max(1, int(counter_dmg * 0.5))\n'
		+ '\ta.malice_source.party_member.restore_will(will_gain)\n'
		+ '\ta.malice_source.log_msg(a.malice_source.get_log_name() + " feeds on the spite — +" + str(will_gain) + " AP.")',
		"malice_counter"
	)
	_save("malice", func(c: ConditionData):
		c.display_name    = "Malice"
		c.default_duration = 2
		c.on_remove_formula = "a.malice_source = null"
		c.signal_hooks    = [malice_hook]
	)

	# ── Martyr ───────────────────────────────────────────────────────────────
	# Absorbs 50% of all incoming damage into a bonus pool added to the next attack.
	# Two hooks: one absorbs on incoming damage, one releases the pool on outgoing hit.
	var martyr_absorb := _hook(
		"damage",
		"ctx.target == a and not ctx.cancelled",
		'var stored = int(ctx.value * 0.5)\n'
		+ 'a.martyr_bonus_damage += stored\n'
		+ 'a.log_msg(a.get_log_name() + " drinks deeply. (+" + str(stored) + " stored)")',
		"martyr_absorb"
	)
	var martyr_release := _hook(
		"damage",
		"ctx.source == a and a.martyr_bonus_damage > 0",
		'ctx.value += float(a.martyr_bonus_damage)\n'
		+ 'a.log_msg(a.get_log_name() + " pours out the cup. (+" + str(a.martyr_bonus_damage) + " damage)")\n'
		+ 'a.martyr_bonus_damage = 0',
		"martyr_release"
	)
	_save("martyr", func(c: ConditionData):
		c.display_name    = "Martyr"
		c.default_duration = 3
		c.on_apply_formula  = "a.martyr_bonus_damage = 0"
		c.on_remove_formula = "a.martyr_bonus_damage = 0; a.martyr_tempo_bonus = 0.0"
		c.signal_hooks    = [martyr_absorb, martyr_release]
	)

	# ── Encased ───────────────────────────────────────────────────────────────
	# Greatly reduces tempo and halves incoming damage. Removed on the actor's
	# own turn (handled by BattleActor.take_turn — cleared there during migration).
	var encased_hook := _hook(
		"damage",
		"ctx.target == a",
		"ctx.value = int(ctx.value * 0.5)",
		""
	)
	_save("encased", func(c: ConditionData):
		c.display_name    = "Encased"
		c.default_duration = 0   # permanent until cleared by take_turn
		c.signal_hooks    = [encased_hook]
	)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _hook(listen_for: String, guard: String,
		formula: String, then_emit: String) -> ConditionSignalHook:
	var h := ConditionSignalHook.new()
	h.listen_for = listen_for
	h.guard      = guard
	h.formula    = formula
	h.then_emit  = then_emit
	return h


func _save(cid: String, setup: Callable) -> void:
	var c := ConditionData.new()
	c.condition_id = cid
	setup.call(c)
	var path := COND_DIR + cid + ".tres"
	var err := ResourceSaver.save(c, path)
	if err != OK:
		push_error("[ConditionSeeder] Failed to save %s: %d" % [path, err])
	else:
		print("[ConditionSeeder] Saved %s" % path)
