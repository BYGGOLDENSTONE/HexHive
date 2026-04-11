class_name MapGenerator
extends RefCounted
## Procedural map generator for Thronefall-style hex maps.
## Creates a central plateau with 3 path corridors, mountain barriers,
## forest clusters, and flower patches. Validates connectivity via BFS.


## Default configuration values.
const DEFAULTS: Dictionary = {
	"seed": 0,
	"plateau_radius": 4,
	"path_count": 3,
	"path_width": 2,
	"choke_width": 1,
	"choke_distance": 7,
	"noise_frequency": 0.12,
	"noise_threshold": 0.45,
	"forest_cluster_count": 8,
	"forest_cluster_radius_min": 2,
	"forest_cluster_radius_max": 4,
	"flower_patch_count": 6,
	"flower_patch_radius": 2,
}


## Generate the full map layout. Mutates tiles in-place.
## Returns the effective seed used for generation.
static func generate(tiles: Dictionary, config: Dictionary, _hex_size: float, map_radius: int) -> int:
	var cfg: Dictionary = DEFAULTS.duplicate()
	cfg.merge(config, true)

	var rng := RandomNumberGenerator.new()
	var effective_seed: int = cfg["seed"] as int
	if effective_seed == 0:
		effective_seed = randi()
	rng.seed = effective_seed

	# Step 1: Define path directions (120 degrees apart, random rotation).
	var path_dirs: Array[int] = _pick_path_directions(rng, cfg["path_count"] as int)

	# Step 2: Mark path corridor tiles.
	var path_set: Dictionary = {}  # Vector2i -> true
	_carve_plateau(tiles, path_set, cfg)
	_carve_corridors(tiles, path_set, path_dirs, cfg, map_radius)

	# Step 3: Fill non-path tiles with MOUNTAIN.
	_fill_mountains(tiles, path_set)

	# Step 4: Noise-based mountain edge variation.
	_apply_noise_erosion(tiles, path_set, rng, cfg)

	# Step 5: Set elevation on plateau tiles.
	_set_plateau_elevation(tiles, cfg)

	# Step 6: Place ramps at plateau exits.
	_place_ramps(tiles, path_dirs, cfg)

	# Step 7: Place forest clusters.
	_place_forests(tiles, rng, cfg, map_radius)

	# Step 8: Place flower patches along paths.
	_place_flowers(tiles, rng, path_dirs, cfg, map_radius)

	# Step 9: Set hive tile.
	if tiles.has(Vector2i.ZERO):
		tiles[Vector2i.ZERO].terrain = HexTile.TerrainType.HIVE
		tiles[Vector2i.ZERO].elevation = 1

	# Step 10: Guarantee spawn points at path exits.
	_ensure_spawn_points(tiles, path_dirs, cfg, map_radius)

	# Step 11: Verify and repair connectivity.
	_verify_and_repair_connectivity(tiles, path_dirs, map_radius)

	return effective_seed


# -- Step 1: Path Directions --

static func _pick_path_directions(rng: RandomNumberGenerator, path_count: int) -> Array[int]:
	var base_rotation: int = rng.randi_range(0, 5)
	var dirs: Array[int] = []
	# Evenly spaced directions: for 3 paths, step by 2 (120 degrees).
	@warning_ignore("integer_division")
	var step: int = 6 / path_count
	for i in range(path_count):
		dirs.append((base_rotation + i * step) % 6)
	return dirs


# -- Step 2: Carve Plateau + Corridors --

static func _carve_plateau(tiles: Dictionary, path_set: Dictionary, cfg: Dictionary) -> void:
	var plateau_radius: int = cfg["plateau_radius"] as int
	var plateau_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(Vector2i.ZERO, plateau_radius)
	for coord in plateau_hexes:
		if tiles.has(coord):
			path_set[coord] = true


static func _carve_corridors(tiles: Dictionary, path_set: Dictionary, path_dirs: Array[int], cfg: Dictionary, map_radius: int) -> void:
	var plateau_radius: int = cfg["plateau_radius"] as int
	var path_width: int = cfg["path_width"] as int
	var choke_width: int = cfg["choke_width"] as int
	var choke_distance: int = cfg["choke_distance"] as int

	for dir_idx: int in path_dirs:
		var dir_vec: Vector2i = HexHelper.DIRECTIONS[dir_idx]
		for d: int in range(1, map_radius + 1):
			var spine_hex: Vector2i = dir_vec * d
			if not tiles.has(spine_hex):
				continue

			# Determine corridor half-width at this distance.
			var half_width: int
			if d <= plateau_radius:
				half_width = path_width  # Inside plateau area
			elif d >= choke_distance - 1 and d <= choke_distance + 1:
				half_width = choke_width  # Narrow choke
			else:
				half_width = path_width  # Normal width

			# Mark spine and neighbors within half_width as path.
			var corridor_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(spine_hex, half_width)
			for ch: Vector2i in corridor_hexes:
				if tiles.has(ch):
					path_set[ch] = true


# -- Step 3: Fill Mountains --

static func _fill_mountains(tiles: Dictionary, path_set: Dictionary) -> void:
	for coord: Vector2i in tiles:
		if not path_set.has(coord):
			tiles[coord].terrain = HexTile.TerrainType.MOUNTAIN


# -- Step 4: Noise Erosion --

static func _apply_noise_erosion(tiles: Dictionary, path_set: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = cfg["noise_frequency"] as float
	var threshold: float = cfg["noise_threshold"] as float

	# Pass 1: Erode some GRASS tiles bordering mountains into MOUNTAIN.
	var to_mountain: Array[Vector2i] = []
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		if tile.terrain != HexTile.TerrainType.GRASS:
			continue
		if not _borders_terrain(tiles, coord, HexTile.TerrainType.MOUNTAIN):
			continue
		var noise_val: float = noise.get_noise_2d(float(coord.x), float(coord.y))
		if noise_val > threshold:
			to_mountain.append(coord)

	for coord: Vector2i in to_mountain:
		tiles[coord].terrain = HexTile.TerrainType.MOUNTAIN
		path_set.erase(coord)

	# Pass 2: Convert some MOUNTAIN tiles bordering GRASS into GRASS (alcoves).
	var to_grass: Array[Vector2i] = []
	var alcove_threshold: float = -threshold * 0.6
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		if tile.terrain != HexTile.TerrainType.MOUNTAIN:
			continue
		if not _borders_terrain(tiles, coord, HexTile.TerrainType.GRASS):
			continue
		var noise_val: float = noise.get_noise_2d(float(coord.x) + 100.0, float(coord.y) + 100.0)
		if noise_val < alcove_threshold:
			to_grass.append(coord)

	for coord: Vector2i in to_grass:
		tiles[coord].terrain = HexTile.TerrainType.GRASS
		path_set[coord] = true


static func _borders_terrain(tiles: Dictionary, coord: Vector2i, terrain: HexTile.TerrainType) -> bool:
	for n: Vector2i in HexHelper.get_neighbors(coord):
		if tiles.has(n) and tiles[n].terrain == terrain:
			return true
	return false


# -- Step 5: Plateau Elevation --

static func _set_plateau_elevation(tiles: Dictionary, cfg: Dictionary) -> void:
	var plateau_radius: int = cfg["plateau_radius"] as int
	var plateau_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(Vector2i.ZERO, plateau_radius)
	for coord: Vector2i in plateau_hexes:
		if tiles.has(coord):
			var tile: HexTile = tiles[coord]
			if tile.terrain != HexTile.TerrainType.MOUNTAIN:
				tile.elevation = 1


# -- Step 6: Ramps --

static func _place_ramps(tiles: Dictionary, path_dirs: Array[int], cfg: Dictionary) -> void:
	var plateau_radius: int = cfg["plateau_radius"] as int

	for dir_idx: int in path_dirs:
		var dir_vec: Vector2i = HexHelper.DIRECTIONS[dir_idx]
		# Ramp sits at the edge of the plateau along this path spine.
		var ramp_coord: Vector2i = dir_vec * plateau_radius
		if tiles.has(ramp_coord):
			var tile: HexTile = tiles[ramp_coord]
			tile.is_ramp = true
			tile.ramp_exit_dir = dir_idx
			tile.elevation = 1
			# Ensure the tile just outside the ramp is walkable ground level.
			var outer_coord: Vector2i = ramp_coord + dir_vec
			if tiles.has(outer_coord):
				var outer: HexTile = tiles[outer_coord]
				if outer.terrain == HexTile.TerrainType.MOUNTAIN:
					outer.terrain = HexTile.TerrainType.GRASS
				outer.elevation = 0


# -- Step 7: Forests --

static func _place_forests(tiles: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, map_radius: int) -> void:
	var cluster_count: int = cfg["forest_cluster_count"] as int
	var cluster_min: int = cfg["forest_cluster_radius_min"] as int
	var cluster_max: int = cfg["forest_cluster_radius_max"] as int

	# Part A: Path-edge forests (GRASS tiles adjacent to 2+ MOUNTAIN tiles).
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		if tile.terrain != HexTile.TerrainType.GRASS:
			continue
		if tile.elevation > 0:
			continue  # No forests on plateau
		var mountain_neighbors: int = 0
		for n: Vector2i in HexHelper.get_neighbors(coord):
			if tiles.has(n) and tiles[n].terrain == HexTile.TerrainType.MOUNTAIN:
				mountain_neighbors += 1
		if mountain_neighbors >= 2 and rng.randf() < 0.6:
			tile.terrain = HexTile.TerrainType.FOREST

	# Part B: Random forest clusters in mid-range.
	var grass_candidates: Array[Vector2i] = []
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		var dist: int = HexHelper.distance(Vector2i.ZERO, coord)
		if tile.terrain == HexTile.TerrainType.GRASS and dist >= 6 and dist <= map_radius - 4 and tile.elevation == 0:
			grass_candidates.append(coord)

	for _i: int in range(cluster_count):
		if grass_candidates.is_empty():
			break
		var center_coord: Vector2i = grass_candidates[rng.randi() % grass_candidates.size()]
		var cluster_radius: int = rng.randi_range(cluster_min, cluster_max)
		var cluster_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(center_coord, cluster_radius)
		for ch: Vector2i in cluster_hexes:
			if tiles.has(ch):
				var ct: HexTile = tiles[ch]
				if ct.terrain == HexTile.TerrainType.GRASS and ct.elevation == 0:
					if rng.randf() < 0.55:
						ct.terrain = HexTile.TerrainType.FOREST


# -- Step 8: Flowers --

static func _place_flowers(tiles: Dictionary, rng: RandomNumberGenerator, path_dirs: Array[int], cfg: Dictionary, map_radius: int) -> void:
	var patch_count: int = cfg["flower_patch_count"] as int
	var patch_radius: int = cfg["flower_patch_radius"] as int
	var choke_distance: int = cfg["choke_distance"] as int

	for _i: int in range(patch_count):
		# Pick a random path.
		var dir_idx: int = path_dirs[rng.randi() % path_dirs.size()]
		var dir_vec: Vector2i = HexHelper.DIRECTIONS[dir_idx]
		# Pick a distance along the path (past choke, before edge).
		var dist: int = rng.randi_range(choke_distance + 2, map_radius - 3)
		var spine_hex: Vector2i = dir_vec * dist
		if not tiles.has(spine_hex):
			continue
		# Offset slightly from spine for variety.
		var offset_dir: int = rng.randi_range(0, 5)
		var patch_center: Vector2i = spine_hex + HexHelper.DIRECTIONS[offset_dir] * rng.randi_range(0, 1)
		var patch_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(patch_center, patch_radius)
		for ph: Vector2i in patch_hexes:
			if tiles.has(ph):
				var ft: HexTile = tiles[ph]
				if ft.terrain == HexTile.TerrainType.GRASS and ft.elevation == 0:
					if rng.randf() < 0.45:
						ft.terrain = HexTile.TerrainType.FLOWER


# -- Step 10: Spawn Point Guarantee --

static func _ensure_spawn_points(tiles: Dictionary, path_dirs: Array[int], cfg: Dictionary, map_radius: int) -> void:
	var path_width: int = cfg["path_width"] as int
	var spawn_ring: Array[Vector2i] = HexHelper.get_hex_ring(Vector2i.ZERO, map_radius)

	for dir_idx: int in path_dirs:
		var dir_vec: Vector2i = HexHelper.DIRECTIONS[dir_idx]
		var path_end: Vector2i = dir_vec * map_radius
		# Ensure tiles near path end on spawn ring are walkable.
		for coord: Vector2i in spawn_ring:
			if HexHelper.distance(coord, path_end) <= path_width + 1:
				if tiles.has(coord):
					var tile: HexTile = tiles[coord]
					if tile.terrain == HexTile.TerrainType.MOUNTAIN:
						tile.terrain = HexTile.TerrainType.GRASS
					tile.elevation = 0


# -- Step 11: Connectivity Verification --

static func _verify_and_repair_connectivity(tiles: Dictionary, path_dirs: Array[int], map_radius: int) -> void:
	# BFS flood fill from center.
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	visited[Vector2i.ZERO] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for n: Vector2i in HexHelper.get_neighbors(current):
			if visited.has(n):
				continue
			if not tiles.has(n):
				continue
			var tile: HexTile = tiles[n]
			if tile.terrain == HexTile.TerrainType.MOUNTAIN or tile.terrain == HexTile.TerrainType.WATER:
				continue
			visited[n] = true
			queue.append(n)

	# Check that spawn exits are reachable.
	var spawn_ring: Array[Vector2i] = HexHelper.get_hex_ring(Vector2i.ZERO, map_radius)
	for dir_idx: int in path_dirs:
		var dir_vec: Vector2i = HexHelper.DIRECTIONS[dir_idx]
		var path_end: Vector2i = dir_vec * map_radius
		# Find a walkable spawn near path end.
		var found_reachable: bool = false
		for coord: Vector2i in spawn_ring:
			if HexHelper.distance(coord, path_end) <= 3:
				if visited.has(coord):
					found_reachable = true
					break

		if not found_reachable:
			# Repair: carve a line from the nearest reachable tile toward path end.
			_repair_path_to_target(tiles, visited, path_end)


static func _repair_path_to_target(tiles: Dictionary, visited: Dictionary, target: Vector2i) -> void:
	# Find closest reachable tile to the target.
	var best_coord: Vector2i = Vector2i.ZERO
	var best_dist: int = 0x7fffffff
	for coord: Variant in visited:
		var d: int = HexHelper.distance(coord as Vector2i, target)
		if d < best_dist:
			best_dist = d
			best_coord = coord as Vector2i

	# Carve a line of GRASS from best_coord to target.
	var line: Array[Vector2i] = HexHelper.get_line(best_coord, target)
	for coord: Vector2i in line:
		if tiles.has(coord):
			var tile: HexTile = tiles[coord]
			if tile.terrain == HexTile.TerrainType.MOUNTAIN:
				tile.terrain = HexTile.TerrainType.GRASS
				tile.elevation = 0
