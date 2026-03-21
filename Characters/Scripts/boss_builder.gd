extends RefCounted
# BossBuilder - attaches a synthetic PartyMemberData to boss CharacterData resources
# so support actor scripts have will and skill unlocks without any script changes.

const SUPPORT_SKILLS := {
	"Hue":    ["Shelter", "Embrace", "Calcify"],
	"Indra":  ["Galvanize", "Martyr", "Fulminate"],
	"Vritra": ["Wither", "Waste", "Devour"],
}

const BOSS_WILL := 20

static func make_party_member(char_data: CharacterData) -> PartyMemberData:
	var pm := PartyMemberData.new()
	pm.character  = char_data
	pm.current_hp = char_data.base_max_hp
	pm.max_will   = BOSS_WILL
	pm.will       = BOSS_WILL
	pm.level      = 99
	for skill in SUPPORT_SKILLS.get(char_data.display_name, []):
		pm.skill_unlocks.append(skill)
	return pm
