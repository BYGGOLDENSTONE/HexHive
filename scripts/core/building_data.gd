extends Resource
## Defines a building type with its properties, tags, and visual data.
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

## Base color for procedural rendering (per level, index 0 = level 1).
@export var level_colors: Array[Color] = []

## Accent color for procedural rendering (per level).
@export var level_accent_colors: Array[Color] = []

# -- Combat stats (per level) --

## Max HP per upgrade level (length should match max_level).
@export var max_hp_per_level: Array[float] = [100.0]

## Damage per attack per level (0 = does not attack).
@export var attack_damage_per_level: Array[float] = [0.0]

## Attack range in pixels per level.
@export var attack_range_per_level: Array[float] = [0.0]

## Attacks per second per level.
@export var attack_speed_per_level: Array[float] = [0.0]

## True if this building can be destroyed (false for invulnerable special buildings, currently unused).
@export var destructible: bool = true

# -- Sprite (optional, replaces procedural _draw body) --

## Texture path for the static sprite. Empty = use procedural draw.
@export var sprite_path: String = ""

## Where the structure's visual *base* sits inside the texture, normalized
## vertically (0 = top of image, 1 = bottom). Used to anchor the sprite so
## its base hex sits centered on the tile.
@export var sprite_baseline_v: float = 0.78

## Sprite width relative to the hex tile width (sqrt(3) * hex_size).
## 1.0 = sprite width matches one hex's width exactly.
@export var sprite_width_factor: float = 1.0


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


## Get attack range (pixels) for a level.
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
