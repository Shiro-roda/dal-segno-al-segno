# Dal Segno al Segno

Game design document.

**Status in this draft**

- Built: rules exist and can be played in a test level (placeholder models, unfinished balance, missing tile content). The current test still treats both tile types as one grid; the two-clef layout below is the intended design.
- Planned: most features are agreed upon, but not playable yet.

---

## Overview

A roguelike about composing a dungeon, then exploring it, then expanding it, then exploring it again.

Each **run** is a sequence of **days**. In the morning you spend resources to place tiles on either of **two overlapping grids**:

- **Treble Clef** — Town: passive income, services, permanent NPC residence, metaprogression.
- **Bass Clef** — Dungeon: enemy and NPC encounters, resource gathering, quest objectives, narrative events.

The two grids share the same coordinates. They can interact **vertically** (a Treble tile and a Bass tile on the same cell) and **horizontally** (a tile on one clef with a neighbour adjacent to it). Then you enter the Bass Clef at the **Segno** (the spawn you placed that morning), fight what spawned, receive differently colored **notes** (building material for tiles) from defeated enemies, and either reach the **exit**, retreat (taking with you only a fraction of your loot), or die on the way.

There is no separate timer. How long and how dangerous a day is depends on what you placed that morning and every morning prior.

The player character is **Kendall**. He does not gain XP or levels, although companions do. Kendall’s combat power comes from the party, gear, Town economy, and permanent boosts gained between runs.

---

## How a day works

1. **Plan.** Spend stored resources and equip your party, or walk around the Treble Clef to talk to npcs and buy services and equipment. Place Treble Clef and Bass Clef tiles next to tiles that already stand **on that same clef**. Place or move the **Segno** on the Bass Clef to set that day’s party spawn point. Bass Clef (dungeon) placements also spend a **blueprint** drawn that morning; unused blueprints are discarded at the next dawn. Treble Clef (Town) tiles never need a blueprint after being unlocked.
2. **Expedition.** The party appears at the Segno, and makes their way towards the exit. Control Kendall in the built 3D space of the Bass Clef. Companions follow. Walking into a Bass Clef encounter tile starts a fight with every enemy that spawned there. Health (Corpus) and spell resource (Anima) do not refill during the expedition unless something you built or brought heals you.
3. **Return.** Reach the exit and leave the dungeon. Walk around the Treble Clef in the evening, before letting the party fully rest.
4. **Plan again.** Wake up the next morning. Certain Treble Clef tiles generate **income**. New dungeon blueprints are drawn from certain Bass Clef tiles. Enemies respawn. Place the Segno again. Back to planning.
5. **Defeat.** If the party is wiped before reaching the exit or retreating: all equipment is lost, the Bass Clef grid is deleted, Treble Clef tiles become **ruins** on the next run (same spots, cheaper to rebuild), storage resets to the run’s starting amounts.

You end a day when the dungeon is cleared or when you retreat because you cannot afford another fight(only keeps a fraction of building resources gained).

---

## Two clefs (spatial)

Town and dungeon are **not** cells on one map. They are two grids that overlay.

| | Treble Clef (Town) | Bass Clef (Dungeon) |
|---|---|---|
| Built on | Its own grid | Its own grid |
| Adjacency for placement | Must touch a standing Treble tile | Must touch a standing Bass tile |
| Blueprints | Never, once the type is unlocked | Daily hand, from blueprint-producing Bass tiles |
| On defeat | Left as ruins (same cells, cheaper rebuild) | Wiped |

**Overlap.** Cell `(x, y)` can hold a Treble tile, a Bass tile, both, or neither. “Both” is a vertical stack. Those stacked pairs are where the two maps are allowed to modify each other. Exact modifiers are not specified yet; they are not “everything is one neighbourhood on a single grid.”

Each clef still uses the same tile data (cost, colour, income, spawns, scene). Persistence is not a third map: the Treble Clef **is** the map that survives a run as ruins; the Bass Clef is the map that does not.

---

## Persistence (between runs)

| | This run | After defeat |
|---|---|---|
| Bass Clef | Built and explored each day | Deleted |
| Treble Clef | Built each day; income, NPCs, services | Ruins at last positions; remembered tile types, run count, best day |
| Planned to keep | — | Unlocked tile types, NPC state, Kendall’s permanent stat gains, starting equipment/loadout choices for the next run |

Companions’ levels, feats, and run gear are planned to **reset each run**. Kendall, unlocks, Treble ruins, and NPC flags persist.

---

## Placement rules (per clef)

- Each clef starts with whatever origin/exit that map needs. The **exit** used to leave the dungeon sits on the Bass Clef; it cannot be built or erased. (Whether Treble Clef has its own origin tile is still open.)
- New tiles must touch an existing standing tile on **their** clef (four directions). That clef grows outward from its own standing tiles.
- You cannot move or swap tiles. A ruined Treble cell can either be rebuilt as the **same** tile type, at half cost (default), or torn down and replaced with a different tile.
- Each plan phase you choose the Bass Clef cell for the **Segno**. That is the expedition spawn. It is not the exit.
- Bass tiles with no walking route to the Segno along standing Bass tiles have reduced gains.

### Segno and the main path (Bass Clef)

After the dungeon is laid out, the graph of standing Bass tiles is scored as follows:

- The **main path** is the longest unbroken (simple) path that reaches the Segno. If several paths qualify, the longest is always the main path; a shorter spine is never chosen to dodge penalties.
- Combat and hazard rooms **on that main path** get a bonus that scales with the main path’s length. That is the reason to stack those rooms on one long line to the Segno, rather than scattering them.
- A path that **branches off the main path and loops back into it** subtracts from the overall bonus. Side branches that do not rejoin do not confer that penalty; reconnecting loops do.
- Rooms not on the main path do not receive the length bonus.

This replaces an earlier rule that scaled notes by distance from the exit. Exact bonus and loop-penalty numbers are not set.

The day’s route is then: spawn at Segno → work the dungeon (best rewards on the long path) → walk to the exit to return. A long main path is worth more and is a longer walk to safety.

---

## Tiles

**Treble Clef / Town**

- Always available on the plan screen’s Town tab once unlocked.
- Cost resources to place on the Treble grid.
- Each dawn, standing Town tiles add **income** (primarily **cuts**, a Town currency).
- Planned uses: NPC housing, shops, party upgrades, quests that ask for specific tiles, resources, or layouts.

**Bass Clef / Dungeon**

- Placed from that day’s blueprint hand (generated from blueprint-producing dungeon tiles; duplicates are weighted to not appear as often in the same hand).
- Each encounter dungeon tile spawns a set number of enemies at expedition start, plus any enemies left alive there yesterday. Differently sized encounter rooms spawn different quantities or qualities of enemies.
- Kills drop **notes** and grant companion XP.

No authored tile list exists yet. First content needed: at least one Town tile with income, one dungeon tile with enemies and loot, one road/hall tile that does nothing but connect other dungeon tiles, a dedicated exit tile, and a Segno marker.

### Colour (every room)

Each room has red, green, and blue channels from **0 to 250**.

- **Build cost:** channel ÷ 10 notes of that colour. Example: RGB(140, 240, 30) costs 14 red, 24 green, 3 blue, plus any extra cost (e.g. cuts).
- **Spawns:** the room’s enemy table is rolled with a bias toward enemies matching the **lowest** channel(s).
- **After combat:** notes looted in that room raise the matching channels (1 note = +1 to colour value, not +10). Neutral/Gray enemies drop notes of random color but in lower quantities.
- **Spent:** RGB(250, 250, 250). The room is pure white and does nothing. It must be **erased** before the cell can be used again. (Other tiles cannot be erased unless a debug option is on.)

Fighting in a room makes its color drift toward neutral values, reducing its overall gains until you remove it or use a special ability to desaturate it. Higher cost rooms therefore have fewer uses, but produce higher quality enemies (that give more notes of specific colors in less time than a lower value room) and provide other benefits.

---

## Resources

| Resource | Role |
|---|---|
| Red / green / blue **notes** | Main build currency. From dungeon kills. Kept between days of a run. Lost on defeat (run starts with a small stock of each). |
| **Cuts** | From Town income. Pays the tithe first by default. Planned shop/upgrade spend. |

The plan screen can allocate notes to be taken before cuts.

---

## Pressure (why days get harder)

Three stacked rules:

1. Enemy **level** rises with the day (default +1 level every two days).
2. Enemies **left alive** on a tile return **in addition** to the usual spawn, and that tile’s enemies get extra levels.
3. A **tithe** is due each dawn and grows with the day. Unpaid amount becomes **debt**, which also raises enemy levels.

Balance numbers are placeholders.

---

## Combat

Real-time with pause, **free movement** on the tile (not a tactics grid).

- Each combatant fills an action gauge (higher Tempo/Initiative stats decrease the size of the gauge). When it fills, they act.
- Fights start paused. Pause to queue orders.
- Range comes from the weapon or ability; characters walk into range, then resolve.
- Attacks use a d20 (natural 20 crit, natural 1 fumble; advantage and disadvantage cancel each other out).
- All enemies on one dungeon tile fight as **one** encounter.
- Party wipe in combat ends the **run**.
- After a win, companions who have enough XP can level up through the party menu.

---

## Party

Active party: **3** characters, Kendall + two companions. Equipment slots: weapon, armor, trinket.

**Kendall (player)**

- No XP, no levels, no Cantos (spells).
- Corpus (HP): starting hit die plus the Tone stat, plus a bonus that grows when companions level (half of that companion’s hit-die roll, rounded up, at least 1; their Tone is not copied).
- Planned: occasional permanent attribute score increase (or extra Corpus) from finishing runs or hitting milestones.

**Companions (test roster)**

| Name | Hit die | Level-up pattern | Starting weapon |
|---|---|---|---|
| Hue | d8 | Feat every 4 levels; Canto every 2; attribute every 2 | Old Umbrella |
| Indra | d10 | Feat every level; Canto every 3; attribute every 4 | Corroded Pipe |
| Vritra | d6 | Feat every 2; Canto every 2; attribute every 3 | Dirty Knife |

Hit points on level-up are a **rolled** hit die stored on the character, not an average. Level 1 is a full die. Tone applies each level; a level always grants at least 1 Corpus.

Recruitment in the real game is **planned** to be gradual (join when Town conditions are met). For testing, all four characters start in the party. Feat and Canto **offer lists** for companions are not filled in yet.

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

Max Anima is taken from the **highest** of a character's three colour attributes, plus a small amount from companion level.

Skills (for checks, including dialogue): Charm (Att), Dynamics (Vol), Fraud (Del), Grace (½ Del + Tem), Menace (Avr), Timbre (Ton).

**Cantos** are levelled spells. They cost Anima (1 / 2 / 3 by Canto level). Companions unlock higher Canto levels at character levels 1, 5, and 10. They can be upcast. Ordinary abilities may also spend a flat Anima cost.

Cantos each have 1-3 associated colors; bonuses to hit, damage, and DC are drawn from the average of the corresponding attributes; each Canto can target different attributes, some even the attributes their bonuses are drawn from.

On companion level-up the player is shown a random handful of options (default 3) for whatever that level grants: feats, Cantos, and/or +1 to an attribute. The level-up UI does not yet show the hit-die roll.

---

## Planned content

**Treble Clef (Town)**

- Tile types that produce cuts(currency) and other services.
- NPCs with stored game flags (dialogic refers to external variables; it does not own them).
- Quests: build a tile or layout, fetch from a dungeon room, fight a given enemy type, etc.
- Recruits gated on Town construction.
- Shop / upgrades paid in cuts.

**Bass Clef (Dungeon)**

- Encounter rooms (colour + enemy tables + loot). Strongest when placed on the main path to the Segno.
- Challenge / hazard rooms that drop **that day’s** dungeon blueprints. Same main-path bonus.
- Optional one-run NPC rooms; a persistent flag can move that NPC to the Town.
- Daily **Segno** placement (spawn). Not the old multi-phase Segno checkpoint from the prior prototype.

**Cross-clef bonuses**

- Vertical pairs (same cell on both grids) and horizontal pairs (neighbour on the same clef) that change income, spawns, cost, or access.
- How the player moves between clefs in 3D (stairs, overlap, camera) is not specified yet.

**Metaprogression**

- Unlock more Town (always listed) and dungeon (still daily-draw) tile types.
- Kendall permanent stats.
- Ruined Town cheaper to rebuild.

**Not returning from an older prototype**

- Multi-phase “segno / transit” run structure.
- Fixed recruit and boss room coordinates.
- “The companion you didn’t pick becomes the final boss.”

**Presentation to restore later (optional)**

- Real room meshes instead of coloured slabs.
- 45° snap camera with orbit/pan.
- Radial three-choice UI.
- RGB overlay of room colour.
- Card-row confirm screens.

---

## Saving (planned)

Two parts of one save:

1. Persistent: unlocks, Treble Clef ruins, Kendall’s permanent changes, NPC flags.
2. Current run: both grids (including each room’s colour), Segno cell, storage, tithe debt, leftover enemies, blueprints, day, companions.

Autosave after fights, after placing/erasing, and after returning to the exit.

---

## Still undecided

- Whether the Bass Clef exit does anything besides return (shop, stash, nothing), and whether Treble Clef has its own origin tile.
- Whether leftover notes can persist after defeat (today they vanish; there is no “successful loop complete” besides dying).
- Which vertical and horizontal overlaps actually do (one or a few rule types, not a full modifier matrix).
- How 3D traversal switches or stacks the two clefs.
- Exact size of the main-path length bonus and of the looping-branch penalty; what the bonus applies to (notes, spawns, both, etc.).
- Constraints on Segno placement (must touch existing tiles, min distance from the exit, one per day, movable after rooms are down, etc.).
- Exact tile and enemy roster.

---

## Current build vs this document

Playable in a test level: plan screen, day loop, colour costs and stain, blueprints, tithe/debt, leftover spawns, 3D walk, pause combat, companion XP and level-up, Kendall’s no-XP / shared Corpus rules. Town and dungeon currently share **one** grid. Spawn is the exit, not a Segno.

Not playable yet: two overlapping clef grids and their vertical/horizontal interactions, daily Segno spawn and main-path scoring, real tile/enemy content, save/load, NPC quests, companion reset on defeat, Kendall’s between-run stat gains, walkable room art.
