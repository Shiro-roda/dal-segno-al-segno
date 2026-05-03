## CONDITION FORMULA REFERENCE
## ============================================================
## This file is documentation only. It is never executed.
##
## Formulas are plain GDScript expressions evaluated by GDScript's
## Expression class. Every formula runs with four names already bound:
##
##   a    BattleActor   The actor who HOLDS this condition.
##                      Use `a` to read or modify the holder's state.
##
##   src  BattleActor   The actor who APPLIED the condition (may be null).
##                      Use `src` for "the one who caused this".
##
##   ctx  BattleEventContext   The event currently flowing through the bus.
##                             Null in lifecycle formulas (on_apply, on_tick,
##                             on_expire, on_remove). Always present in
##                             signal_hook formulas.
##
##   CR   ConditionRunner      The autoload singleton. Use it to fire new
##                             events, apply more conditions, etc.
##
## ── WHAT YOU CAN READ ─────────────────────────────────────────────
##
## From any actor (a or src):
##   a.hp                  current hit points  (int)
##   a.max_hp              maximum hit points  (int)
##   a.attack_power        current SHARP stat  (int)
##   a.flat_defense        current FLAT stat   (int)
##   a.bpm                 tempo gain per round
##   a.tempo_pool          accumulated tempo   (float)
##   a.shield_hp           temporary HP buffer (int)
##   a.martyr_bonus_damage stored damage pool  (int)
##   a.extra_data          Dictionary — stash anything you need
##   a.is_alive()          → bool
##   a.has_condition("id") → bool  (new API)
##   a.has_status("id")    → bool  (legacy, still works)
##   a.get_log_name()      → String
##   a.get_opponents()     → Array[BattleActor]
##   a.get_allies()        → Array[BattleActor]
##
## From ctx (signal hooks only):
##   ctx.source            BattleActor who caused the event
##   ctx.target            BattleActor receiving the event  (writable — redirect to another actor)
##   ctx.value             float damage/heal amount          (writable — change the number)
##   ctx.tags              Array[String] e.g. ["physical"]  (readable + appendable)
##   ctx.cancelled         bool — set true to suppress the event entirely
##   ctx.extra             Dictionary — open bag for extra data
##   ctx.has_tag("name")   → bool convenience method
##
## ── WHAT YOU CAN DO ───────────────────────────────────────────────
##
## Modify HP directly (bypasses the resolve chain):
##   a.hp = min(a.hp + 5, a.max_hp)
##   a.emit_signal("hp_changed")  # always emit after writing hp directly
##
## Fire a new damage event (goes through the full resolve/hook chain):
##   CR.resolve("damage", CR.ctx_new(src, a, 10.0, ["bleed_tick"]))
##
## Fire a new heal event:
##   CR.resolve("heal", CR.ctx_new(src, a, 5.0, []))
##
## Apply another condition:
##   CR.apply(a, "slow", src, 2)
##
## Remove a condition:
##   CR.remove(a, "bleeding")
##
## Log a message to the battle feed:
##   a.log_msg("Something happened.")
##
## Modify stats:
##   a.modify_attack(-2)   # reduce SHARP by 2 (bounded)
##   a.modify_flat(3)      # raise FLAT by 3   (bounded)
##
## Stash data across ticks (e.g. remember a pre-condition stat value):
##   a.extra_data["pre_slow_bpm"] = a.bpm
##   a.bpm = max(1, int(a.bpm * 0.4))
##   # later in on_remove_formula:
##   # a.bpm = a.extra_data.get("pre_slow_bpm", a.bpm)
##
## ── GUARD FORMULAS ────────────────────────────────────────────────
## Guards must return a truthy or falsy value. Keep them short.
##
##   "ctx.target == a"             only intercept events hitting the holder
##   "ctx.source == a"             only intercept events caused by the holder
##   "ctx.has_tag(\"physical\")"   only intercept physical hits
##   "not ctx.cancelled"           only run if not already cancelled
##   "a.is_alive()"                only run while holder is alive
##   "ctx.target == a and not ctx.has_tag(\"true_damage\")"
##
## ── FULL EXAMPLES ─────────────────────────────────────────────────
##
## -- BLEEDING --
## on_tick_formula:
##   CR.resolve("damage", CR.ctx_new(src, a, max(1.0, float(a.max_hp) * 0.1), ["bleed_tick"]))
##
## -- SLOW --
## on_apply_formula:
##   a.extra_data["pre_slow_bpm"] = a.bpm; a.bpm = max(1, int(a.bpm * 0.4))
## on_remove_formula:
##   a.bpm = a.extra_data.get("pre_slow_bpm", a.bpm); a.extra_data.erase("pre_slow_bpm")
##
## -- DODGE --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.target == a and not ctx.has_tag("true_damage")
##   formula: if randf() < 0.5: ctx.cancelled = true; a.log_msg(a.get_log_name() + " dodges!")
##
## -- SHIELD --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.target == a and a.shield_hp > 0
##   formula: if ctx.value <= a.shield_hp: a.shield_hp -= int(ctx.value); ctx.cancelled = true; a.emit_signal("hp_changed") \
##            else: ctx.value -= a.shield_hp; a.shield_hp = 0; CR.remove(a, "shield")
##
## -- LIFESTEAL --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.source == a and not ctx.cancelled
##   formula: var h = max(1, int(ctx.value * 0.5)); a.hp = min(a.hp + h, a.max_hp); a.emit_signal("hp_changed"); a.log_msg(a.get_log_name() + " drinks " + str(h) + " CORP.")
##
## -- MARTYR (absorb) --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.target == a and not ctx.cancelled
##   formula: a.martyr_bonus_damage += int(ctx.value * 0.5)
##   then_emit: "martyr_absorb"
##
## -- MARTYR (release on attack) --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.source == a and a.martyr_bonus_damage > 0
##   formula: ctx.value += float(a.martyr_bonus_damage); a.log_msg(a.get_log_name() + " pours out the cup. (+" + str(a.martyr_bonus_damage) + ")"); a.martyr_bonus_damage = 0
##   then_emit: "martyr_release"
##
## -- COVER (redirect incoming damage to Hue) --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.target == a and is_instance_valid(a.cover_source) and a.cover_source.is_alive() and ctx.source != a.cover_source
##   formula: ctx.target = a.cover_source; ctx.value = int(ctx.value * 0.65)
##
## -- MALICE (counter on being hit) --
## signal_hook:  listen_for = "damage"
##   guard:   ctx.target == a and ctx.source != null and a.is_alive() and not ctx.cancelled
##   formula: CR.resolve("damage", CR.ctx_new(a, ctx.source, float(max(1, a.attack_power)), ["counter"])); \
##            if is_instance_valid(a.malice_source) and a.malice_source.party_member != null: \
##              a.malice_source.party_member.restore_will(max(1, int(a.attack_power * 0.5)))
##   then_emit: "malice_counter"
##
## ── NOTES ON MULTI-STATEMENT FORMULAS ─────────────────────────────
## GDScript's Expression class evaluates a single expression, not a block.
## Use semicolons to chain statements on one line.
## Use the backslash continuation in .tres files for readability.
## The return value of the last statement is what _eval_formula() returns —
## this only matters for guard formulas (which must return true/false).
## In main formula strings, the return value is ignored.
##
## If a formula becomes too complex for one line, move the logic into
## a helper method on BattleActor and call it from the formula:
##   a.my_custom_method(ctx)
##
## ── TAG CONVENTIONS ───────────────────────────────────────────────
##   "physical"    normal attack damage — subject to flat defense
##   "true_damage" bypasses flat defense AND dodge AND shield
##   "bleed_tick"  from a bleeding condition tick
##   "counter"     a reactive counter-attack
##   "aoe"         hits multiple targets in one event wave
