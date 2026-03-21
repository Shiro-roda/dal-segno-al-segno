extends Resource
class_name DialogueLine

# Who is speaking. Should match a BattleActor node name or a display_name.
# Leave empty for narration (no speaker label shown).
@export var speaker : String = ""

# The line of dialogue text.
@export var text : String = ""

# Optional condition key. If non-empty, this line only plays when the
# condition is met. Evaluated by BattleDialoguePlayer at battle start.
# Supported keys:
#   "always"            — always plays (default when empty)
#   "party_has_hue"     — Hue is in the player's party
#   "party_has_indra"   — Indra is in the player's party
#   "party_has_vritra"  — Vritra is in the player's party
#   "kendall_low_hp"    — Kendall is below 40% HP
#   "any_low_hp"        — any party member below 40% HP
#   "boss_fight"        — this is a boss encounter (enemy has boss_party_member)
@export var condition : String = ""

# Typewriter settings. If typewriter is true, text appears one character at a
# time. Leave at the default (-1) to use the speaker's default speed.
# Set to false to show the full line instantly regardless of speaker default.
@export var typewriter : bool = true
@export var typewriter_speed : float = -1.0  # chars/sec; -1 = use speaker default

# Optional AudioStream to play for each typed character.
# Leave null to use the speaker's default typing sound.
@export var typing_sound : AudioStream = null
