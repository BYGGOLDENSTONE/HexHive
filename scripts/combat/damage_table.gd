class_name DamageTable
## Static utility for tag-based damage modifier resolution.
## Attacker tags * defender tags → multiplier.
## Foundation for the tag-based combat system (future elements: fire+wet, holy+undead, etc.).
##
## Current rules (minimal):
##   ranged + armored  -> 0.6  (armor deflects arrows/projectiles)
##   melee + flying    -> 0.7  (harder to reach airborne targets)
##   piercing + armored -> 1.4 (anti-armor bonus)
##   heavy + swarm     -> 1.3  (area damage sweeps swarms)
##
## Call DamageTable.compute(base, attacker_tags, defender_tags) -> float.

## Attacker tag × defender tag -> multiplier. Missing keys default to 1.0.
const MULTIPLIERS: Dictionary = {
	"ranged|armored": 0.6,
	"melee|flying": 0.7,
	"piercing|armored": 1.4,
	"heavy|swarm": 1.3,
}


## Resolve the final damage number after applying all tag interactions.
static func compute(base_amount: float, attacker_tags: Array, defender_tags: Array) -> float:
	if attacker_tags.is_empty() or defender_tags.is_empty():
		return base_amount

	var multiplier: float = 1.0
	for atk in attacker_tags:
		for def in defender_tags:
			var key: String = "%s|%s" % [String(atk), String(def)]
			if MULTIPLIERS.has(key):
				multiplier *= float(MULTIPLIERS[key])

	return base_amount * multiplier
