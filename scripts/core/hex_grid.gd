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


## Place a building on a tile. Returns true if successful.
func place_building(coord: Vector2i, building_node: Node2D) -> bool:
	var tile := get_tile(coord)
	if tile == null or tile.has_building:
		return false
	tile.has_building = true
	tile.building = building_node
	return true


## Remove a building from a tile.
func remove_building(coord: Vector2i) -> void:
	var tile := get_tile(coord)
	if tile:
		tile.has_building = false
		tile.building = null


## Get the building on a tile (or null).
func get_building_at(coord: Vector2i) -> Variant:
	var tile := get_tile(coord)
	if tile:
		return tile.building
	return null


## Check if a tile can accept a specific building type.
func can_place_building(coord: Vector2i, building_data: Resource) -> bool:
	var tile := get_tile(coord)
	if tile == null:
		return false
	if tile.has_building:
		return false
	if int(tile.terrain) not in building_data.buildable_on:
		return false
	# Refuse the hero's current hex — placing a building there would trap the hero
	# inside a non-walkable cell.
	var hero: Node = get_tree().get_first_node_in_group(&"hero")
	if hero != null and "current_hex" in hero and (hero.current_hex as Vector2i) == coord:
		return false
	return true


## Get all tile coordinates that have buildings.
func get_all_building_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord: Vector2i in tiles:
		if tiles[coord].has_building:
			result.append(coord)
	return result


## Find a path from start to goal across walkable tiles using A*.
##
## - Returns an Array[Vector2i] of coordinates from start (inclusive) to the
##   reached destination (inclusive). Empty array if no path exists.
## - If `goal` itself is unwalkable (e.g. a hex where a building will be placed),
##   the search succeeds when any walkable tile within `goal_range` of `goal` is
##   reached. This lets the hero path adjacent to a build target without trying
##   to step into it.
## - `start` must be walkable; if not, returns an empty array.
func find_path(start: Vector2i, goal: Vector2i, goal_range: int = 0) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var start_tile: HexTile = get_tile(start)
	if start_tile == null or not start_tile.is_walkable():
		return empty
	if HexHelper.distance(start, goal) <= goal_range:
		return [start] as Array[Vector2i]

	# Standard A* on the hex grid. f = g + h where h is hex distance to goal.
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}        # Vector2i -> Vector2i
	var g_score: Dictionary = {start: 0}  # Vector2i -> int
	var f_score: Dictionary = {start: HexHelper.distance(start, goal)}

	while not open_set.is_empty():
		# Pick node in open_set with the lowest f_score.
		var current: Vector2i = open_set[0]
		var current_idx: int = 0
		for i in range(1, open_set.size()):
			var node: Vector2i = open_set[i]
			if int(f_score.get(node, 0x7fffffff)) < int(f_score.get(current, 0x7fffffff)):
				current = node
				current_idx = i
		open_set.remove_at(current_idx)

		if HexHelper.distance(current, goal) <= goal_range:
			return _reconstruct_path(came_from, current)

		for neighbor in get_walkable_neighbors(current):
			var tentative_g: int = int(g_score[current]) + 1
			if tentative_g < int(g_score.get(neighbor, 0x7fffffff)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + HexHelper.distance(neighbor, goal)
				if neighbor not in open_set:
					open_set.append(neighbor)

	return empty


## Walk the came_from chain backwards to reconstruct the path.
func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
