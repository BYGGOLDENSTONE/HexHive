class_name HexGrid
extends Node2D
## Manages the hex tile map. Creates, stores, and queries pointy-top hex tiles.

signal tile_hovered(coord: Vector2i)
signal tile_unhovered()
signal tile_clicked(coord: Vector2i)

## Hex outer radius in pixels (center to vertex)
@export var hex_size: float = 48.0

## Map radius in hexes (produces a hex-shaped map)
@export var map_radius: int = 20

## Radius for inner unit slot positioning (computed from hex_size for perfect fit)
var slot_radius: float

## All tiles indexed by axial coordinate
var tiles: Dictionary = {}  # Dictionary[Vector2i, HexTile]

## Currently hovered tile coordinate (or null)
var hovered_coord: Variant = null


func _ready() -> void:
	slot_radius = hex_size * 3.0 / 5.0
	_generate_map()


## Generate a hex-shaped map with the given radius.
func _generate_map() -> void:
	tiles.clear()
	var all_coords: Array[Vector2i] = HexHelper.get_hexes_in_range(Vector2i.ZERO, map_radius)
	for coord in all_coords:
		var tile := HexTile.new(coord.x, coord.y, hex_size)
		tiles[coord] = tile


## Get the tile at a given axial coordinate, or null if out of bounds.
func get_tile(coord: Vector2i) -> HexTile:
	return tiles.get(coord) as HexTile


## Check if a coordinate is within the map.
func has_tile(coord: Vector2i) -> bool:
	return tiles.has(coord)


## Convert a world pixel position to the hex coordinate it falls in.
func world_to_hex(world_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = to_local(world_pos)
	return HexHelper.pixel_to_hex(local_pos, hex_size)


## Convert a hex coordinate to its world pixel position.
func hex_to_world(coord: Vector2i) -> Vector2:
	var local_pos: Vector2 = HexHelper.axial_to_pixel(coord, hex_size)
	return to_global(local_pos)


## Get the walkable neighbors of a hex (tiles that exist and are walkable).
func get_walkable_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for neighbor in HexHelper.get_neighbors(coord):
		var tile: HexTile = get_tile(neighbor)
		if tile and tile.is_walkable():
			result.append(neighbor)
	return result


## Get the pixel positions of all 7 inner slots for a tile.
func get_tile_slot_positions(coord: Vector2i) -> Array[Vector2]:
	return HexHelper.get_slot_positions(coord, hex_size, slot_radius)


## Get all tiles of a specific terrain type.
func get_tiles_by_terrain(terrain: HexTile.TerrainType) -> Array[HexTile]:
	var result: Array[HexTile] = []
	for tile: HexTile in tiles.values():
		if tile.terrain == terrain:
			result.append(tile)
	return result


## Get total tile count.
func get_tile_count() -> int:
	return tiles.size()
