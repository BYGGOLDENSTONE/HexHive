class_name HexGrid
extends Node3D
## Manages the hex tile map. Creates, stores, and queries pointy-top hex tiles.
## Hex grid lives on the XZ plane; Y axis is used for elevation.

const _MapGen := preload("res://scripts/core/map_generator.gd")
const _PriorityQueue := preload("res://scripts/utils/priority_queue.gd")

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

## Spatial index: hex coord -> Array of enemy Node3D currently occupying that hex.
## Maintained by Enemy.gd via register_enemy_at / unregister_enemy_from / move_enemy.
## Lets hero and turrets skip per-frame get_nodes_in_group scans.
var enemy_by_hex: Dictionary = {}  # Vector2i -> Array[Node3D]

## Path cache: (start, goal, goal_range) -> Array[Vector2i].
## Invalidated whenever a building is placed or destroyed.
var _path_cache: Dictionary = {}

## Currently hovered tile coordinate (or null).
var hovered_coord: Variant = null

## Effective seed used for map generation (for debug display / reproducibility).
var effective_seed: int = 0


const MAPS_DIR: String = "res://resources/maps/"
const DEFAULT_MAP_NAME: String = "custom_map"

## Currently loaded map name (without extension).
var current_map_name: String = DEFAULT_MAP_NAME


func _ready() -> void:
	slot_radius = hex_size * 3.0 / 5.0
	_create_tiles()
	# Load saved map if one exists; otherwise leave all tiles as default GRASS.
	# The procedural generator is no longer auto-called. Use the Map Editor
	# (standalone scene) to create and save maps, or call reset_to_procedural()
	# explicitly from a dev console command.
	_load_map_from_file()
	# Any building placement or destruction invalidates cached paths.
	SignalBus.building_placed.connect(_on_grid_topology_changed)
	SignalBus.building_destroyed.connect(_on_grid_topology_changed_node)


func _on_grid_topology_changed(_id: StringName, _coord: Vector2i, _level: int) -> void:
	_path_cache.clear()


func _on_grid_topology_changed_node(_building: Node, _coord: Vector2i) -> void:
	_path_cache.clear()


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


## Get the file path for a named map slot.
func _get_map_path(map_name: String = "") -> String:
	if map_name.is_empty():
		map_name = current_map_name
	return MAPS_DIR + map_name + ".json"


## Save all non-default tile data to a JSON file.
## If map_name is empty, uses the current map name.
func save_map_to_file(map_name: String = "") -> bool:
	if map_name.is_empty():
		map_name = current_map_name
	var save_path: String = _get_map_path(map_name)

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
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save map: cannot open " + save_path)
		return false
	file.store_string(json_str)
	file.close()
	current_map_name = map_name
	print("[HexGrid] Map saved to %s (%d modified tiles)" % [save_path, map_data.size()])
	return true


## Load map data from a JSON file. Returns true if loaded successfully.
## If map_name is empty, uses the current map name.
func load_map_from_file(map_name: String = "") -> bool:
	if map_name.is_empty():
		map_name = current_map_name
	var load_path: String = _get_map_path(map_name)

	if not FileAccess.file_exists(load_path):
		return false

	var file := FileAccess.open(load_path, FileAccess.READ)
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

	current_map_name = map_name
	print("[HexGrid] Map loaded from %s (%d modified tiles)" % [load_path, map_data.size()])
	return true


## List all saved map names (without .json extension).
func get_saved_map_names() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## Delete a saved map file. Returns true on success.
func delete_map(map_name: String) -> bool:
	var path: String = _get_map_path(map_name)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return false
	return dir.remove(map_name + ".json") == OK


## Private alias used internally at startup.
func _load_map_from_file() -> bool:
	return load_map_from_file()


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


## Get the walkable neighbors of a hex, accounting for elevation.
## max_climb: how many elevation levels an entity can traverse without a ramp.
## Default 0 means only same-level or ramp connections are walkable.
func get_walkable_neighbors(coord: Vector2i, max_climb: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var tile: HexTile = get_tile(coord)
	if tile == null:
		return result
	for neighbor in HexHelper.get_neighbors(coord):
		var ntile: HexTile = get_tile(neighbor)
		if ntile == null or not ntile.is_walkable():
			continue
		# Elevation check: adjacent tiles with elevation diff > max_climb
		# are IMPASSABLE unless one of them is a ramp.
		var elev_diff: int = absi(tile.elevation - ntile.elevation)
		if elev_diff > max_climb:
			# Ramps bridge exactly 1 elevation level.
			if elev_diff == 1 and (tile.is_ramp or ntile.is_ramp):
				result.append(neighbor)
			# else: impassable cliff face
		else:
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
	_path_cache.clear()
	return true


## Remove a building from a tile.
func remove_building(coord: Vector2i) -> void:
	var tile := get_tile(coord)
	if tile:
		tile.has_building = false
		tile.building = null
		_path_cache.clear()


# -- Spatial cache: enemies indexed by hex --

## Register an enemy node as occupying the given hex.
func register_enemy_at(coord: Vector2i, enemy: Node3D) -> void:
	if not enemy_by_hex.has(coord):
		enemy_by_hex[coord] = []
	var arr: Array = enemy_by_hex[coord]
	if enemy not in arr:
		arr.append(enemy)


## Remove an enemy node from the given hex bucket.
func unregister_enemy_from(coord: Vector2i, enemy: Node3D) -> void:
	if not enemy_by_hex.has(coord):
		return
	var arr: Array = enemy_by_hex[coord]
	arr.erase(enemy)
	if arr.is_empty():
		enemy_by_hex.erase(coord)


## Move an enemy between hex buckets (old == new is a no-op).
func move_enemy(old_coord: Vector2i, new_coord: Vector2i, enemy: Node3D) -> void:
	if old_coord == new_coord:
		return
	unregister_enemy_from(old_coord, enemy)
	register_enemy_at(new_coord, enemy)


## Return all alive enemy nodes within `hex_radius` hex tiles of `center`.
## Hex radius is approximate — callers may still do a final world-space distance check.
func get_enemies_in_hex_radius(center: Vector2i, hex_radius: int) -> Array:
	var result: Array = []
	if hex_radius <= 0:
		if enemy_by_hex.has(center):
			result.append_array(enemy_by_hex[center])
		return result
	var coords: Array[Vector2i] = HexHelper.get_hexes_in_range(center, hex_radius)
	for c in coords:
		if enemy_by_hex.has(c):
			result.append_array(enemy_by_hex[c])
	return result


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


## A* pathfinding across walkable tiles, with a heap-based open set
## and a per-grid path cache invalidated on building topology changes.
## max_climb: elevation levels an entity can step without a ramp (default 0).
func find_path(start: Vector2i, goal: Vector2i, goal_range: int = 0, max_climb: int = 0) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var start_tile: HexTile = get_tile(start)
	if start_tile == null or not start_tile.is_walkable():
		return empty
	if HexHelper.distance(start, goal) <= goal_range:
		return [start] as Array[Vector2i]

	# Cache hit?
	var cache_key: String = "%d,%d|%d,%d|%d|%d" % [start.x, start.y, goal.x, goal.y, goal_range, max_climb]
	if _path_cache.has(cache_key):
		return (_path_cache[cache_key] as Array[Vector2i]).duplicate()

	var heap := _PriorityQueue.new()
	heap.push(start, HexHelper.distance(start, goal))
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var in_open: Dictionary = {start: true}

	while not heap.is_empty():
		var current: Vector2i = heap.pop()
		in_open.erase(current)

		if HexHelper.distance(current, goal) <= goal_range:
			var path: Array[Vector2i] = _reconstruct_path(came_from, current)
			_path_cache[cache_key] = path
			return path.duplicate()

		for neighbor in get_walkable_neighbors(current, max_climb):
			var tentative_g: int = int(g_score[current]) + 1
			if tentative_g < int(g_score.get(neighbor, 0x7fffffff)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var f: int = tentative_g + HexHelper.distance(neighbor, goal)
				if not in_open.has(neighbor):
					heap.push(neighbor, f)
					in_open[neighbor] = true
				else:
					heap.push(neighbor, f)

	_path_cache[cache_key] = empty
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
