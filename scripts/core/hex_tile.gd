class_name HexTile
extends RefCounted
## Represents a single hex tile on the map grid.
## Each tile has axial coordinates (q, r) and 7 internal slots for unit placement.

## Tile terrain types
enum TerrainType {
	GRASS,
	MOUNTAIN,
	WATER,
	HIVE,
}

## Axial coordinate of this tile
var coord: Vector2i

## Pixel position of the tile center (cached for performance)
var pixel_center: Vector2

## Terrain type
var terrain: TerrainType = TerrainType.GRASS

## Elevation level (0 = low ground, 1 = high ground)
var elevation: int = 0

## Whether this tile is a ramp (transition between elevations)
var is_ramp: bool = false

## Direction index (0-5) pointing from this ramp tile toward the LOW side.
## Only meaningful when is_ramp == true. -1 = unset.
var ramp_exit_dir: int = -1

## Whether a building occupies this tile
var has_building: bool = false

## Reference to the Building node on this tile (null if none).
var building: Variant = null

## The 7 internal slot states (true = occupied, false = empty)
var slot_occupied: Array[bool] = [false, false, false, false, false, false, false]

## References to entities in each slot (null = empty)
## Stored as generic Variant to avoid circular dependencies.
var slot_entities: Array = [null, null, null, null, null, null, null]


func _init(q: int, r: int, hex_size: float) -> void:
	coord = Vector2i(q, r)
	pixel_center = HexHelper.axial_to_pixel(coord, hex_size)


## Returns the number of occupied slots.
func get_occupied_count() -> int:
	var count: int = 0
	for occupied in slot_occupied:
		if occupied:
			count += 1
	return count


## Returns the number of free slots.
func get_free_count() -> int:
	return 7 - get_occupied_count()


## Returns true if at least one slot is free.
func has_free_slot() -> bool:
	for occupied in slot_occupied:
		if not occupied:
			return true
	return false


## Returns the index of the first free slot, or -1 if full.
func get_first_free_slot() -> int:
	for i in range(7):
		if not slot_occupied[i]:
			return i
	return -1


## Place an entity in a specific slot. Returns true if successful.
func occupy_slot(slot_index: int, entity: Variant = null) -> bool:
	if slot_index < 0 or slot_index >= 7:
		return false
	if slot_occupied[slot_index]:
		return false
	slot_occupied[slot_index] = true
	slot_entities[slot_index] = entity
	return true


## Remove an entity from a slot. Returns true if successful.
func free_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= 7:
		return false
	if not slot_occupied[slot_index]:
		return false
	slot_occupied[slot_index] = false
	slot_entities[slot_index] = null
	return true


## Clear all slots.
func clear_all_slots() -> void:
	for i in range(7):
		slot_occupied[i] = false
		slot_entities[i] = null


## Check if the tile is walkable (not mountain/water, not a wall building).
func is_walkable() -> bool:
	if terrain == TerrainType.MOUNTAIN or terrain == TerrainType.WATER:
		return false
	if building != null and building.data != null and building.data.blocks_walkability:
		return false
	return true
