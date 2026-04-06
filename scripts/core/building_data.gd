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
