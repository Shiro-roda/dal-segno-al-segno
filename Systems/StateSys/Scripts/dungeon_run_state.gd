extends Resource
class_name DungeonRunState

## Run phases — the musical structure of a run.
enum Phase {
	DA_CAPO,      ## Charges not yet collected. Build freely.
	DAL_SEGNO,    ## Segno is placed. Build freely, safe phase.
	DC_AL_SEGNO,  ## D.C. al Segno: first transit. No building, NO reprime.
	DS_AL_SEGNO,  ## D.S. al Segno: subsequent transits. No building, battles reprimed.
	CAESURA,      ## Died during DAL_SEGNO. Respawned. Redo Semiosis to re-mark the Coda.
	AL_FINE,      ## Final transit to boss room. No building, battles reprimed.
}

var dungeon_data : DungeonData
var run_state : RunState

var grid : Dictionary = {} # Vector2i -> RoomInstance

var current_pos : Vector2i = Vector2i.ZERO

## Current run phase.
var phase : Phase = Phase.DA_CAPO

## Grid position where the Segno is currently placed.
## Vector2i(-999,-999) means no Segno is placed.
var segno_pos : Vector2i = Vector2i(-999, -999)

## Coda marker position — left behind when the player dies during a transit phase.
## During CAESURA the player must return here to place the new Segno.
var coda_pos : Vector2i = Vector2i(-999, -999)

## The grid position that has been designated as the NEXT Segno room.
## Assigned when charges complete; that slot is converted to a SEGNO room.
var next_segno_target : Vector2i = Vector2i(-999, -999)

## All past Segno positions (added each time a Segno is placed).
## Used to grow the minimum range for new Segno room placement.
var past_segno_positions : Array = []  # Array[Vector2i]

## Full snapshot taken when a Segno is placed. Null when no Segno is live.
var segno_snapshot : Resource = null  # SegnoSnapshot

## Level cap enforced during safe phases (DA_CAPO, CAESURA, DAL_SEGNO).
## Starts at 3. On each Segno placement locks to max party level + a bonus
## that shrinks each transit, rewarding early exploration.
## No cap applies during al Segno / al fine phases.
var segno_level_ceiling : int = 3

## How many times the player has completed a full Segno transit (placed down).
## Used to calculate the shrinking ceiling bonus.
var segno_transit_count : int = 0

## Ceiling bonus per transit (index = transit number, 0-based).
## Third placement is generous; bonus shrinks to 0 after several transits.
const CEILING_BONUSES : Array = [1, 2, 3, 2, 1, 0]

## Minimum distance required for the next Segno target from every anchor.
## First placement uses SEGNO_MIN_DIST (set by DungeonController).
## Subsequent placements use the distance between the last two Segnos.
var segno_min_dist : int = 4

## Whether room-building is locked.
func is_building_locked() -> bool:
	return phase == Phase.DC_AL_SEGNO or phase == Phase.DS_AL_SEGNO or phase == Phase.AL_FINE

## Whether the current transit reprimes all battle rooms.
func is_battle_reprimed_transit() -> bool:
	return phase == Phase.DS_AL_SEGNO or phase == Phase.AL_FINE

## Human-readable short phase name for HUD display.
func phase_label() -> String:
	match phase:
		Phase.DA_CAPO:      return "D.C."
		Phase.DAL_SEGNO:    return "D.S."
		Phase.DC_AL_SEGNO:  return "D.C. al §"
		Phase.DS_AL_SEGNO:  return "D.S. al §"
		Phase.CAESURA:      return "caesura"
		Phase.AL_FINE:      return "al fine"
		_: return ""
