class_name HexGrid
extends Node3D
## Manages the hex tile map. Creates, stores, and queries pointy-top hex tiles.
## Hex grid lives on the XZ plane; Y axis is used for elevation.

const _MapGen := preload("res://scripts/core/map_generator.gd")

signal tile_hovered(coord: Vector2i)
signal tile_unhovered()
signal tile_clicked(coord: Vector2i)

## Hex outer radius in world units (center to vertex).
## Matches greentile.glb outer radius after pointy-top fix.
@export var hex_size: float = 0.6929

## Map radius in hexes (produces a hex-shaped map).
@export var map_radius: int = 20

## World units per elevation level.
@export var elevation_height: float = 1.0

## Radius for inner unit slot positioning (computed from hex_size for perfect fit).
var slot_radius: float

## All tiles indexed by axial coordinate.
var tiles: Dictionary = {}  # Dictionary[Vector2i, HexTile]

## Currently hovered tile coordinate (or null).
var hovered_coord: Variant = null

## Effective seed used for map generation (for debug display / reproducibility).
var effective_seed: int = 0


const MAP_SAVE_PATH: String = "res://resources/maps/custom_map.json"


func _ready() -> void:
	slot_radius = hex_size * 3.0 / 5.0
	_create_tiles()
	if not _load_map_from_file():
		_generate_terrain()


## Create all hex tiles with default GRASS terrain.
func _create_tiles() -> void:
	tiles.clear()
	var all_coords: Array[Vector2i] = HexHelper.get_hexes_in_range(Vector2i.ZERO, map_radius)
	for coord in all_coords:
		var tile := HexTile.new(coord.x, coord.y, hex_size)
		tiles[coord] = tile


## Run the procedural map generator to assign terrain, elevation, and ramps.
func _generate_terrain() -> void:
	var config: Dictionary = {}
	effective_seed = _MapGen.generate(tiles, config, hex_size, map_radius)


## Save all non-default tile data to a JSON file.
func save_map_to_file() -> bool:
	var map_data: Array = []
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		# Only save tiles that differ from default (GRASS, elevation 0, no ramp).
		if tile.terrain != HexTile.TerrainType.GRASS or tile.elevation != 0 or tile.is_ramp:
			var entry: Dictionary = {
				"q": coord.x,
				"r": coord.y,
				"terrain": int(tile.terrain),
				"elevation": tile.elevation,
			}
			if tile.is_ramp:
				entry["is_ramp"] = true
				entry["ramp_exit_dir"] = tile.ramp_exit_dir
			map_data.append(entry)

	var json_str: String = JSON.stringify(map_data, "\t")
	var file := FileAccess.open(MAP_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save map: cannot open " + MAP_SAVE_PATH)
		return false
	file.store_string(json_str)
	file.close()
	print("[HexGrid] Map saved to %s (%d modified tiles)" % [MAP_SAVE_PATH, map_data.size()])
	return true


## Load map data from a JSON file. Returns true if loaded successfully.
func _load_map_from_file() -> bool:
	if not FileAccess.file_exists(MAP_SAVE_PATH):
		return false

	var file := FileAccess.open(MAP_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_error("Failed to parse map file: " + json.get_error_message())
		return false

	var map_data: Array = json.data as Array
	if map_data == null:
		return false

	for entry: Variant in map_data:
		var d: Dictionary = entry as Dictionary
		var coord := Vector2i(d["q"] as int, d["r"] as int)
		var tile: HexTile = get_tile(coord)
		if tile == null:
			continue
		tile.terrain = d["terrain"] as HexTile.TerrainType
		tile.elevation = d.get("elevation", 0) as int
		if d.has("is_ramp"):
			tile.is_ramp = d["is_ramp"] as bool
			tile.ramp_exit_dir = d.get("ramp_exit_dir", -1) as int

	print("[HexGrid] Map loaded from %s (%d modified tiles)" % [MAP_SAVE_PATH, map_data.size()])
	return true


## Reset all tiles to default GRASS and regenerate with procedural generator.
func reset_to_procedural() -> void:
	for tile: HexTile in tiles.values():
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
	_generate_terrain()


## Get the tile at a given axial coordinate, or null if out of bounds.
func get_tile(coord: Vector2i) -> HexTile:
	return tiles.get(coord) as HexTile


## Check if a coordinate is within the map.
func has_tile(coord: Vector2i) -> bool:
	return tiles.has(coord)


## Convert a 3D world position to the hex coordinate it falls in (ignores Y).
func world_to_hex(world_pos: Vector3) -> Vector2i:
	var local_pos: Vector3 = world_pos - global_position
	return HexHelper.pixel_to_hex(Vector2(local_pos.x, local_pos.z), hex_size)


## Convert a hex coordinate to its 3D world position (with elevation Y).
func hex_to_world(coord: Vector2i) -> Vector3:
	var pixel: Vector2 = HexHelper.axial_to_pixel(coord, hex_size)
	var tile: HexTile = get_tile(coord)
	var y: float = 0.0
	if tile:
		y = float(tile.elevation) * elevation_height
	return Vector3(pixel.x, y, pixel.y) + global_position


## Get the walkable neighbors of a hex (tiles that exist and are walkable).
func get_walkable_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for neighbor in HexHelper.get_neighbors(coord):
		var tile: HexTile = get_tile(neighbor)
		if tile and tile.is_walkable():
			result.append(neighbor)
	return result


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
func place_building(coord: Vector2i, building_node: Node3D) -> bool:
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


## A* pathfinding across walkable tiles.
func find_path(start: Vector2i, goal: Vector2i, goal_range: int = 0) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var start_tile: HexTile = get_tile(start)
	if start_tile == null or not start_tile.is_walkable():
		return empty
	if HexHelper.distance(start, goal) <= goal_range:
		return [start] as Array[Vector2i]

	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: HexHelper.distance(start, goal)}

	while not open_set.is_empty():
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


func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


## Project a screen-space mouse position to the ground plane via camera ray.
## Returns the XZ world position at Y = target_y.
func get_mouse_world_position(target_y: float = 0.0) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3.ZERO
	var t: float = (target_y - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return Vector3.ZERO
	return ray_origin + ray_dir * t
