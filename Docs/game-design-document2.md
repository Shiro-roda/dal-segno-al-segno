# Dal Segno al Segno

Game design document.

**Status in this draft**

- Built: the two-clef layout, Segno, main-path scoring, daily blueprints, tithe/debt, leftover enemies, a walkable Town with a plan console, pause-combat, companion level-up, and a first set of authored resources (see *Current resources*). Models are placeholders and balance is unfinished.
- Planned: most remaining features are agreed upon but not playable yet. See *Backlog: to design and implement*.
- Items marked **(unconfirmed)** were not verified against the code when this draft was written.

---

## Overview

A roguelike about composing a dungeon, then exploring it, then expanding it, then exploring it again.

Each **run** is a sequence of **days**. In the morning you spend resources to place tiles on either of **two overlapping grids**:

- **Treble Clef** — Town: passive income, services, permanent NPC residence, metaprogression.
- **Bass Clef** — Dungeon: enemy and NPC encounters, resource gathering, quest objectives, narrative events.

The two grids share the same coordinates. They can interact **vertically** (a Treble tile and a Bass tile on the same cell) and **horizontally** (a tile on one clef with a neighbour adjacent to it). Then you enter the Bass Clef at the **Segno** (the spawn you placed that morning), fight what spawned, receive differently colored **notes** (building material for tiles) from defeated enemies, and either reach the **exit**, retreat (taking with you only a fraction of your loot), or die on the way.

There is no separate timer. How long and how dangerous a day is depends on what you placed that morning and every morning prior.

The player character is **Kendall**. He does not gain XP or levels, although companions do. Kendall's combat power comes from the party, gear, Town economy, and permanent boosts gained between runs.

---

## How a day works

1. **Plan.** Spend stored resources and equip your party, or walk around the Treble Clef to talk to NPCs and buy services and equipment. Place Treble Clef and Bass Clef tiles next to tiles that already stand **on that same clef**. Place or move the **Segno** on the Bass Clef to set that day's party spawn point. Bass Clef (dungeon) placements also spend a **blueprint** drawn that morning (3 per day); unused blueprints are discarded at the next dawn. Treble Clef (Town) tiles never need a blueprint after being unlocked.
2. **Expedition.** The party appears at the Segno, and makes their way towards the exit. Control Kendall in the built 3D space of the Bass Clef. Companions follow. Walking into a Bass Clef encounter tile starts a fight with every enemy that spawned there. Health (Corpus) and spell resource (Anima) do not refill during the expedition unless something you built or brought heals you.
3. **Return.** Reach the exit and leave the dungeon. Walk around the Treble Clef in the evening, before letting the party fully rest.
4. **Plan again.** Wake up the next morning. Certain Treble Clef tiles generate **income**. New dungeon blueprints are drawn. Enemies respawn. Place the Segno again. Back to planning.
5. **Defeat.** If the party is wiped before reaching the exit or retreating: all equipment is lost, the Bass Clef grid is deleted, Treble Clef tiles become **ruins** on the next run (same spots, cheaper to rebuild), storage resets to the run's starting amounts.

You end a day when the dungeon is cleared or when you retreat because you cannot afford another fight (only keeps a fraction of building resources gained; the partial-loot retreat is not built, see backlog).

---

## Two clefs (spatial)

Town and dungeon are **not** cells on one map. They are two grids that overlay.

| | Treble Clef (Town) | Bass Clef (Dungeon) |
|---|---|---|
| Built on | Its own grid | Its own grid |
| Adjacency for placement | Must touch a standing Treble tile | Must touch a standing Bass tile |
| Blueprints | Never, once the type is unlocked | Daily hand |
| Origin | "Town Square" (built in code; carries the plan console) | Exit and Segno |
| On defeat | Left as ruins (same cells, cheaper rebuild) | Wiped |

**Overlap.** Cell `(x, y)` can hold a Treble tile, a Bass tile, both, or neither. "Both" is a vertical stack. Those stacked pairs are where the two maps are allowed to modify each other. Exact modifiers are not specified yet; they are not "everything is one neighbourhood on a single grid."

Each clef uses the same tile data (cost, colour, income, spawns, scene). Persistence is not a third map: the Treble Clef **is** the map that survives a run as ruins; the Bass Clef is the map that does not.

`TileDef.role` (`NORMAL`, `EXIT`, `ORIGIN`, `SEGNO`) marks the special tiles. `is_exit`, `is_origin`, and `is_segno` are read/write properties over it, so code and tests can use either. They must stay properties, not methods: callers use them without parentheses. The exit, the Town origin, and the Segno room have no tile files; they are built in code.

---

## Persistence (between runs)

| | This run | After defeat |
|---|---|---|
| Bass Clef | Built and explored each day | Deleted |
| Treble Clef | Built each day; income, NPCs, services | Ruins at last positions; remembered tile types, run count, best day |
| Planned to keep | — | Unlocked tile types, NPC state, Kendall's permanent stat gains, starting equipment/loadout choices for the next run |

Companions' levels, feats, and run gear are planned to **reset each run**. Kendall, unlocks, Treble ruins, and NPC flags persist. Currently nothing is saved to disk except combat options and theme preferences, and defeat returns to the start screen. Whether companions reset on defeat is **(unconfirmed)**.

---

## Placement rules (per clef)

- Each clef starts with whatever origin/exit that map needs. The **exit** sits on the Bass Clef; it cannot be built or erased. The Treble Clef has its own origin tile ("Town Square").
- New tiles must touch an existing standing tile on **their** clef (four directions). That clef grows outward from its own standing tiles.
- You cannot move or swap tiles. A ruined Treble cell can either be rebuilt as the **same** tile type, at half cost (default), or torn down and replaced with a different tile.
- Each plan phase you choose the Bass Clef cell for the **Segno**. That is the expedition spawn. It is not the exit.
- Bass tiles with no walking route to the Segno along standing Bass tiles are **disconnected** and yield ×0.5 loot.

### Segno and the main path (Bass Clef)

After the dungeon is laid out, the graph of standing Bass tiles is scored as follows:

- The **main path** is the longest unbroken (simple) path that reaches the Segno. If several paths qualify, the longest is always the main path; a shorter spine is never chosen to dodge penalties.
- Combat and hazard rooms **on that main path** get a bonus of **+0.25 per step** of main-path length. That is the reason to stack those rooms on one long line to the Segno, rather than scattering them.
- A path that **branches off the main path and loops back into it** subtracts **0.25 per loop** from the overall bonus. Side branches that do not rejoin do not confer that penalty; reconnecting loops do.
- Rooms not on the main path do not receive the length bonus.

This replaces an earlier rule that scaled notes by distance from the exit. The day's route is: spawn at Segno → work the dungeon (best rewards on the long path) → walk to the exit to return. A long main path is worth more and is a longer walk to safety.

---

## Tiles

**Treble Clef / Town**

- Cost resources to place on the Treble grid.
- Each dawn, standing Town tiles add **income** (primarily **cuts**, a Town currency).
- **Shops** (`TileDef.shop`, a `ShopDef`): each dawn, and when the tile is built, a shop stocks `slots` different offers picked by weight, skipping offers not yet available on the current day (`min_day`). Stock is per tile. Buying happens during PLAN, is paid from the run's stock (cuts by default), and puts the item in the party's shared bag. Each offer has a price and a number of copies per day. Offers with no price are never stocked.
- Planned uses: NPC housing, party upgrades, quests that ask for specific tiles, resources, or layouts.
- Currently every village tile is always available; built tile ids are recorded but nothing reads them, so unlocking is not implemented.

**Bass Clef / Dungeon**

- Placed from that day's blueprint hand. Today the hand is drawn from a flat pool of dungeon tiles (weighted by `blueprint_weight`, not before `blueprint_min_day`), not from blueprint-producing tiles.
- Each encounter dungeon tile spawns a set number of enemies at expedition start, plus any enemies left alive there yesterday. Differently sized encounter rooms spawn different quantities or qualities of enemies.
- Kills drop **notes** and grant companion XP.
- **Short rest rooms** (`TileDef.rest`, a `RestDef`): interacting restores a fraction of every active character's Anima (rounded up) and lets the party spend **hit dice**. Each die heals its roll plus the Corpus stat modifier (at least 1). Hit dice are a daily pool per character (level × `hit_dice_per_level`), shared by every rest room, and refill at dawn. A room has a number of uses per day and can't be used while remnants are alive in it. The room currently spends every available die up to full Corpus; the player does not choose.
- **Hazard rooms** (`TileDef.hazard`, a `HazardDef`): the first time the party walks in each day, every active character makes a save against the hazard's DC and takes its damage (reduced or negated on a success, per the hazard). A failed save applies the hazard's condition, if any. Unless the hazard is marked lethal, nobody drops below 1 Corpus. Each trigger adds bonus blueprints to the next dawn's hand, drawn from the normal pool and capped by `hazard_bonus_cap`.
- Every dungeon room currently loads the shared `room_base.tscn`; no tile sets its own scene.

### Colour (every room)

Each room has red, green, and blue channels from **0 to 250**.

- **Build cost:** channel ÷ 10 notes of that colour. Example: RGB(140, 240, 30) costs 14 red, 24 green, 3 blue, plus any extra cost (e.g. cuts).
- **Spawns:** the room's enemy table is rolled with a bias: the room's **lowest** channel makes matching enemies **4×** as likely.
- **After combat:** notes looted in that room raise the matching channels (1 note = +1 to colour value, not +10). Neutral/Gray enemies drop notes of random color but in lower quantities.
- **Spent:** RGB(250, 250, 250). The room is pure white and does nothing. It must be **erased** before the cell can be used again. (Other tiles cannot be erased unless a debug option is on.)

Fighting in a room makes its color drift toward neutral values, reducing its overall gains until you remove it or use a special ability to desaturate it. Higher cost rooms therefore have fewer uses, but produce higher quality enemies and provide other benefits.

---

## Resources

| Resource | Role |
|---|---|
| Red / green / blue **notes** | Main build currency. From dungeon kills. Kept between days of a run. Lost on defeat. A run starts with **10** of each. |
| **Cuts** | From Town income. Pays the tithe first by default. Planned shop/upgrade spend. |

The plan screen can allocate notes to be taken before cuts.

---

## Pressure (why days get harder)

Three stacked rules, with current values:

1. Enemy **level** rises **+0.5 per day** (one level every two days).
2. Enemies **left alive** on a tile return **in addition** to the usual spawn, with **+1 level**.
3. A **tithe** is due each dawn: **0 + 1 per day**. Unpaid amount becomes **debt**; every **4 debt** adds 1 enemy level.

Treble ruins cost ×0.5 to rebuild. All numbers are tunable.

---

## Combat

Real-time with pause, **free movement** on the tile (not a tactics grid).

- Each combatant fills an action gauge (higher Tempo/Initiative stats decrease the size of the gauge). When it fills, they act.
- Fights start paused. Pause to queue orders.
- Range comes from the weapon or ability; characters walk into range, then resolve.
- Attacks use a d20 (natural 20 crit, natural 1 fumble; advantage and disadvantage cancel each other out). A critical hit **doubles the dice**.
- **Defense** is 10 + Tempo modifier. **Save DC** is 8 + modifier + level ÷ 4.
- The `attack` modifier adds to every attack roll, weapon or Canto. Conditions can grant advantage or disadvantage to a roll kind (`attack`, `save`), to one stat, or to `all`.
- **Weapon actions** (any action with a weapon-damage step: the basic Attack, Crucify, Brute Force) make several attacks per turn with Guerriero feats: the equipped weapon 1 + extra times, then the secondary weapon if one is held. Extra attacks on a downed target are skipped. Cantos never get extra attacks.
- Damage has a **type** (physical, red, green, blue). Resistances, weaknesses, and immunities scale damage of one type (see *Rules architecture*). Temporary Corpus absorbs damage before Corpus, and ends with the fight.
- All enemies on one dungeon tile fight as **one** encounter.
- Party wipe in combat ends the **run**.
- After a win, companions who have enough XP can level up through the party menu.

---

## Party

Active party: **3** characters, Kendall + two companions. Equipment slots: weapon, armor, trinket. A character with Guerriero I may hold a **secondary weapon** in the armor or trinket slot instead.

**Kendall (player)**

- No XP, no levels, no progression, no Cantos (spells). Tempo 15, Tone 12. Starting weapon: Rusty Six Shooter.
- Corpus (HP): starting hit die plus the Tone stat, plus a bonus that grows when companions level (half of that companion's hit-die roll, rounded up, at least 1; their Tone is not copied).
- Planned: occasional permanent attribute score increase (or extra Corpus) from finishing runs or hitting milestones.

**Companions** (see *Current resources* for full detail)

| Name | Hit die | Feat | Canto | Attribute | Starting weapon |
|---|---|---|---|---|---|
| Hue | d8 | every 4 levels | every 2 | every 2 | Old Umbrella |
| Indra | d10 | every level (default) | every 3 | every 4 | Corroded Pipe |
| Vritra | d6 | every 2 levels | every 2 | every 3 | Dirty Knife |

All three share max level 20 and the same XP thresholds (30, 90, 270, … 35,500). Hit points on level-up are a **rolled** hit die stored on the character, not an average. Level 1 is a full die. Tone applies each level; a level always grants at least 1 Corpus.

Each companion has a feat pool, a Canto pool, and a cantrip pool. Starting loadouts: Hue, Vritra: 1 Canto + 1 cantrip; Indra: 1 feat + 1 Canto + 1 cantrip.

Recruitment in the real game is **planned** to be gradual (join when Town conditions are met). For testing, all four characters are recruited at the start of a new game.

---

## Stats and abilities

Attributes start at 10. Modifier is +/-1 per 2 points above/below 10/11.

| Attribute | Combat role |
|---|---|
| Volume (Vol) | Melee accuracy and damage |
| Tone (Ton) | Corpus and physical saves |
| Tempo (Tem) | Defense, turn speed, ranged accuracy and damage |
| Attachment (Att) | Used for Red Cantos, saves, and skills; feeds max Anima |
| Aversion (Avr) | Used for Green Cantos, saves, and skills; feeds max Anima |
| Delusion (Del) | Used for Blue Cantos, saves, and skills; feeds max Anima |

**Max Anima** = 2 + 1 per 2 levels + the character's best colour-attribute modifier.

Skills (for checks, including dialogue): Charm (Att), Dynamics (Vol), Fraud (Del), Grace (½ Del + Tem), Menace (Avr), Timbre (Ton).

**Cantos** are levelled spells. They cost Anima (1 / 2 / 3 by Canto level). Companions unlock higher Canto levels at character levels **1, 5, and 10**. They can be upcast. **Cantrips** are free-use abilities that gain a tier at levels **5, 10, 15, and 20**. Ordinary abilities may also spend a flat Anima cost.

Cantos each have 1-3 associated colors; bonuses to hit, damage, and DC are drawn from the average of the corresponding attributes; each Canto can target different attributes, some even the attributes their bonuses are drawn from.

On companion level-up the player is shown a random handful of options (default 3) for whatever that level grants: feats, Cantos, and/or +1 to an attribute. Some feats (Virtuoso) grant a follow-up pick, offered right after the level-up confirms. The level-up UI does not yet show the hit-die roll.

---

## Current resources

Everything below exists as authored data in the project. Items that are described but not implemented are called out in the backlog.

### Characters (4)

| Character | Role | Hit die | Weapon | Notes |
|---|---|---|---|---|
| Kendall | Player | — | Rusty Six Shooter | Tempo 15, Tone 12. No progression. |
| Hue | Companion | d8 | Old Umbrella | Starts with 1 Canto, 1 cantrip |
| Indra | Companion | d10 | Corroded Pipe | Starts with 1 feat, 1 Canto, 1 cantrip. **Weak to Red damage (×1.5).** |
| Vritra | Companion | d6 | Dirty Knife | Starts with 1 Canto, 1 cantrip |

Companion feat pools: Guerriero I–III, Virtuoso, and (Indra) Barbaro. Each also has a Canto pool and cantrip pool.

### Cantos (10)

| Canto | Colour | Effect |
|---|---|---|
| Amore | Red | Drains a single ally (2d4), then heals the caster 2d10 + Attachment. Both get *Amorous*. |
| Asceta | none | Heals all allies, grants advantage on attacks (*Roused*), and puts *Bleeding* on the caster. |
| Banality | none | Enemy-only. Save: Delusion vs the caster's Tone. Hits all enemies for 1d4 and applies *Deluded*. In no companion pool. |
| Decelerando | Green | Attack roll. Hits all enemies for 2d4 and applies *Slow* (−10 speed, −3 Tempo, 5 rounds). |
| Dissonante | Green | Save: Aversion. One enemy, 2d8 + Aversion (half on save); applies *Dissonant* (disadvantage on Delusion and Attachment). |
| Dolce | Blue | Heals all allies 1d8 + Delusion. Can be upcast to level 3. |
| Dolore | Red | Attack roll. One enemy, 3d10. |
| Flebile | Red | Save: Attachment. All enemies, 2d6; applies *Feeble* (−3 Volume, disadvantage on Tempo). |
| Fuoco | Blue | Attack roll. One enemy, 3d6; applies *Heartburn* (2d6 per round). |
| Obbligato | Blue | Save: Delusion. Applies *Bound* (blocks actions). |

### Cantrips (4)

| Cantrip | Colour | Effect |
|---|---|---|
| Arietta | Blue | Save: Delusion. All enemies, 1d4; applies *Emotional* (disadvantage on attack). |
| Break | Red tag | Save: Tone vs an Attachment DC. 1d12 + Attachment physical, negated on a save. |
| Low Dim | enemy-only | Attack roll with Tone. 1d6 + Volume. |
| Repel | Green | Attack roll with Aversion. 1d8 green; requests a 10 m push and a stop for one turn (see backlog). |

### Special actions (1)

- **Crucify** (granted by the Baton): Tone save against a Delusion DC; applies *Bleeding* and adds 1d4+1 extra weapon damage.

### Conditions

- Standalone files: **Bleeding** (1d4+1 per round), **Deluded**.
- Defined inline: Amorous, Roused, Slow, Dissonant, Feeble, Heartburn, Bound, Emotional, Repelled, and **Reckless** (Barbaro: −5 attack, +10 damage, 1 round).

### Feats

| Feat | Effect |
|---|---|
| Barbaro | Grants *Brute Force*: attack roll with Volume dealing weapon damage, preceded by *Reckless* on the user (−5 attack, +10 damage, 1 round). No description. |
| Guerriero I | Hold a secondary weapon in place of armor or a trinket, with one extra attack per turn using it. +1 damage. |
| Guerriero II | Two attacks per turn with the primary weapon. +1 attack. |
| Guerriero III | Two attacks per turn with the secondary weapon as well (four total). +1 attack, +1 damage. |
| Virtuoso | Choose an additional Canto from the **entire** list (enemy-only excluded), even one not normally available. Up to 3 times. |

### Items (9)

| Item | Slot | Stats | Notes |
|---|---|---|---|
| Rusty Six Shooter | Weapon | Ranged, d12, Tempo | Kendall's starter |
| Old Umbrella | Weapon | d4, Volume | Hue's starter |
| Corroded Pipe | Weapon | d8, Volume | Indra's starter |
| Dirty Knife | Weapon | d6, Tempo | Vritra's starter |
| Baton | Weapon | 2d4+1, +1 Tempo | Grants *Crucify* |
| Fang | Weapon | 1d6+1, Tempo | Grants *Banquet* |
| Six Shooter | Weapon | 2d6+1, +5 initiative | Guaranteed crit on every 6th shot (described) |
| Umbrella | Weapon | Ranged, 1d4+1, Aversion; +2 Aversion | |
| Soundproof Padding | Armor | +2 defense | |

The Baton, Fang, Six Shooter, Umbrella, and Padding start on nobody. Whether a shop or drop system supplies them is **(unconfirmed)**.

### Enemies (2)

| Enemy | Hit die | Stats | Reward | Actions |
|---|---|---|---|---|
| Banal Shadow | d8 | Vol 15, Ton 14, Tem 12 | 6 XP, 3 notes per kill | Low Dim, Banality |
| Sturdy Shadow | d12 | Tone 17 | 8 XP, 4 notes per kill | Low Dim, Banality |

Neither has a note colour, so both drop random-colour notes.

### Tiles (4 authored)

| Tile | Clef | Colour | Notes |
|---|---|---|---|
| Hallway | Bass | (30,30,30) | No enemies |
| Small Room | Bass | (10,10,10) | 1 spawn, 5 cuts per kill |
| Medium Room | Bass | (20,20,20) | 2 spawns, 6 cuts per kill |
| Salvage Shack | Treble | (50,50,50) | +1 cut per day |

### Stats and skills

All six attribute definitions and six skill definitions exist and match the *Stats and abilities* section.

---

## Rules architecture

How resource-defined elements get unique behaviour without new fields or hardcoded branches in the definition classes.

**Two extension points.**

1. **Effects (active steps).** What an action does when it resolves. `EffectDef` has a closed `Kind` enum plus `Kind.CUSTOM`; subclass `EffectDef` and override `apply_custom(engine, user, victim, ctx)`. Example: `PushEffect` (Repel) records a push and stop on the target's `flags`.
2. **Mechanics (passive listeners).** `Mechanic` is a `Resource` attached through a `mechanics` array on `ActionDef`, `FeatDef`, `ItemDef`, `ConditionDef`, `EnemyTemplate`, and `CharacterSheet` (innate mechanics). Override only the hooks needed.

| Hook | Used for |
|---|---|
| `on_damage_taken(owner, event)` | Resistances, weaknesses, immunities |
| `on_damage_dealt(owner, event)` | Banquet-style gains |
| `on_attack_rolled(owner, action, roll, target)` | Guaranteed crits |
| `on_chosen(sheet)` | Feat-granted picks (Virtuoso) |
| `extra_attacks(owner, secondary)` | Guerriero |
| `allows_secondary_weapon(owner)` | Guerriero I |

**Shipped mechanics:** `DamageTypeAffinity`, `TempCorpusFromDamage`, `NthShotCrit`, `ExtraAttacks`, `GrantBonusPicks`.

**Damage pipeline.** All damage goes through `StatBlock.receive_damage(DamageEvent)`: the target's mechanics edit the event, temporary Corpus absorbs, then Corpus takes the rest. Condition ticks go through the same path with the condition's `tick_damage_type`. Several affinities on one owner multiply together, each rounding down; a multiplier of 0 is immunity.

**Conventions.**

- Plain numbers stay in `modifiers`. Keys must be a registered stat or a pseudo-stat (`defense`, `initiative`, `damage`, `corpus_max`, `anima_max`, `attack`); anything else logs a warning when gear, feats, or conditions are applied.
- Runtime counters live on the owner (`StatBlock.mechanic_state`), never on the shared resource. Temporary Corpus and push/stop flags are cleared by `StatBlock.end_of_fight()`.
- A field is for behaviour every instance of a class might use. A mechanic or effect subclass is for behaviour only a few resources use.

---

## Backlog: to design and implement

### A. Described in data but not implemented

**Combat and rules**

| Item | Problem |
|---|---|
| Slow's −10 speed | Not read. Movement comes from the enemy template's `move_speed`; route it through the stat system. The −3 Tempo part works. |
| Repel's push and stop | `PushEffect` records `push_m` and `stopped_turns` on the target; combat movement does not read them yet. *Repelled* is empty. |
| Crucify's inverted save | Described as failing only by rolling over the DC, otherwise the user damages themselves. No field supports it. |
| Fang's Banquet | `TempCorpusFromDamage` exists; attach it to the Banquet action. |
| Six Shooter crit counter | `NthShotCrit` exists; attach it to the Six Shooter. |
| Resistances and weaknesses | `DamageTypeAffinity` works (Indra is weak to Red). Enemies, items, and conditions still need them authored. |
| Extra attacks and saves | Each extra attack re-applies every step of the action, so Crucify re-rolls its save and Bleed each time. Decide whether that is wanted. Extra attacks also stop on a downed target instead of retargeting, and reach uses the primary weapon's range. |
| Brute Force and Reckless | Check that Reckless's −5 attack applies to the same turn's roll. |
| Barbaro | No description, and in only Indra's pool. |
| Heals | No heal pipeline yet for mechanics (nothing like `on_heal_received`). |

**World and meta**

| Item | Problem |
|---|---|
| Blueprint-producing rooms | Blueprints come from a flat pool, not from tiles. |
| Challenge, NPC, desaturation rooms | Do not exist. |
| Short rest rooms | Built (`RestDef`, `RoomRest`). The player can't choose how many hit dice to spend. A full rest also exists (`PartyRoster.rest_all`). |
| Hazard rooms | Built (`HazardDef`). A lethal hazard that downs the whole party does not trigger defeat. No per-hazard blueprint pool. |
| Shops | Stock, pricing and buying are built (`ShopDef`, `RoomFeatures.buy`). No shop screen or Town interactable calls them yet. |
| Cross-clef interactions | No vertical or horizontal bonuses. |
| Tile unlocking | Built tile ids are recorded but nothing reads them. |
| Town services | No NPCs, quests, or gradual recruitment. |
| Retreat for a fraction of loot | `return_to_exit` banks all loot. No partial-loot path. |
| Between-run progress and saving | Kendall's permanent stat gains not built. Nothing saved to disk except combat options and theme preferences. |
| Item sources | No confirmed shop or drop system for the five unequipped items. |
| Room scenes | No tile sets its own scene; all use `room_base.tscn`. |

### B. Content still to author

- More enemy templates, with note colours so room-colour bias has meaning.
- Descriptions for most Cantos and for Barbaro.
- More Treble tiles (income, housing, shops) and more Bass tiles (challenge, hazard, rest, blueprint, NPC).
- Item acquisition (shop, loot, quest rewards).

### C. Open design questions

- Whether the Bass Clef exit does anything besides return (shop, stash, nothing).
- Whether leftover notes can persist after defeat (today they vanish).
- What vertical and horizontal overlaps actually do (one or a few rule types, not a full modifier matrix).
- How 3D traversal switches or stacks the two clefs.
- How the main-path bonus applies (notes, spawns, both) — values are +0.25 per step and −0.25 per loop.
- Constraints on Segno placement (must touch existing tiles, min distance from the exit, one per day, movable after rooms are down).

---

## Planned content

**Treble Clef (Town)**

- Tile types that produce cuts (currency) and other services.
- Shops that sell items for cuts.
- NPCs with stored game flags (dialogic refers to external variables; it does not own them).
- Quests: build a tile or layout, fetch from a dungeon room, fight a given enemy type, etc.
- Recruits gated on Town construction.
- Upgrades paid in cuts.

**Bass Clef (Dungeon)**

- Encounter rooms (colour + enemy tables + loot). Strongest when placed on the main path to the Segno.
- Challenge / hazard rooms that drop **that day's** dungeon blueprints. Same main-path bonus.
- Short rest rooms that restore part of the party's Corpus and Anima mid-expedition.
- Optional one-run NPC rooms; a persistent flag can move that NPC to the Town.

**Cross-clef bonuses**

- Vertical pairs (same cell on both grids) and horizontal pairs (neighbour on the same clef) that change income, spawns, cost, or access.

**Metaprogression**

- Unlock more Town and dungeon tile types.
- Kendall permanent stats.
- Ruined Town cheaper to rebuild.

**Not returning from an older prototype**

- Multi-phase "segno / transit" run structure.
- Fixed recruit and boss room coordinates.
- "The companion you didn't pick becomes the final boss."

**Presentation to restore later (optional)**

- Real room meshes instead of coloured slabs.
- 45° snap camera with orbit/pan.
- Radial three-choice UI.
- RGB overlay of room colour.
- Card-row confirm screens.

---

## Saving (planned)

Two parts of one save:

1. Persistent: unlocks, Treble Clef ruins, Kendall's permanent changes, NPC flags.
2. Current run: both grids (including each room's colour), Segno cell, storage, tithe debt, leftover enemies, blueprints, day, companions.

Autosave after fights, after placing/erasing, and after returning to the exit.

---

## Current build vs this document

**Built and running:** two separate clef grids, Segno placement, main-path scoring with loop penalties, daily blueprints, tithe and debt, leftover-enemy carry-over, colour costs and stain, spent rooms that must be erased, cheaper Treble ruins, a walkable Town with a plan console on the origin tile, dungeon rooms as individual scenes with doors and an exit zone, pause combat with a typed damage pipeline, extra attacks and secondary weapons, companion XP and level-up with filled pools and follow-up picks, and Kendall's no-XP / shared-Corpus rules.

**Not built yet:** see *Backlog*. In short: several described effects, cross-clef interactions, tile unlocking, shops, hazard and rest rooms, Town services and NPCs, partial-loot retreat, save/load, Kendall's between-run gains, and tile-specific room art.

**Not reviewed:** the Exploration, Environments, Rooms, Audio, and UI folders were not read when this draft was written.
