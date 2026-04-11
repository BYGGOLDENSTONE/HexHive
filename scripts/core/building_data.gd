extends Resource
## Defines a building type with its properties, tags, and 3D model data.
## Each building type is a .tres file in resources/buildings/.

## Unique identifier for this building type.
@export var id: StringName = &""

## Display name shown in UI.
@export var display_name: String = ""

## Short description shown in build menu.
@export var description: String = ""

## Tags for the tag-based system (e.g. &"defense", &"ranged", &"economy").
@export var tags: Array[StringName] = []

## Maximum upgrade level (1 = no upgrades, 3 = two upgrades).
@export var max_level: int = 3

## Terrain types this building can be placed on (int values from HexTile.TerrainType).
## 0=GRASS, 1=MOUNTAIN, 2=WATER, 3=HIVE
@export var buildable_on: Array[int] = [0]

## Whether this building blocks hero/unit movement.
@export var blocks_walkability: bool = false

## Whether the player can build this (false for Hive which is pre-placed).
@export var player_buildable: bool = true

# -- Combat stats (per level) --

## Max HP per upgrade level (length should match max_level).
@export var max_hp_per_level: Array[float] = [100.0]

## Damage per attack per level (0 = does not attack).
@export var attack_damage_per_level: Array[float] = [0.0]

## Attack range in world units per level.
@export var attack_range_per_level: Array[float] = [0.0]

## Attacks per second per level.
@export var attack_speed_per_level: Array[float] = [0.0]

## True if this building can be destroyed.
@export var destructible: bool = true

# -- Economy --

## Honey cost to place this building at each level.
## Index 0 = L1 placement cost, Index 1 = upgrade L1→L2, Index 2 = upgrade L2→L3.
## Length should match max_level. Empty or 0 = free.
@export var cost_per_level: Array[int] = [0]

## Honey income granted once per combat round (when the day's wave is cleared).
## Flower Garden etc. pay out at the end of each day, not during combat.
## Length should match max_level. 0 = no income.
@export var honey_per_round_per_level: Array[int] = [0]

# -- 3D Model --

## Path to the GLB model scene. Empty = use procedural placeholder.
@export var model_path: String = ""

## Scale multiplier for the 3D model.
@export var model_scale: Vector3 = Vector3.ONE

## Vertical offset for the model (positive = up).
@export var model_y_offset: float = 0.0


## Get max HP for a given level (1-indexed, clamped to data length).
func get_max_hp(level: int) -> float:
	var idx: int = clampi(level - 1, 0, max_hp_per_level.size() - 1)
	if max_hp_per_level.is_empty():
		return 100.0
	return max_hp_per_level[idx]


## Get attack damage for a level. Returns 0 if this building doesn't attack.
func get_attack_damage(level: int) -> float:
	if attack_damage_per_level.is_empty():
		return 0.0
	var idx: int = clampi(level - 1, 0, attack_damage_per_level.size() - 1)
	return attack_damage_per_level[idx]


## Get attack range (world units) for a level.
func get_attack_range(level: int) -> float:
	if attack_range_per_level.is_empty():
		return 0.0
	var idx: int = clampi(level - 1, 0, attack_range_per_level.size() - 1)
	return attack_range_per_level[idx]


## Get attacks-per-second for a level.
func get_attack_speed(level: int) -> float:
	if attack_speed_per_level.is_empty():
		return 0.0
	var idx: int = clampi(level - 1, 0, attack_speed_per_level.size() - 1)
	return attack_speed_per_level[idx]


## Returns true if this building has any offensive capability.
func is_offensive() -> bool:
	for d in attack_damage_per_level:
		if d > 0.0:
			return true
	return false


## Get the honey cost to place at L1 or upgrade to the given level.
## level=1 returns placement cost; level=2 returns L1→L2 upgrade cost; etc.
func get_cost(level: int) -> int:
	if cost_per_level.is_empty():
		return 0
	var idx: int = clampi(level - 1, 0, cost_per_level.size() - 1)
	return cost_per_level[idx]


## Get the per-round honey income for the given level. 0 if none.
## Paid out at the end of each day when the wave is cleared.
func get_honey_per_round(level: int) -> int:
	if honey_per_round_per_level.is_empty():
		return 0
	var idx: int = clampi(level - 1, 0, honey_per_round_per_level.size() - 1)
	return honey_per_round_per_level[idx]


## Returns true if this building produces honey income at any level.
func is_economy() -> bool:
	for v in honey_per_round_per_level:
		if v > 0:
			return true
	return false
