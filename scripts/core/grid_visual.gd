class_name GridVisual
extends Node3D
## Renders the hex grid in 3D using instanced GLB models for tiles.
## Supports elevation via cliff models and terrain-specific decorations.
## Handles hover highlights and tile click signals for the map editor.

## Reference to the HexGrid node.
@onready var hex_grid: HexGrid = %HexGrid

## -- Tile Model Paths --
@export var tile_model_path: String = "res://assets/models/tiles/hex_base/greentile.glb"
@export var ramp_corner_model_path: String = "res://assets/models/tiles/ramps/hex_ramp.obj"
@export var ramp_edge_model_path: String = "res://assets/models/tiles/ramps/hex_ramp_edge.obj"
@export var cliff_model_path: String = "res://assets/models/tiles/cliffs/threelayercliff.glb"

## Scale applied to all tile models to fit hex_size.
@export var tile_model_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

## Fallback height per cliff layer when no model is loaded.
@export var cliff_layer_height: float = 1.0

## -- Highlight --
var _hover_highlight: MeshInstance3D

## Tile mesh instances keyed by coord. Each is a wrapper Node3D.
var _tile_instances: Dictionary = {}  # Vector2i -> Node3D

## Currently hovered hex coordinate (null if none).
var _hovered_coord: Variant = null

## Preloaded tile resources.
var _tile_resource: Variant = null
var _ramp_corner_resource: Variant = null
var _ramp_edge_resource: Variant = null
var _cliff_resource: Variant = null

## Cached AABB height of the unscaled 3-layer cliff model (measured once).
var _cliff_model_height: float = 0.0

## Cached AABB height of the greentile model (floor tile thickness).
var _tile_model_height: float = 0.0


func _ready() -> void:
	_load_scale_config()
	_preload_resources()
	_measure_model_heights()
	_create_all_tiles()
	_create_highlight_meshes()


func _preload_resources() -> void:
	if ResourceLoader.exists(tile_model_path):
		_tile_resource = load(tile_model_path)
	if ResourceLoader.exists(ramp_corner_model_path):
		_ramp_corner_resource = load(ramp_corner_model_path)
	if ResourceLoader.exists(ramp_edge_model_path):
		_ramp_edge_resource = load(ramp_edge_model_path)
	if ResourceLoader.exists(cliff_model_path):
		_cliff_resource = load(cliff_model_path)


## Measure the natural heights of the tile and cliff models.
## The cliff sits ON TOP of the floor tile, not overlapping it.
func _measure_model_heights() -> void:
	# Measure greentile (floor) height.
	if _tile_resource != null:
		var temp: Node3D = _instantiate_resource(_tile_resource)
		if temp != null:
			var aabb: AABB = HexHelper._compute_combined_aabb(temp, temp)
			_tile_model_height = aabb.size.y if aabb.size.y > 0.001 else 0.1
			temp.queue_free()

	# Measure cliff model height.
	if _cliff_resource == null:
		_cliff_model_height = 3.0 * cliff_layer_height
	else:
		var temp: Node3D = _instantiate_resource(_cliff_resource)
		if temp == null:
			_cliff_model_height = 3.0 * cliff_layer_height
		else:
			var aabb: AABB = HexHelper._compute_combined_aabb(temp, temp)
			_cliff_model_height = aabb.size.y if aabb.size.y > 0.001 else 3.0 * cliff_layer_height
			temp.queue_free()

	# Sync elevation_height to HexGrid.
	# Cliff sits on top of the floor tile, so total elevated height =
	# tile_height + cliff_height. Per-level = total / 3.
	hex_grid.elevation_height = (_tile_model_height + _cliff_model_height) / 3.0


func _create_all_tiles() -> void:
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		var instance: Node3D = _create_tile_instance(tile, coord)
		if instance:
			add_child(instance)
			_tile_instances[coord] = instance


## Build the full visual for a single hex tile, including cliffs if elevated.
func _create_tile_instance(tile: HexTile, coord: Vector2i) -> Node3D:
	# XZ position from hex coords; wrapper sits at Y=0 always.
	var pixel: Vector2 = HexHelper.axial_to_pixel(coord, hex_grid.hex_size)
	var wrapper := Node3D.new()
	wrapper.position = Vector3(pixel.x, 0.0, pixel.y)

	if tile.is_ramp:
		var top_y: float = float(tile.elevation) * hex_grid.elevation_height
		var ramp_model: Node3D = _create_ramp_instance(tile)
		if ramp_model == null:
			ramp_model = _create_fallback_tile()
		ramp_model.scale = tile_model_scale
		ramp_model.rotation.y = deg_to_rad(30)
		ramp_model.position.y = top_y
		wrapper.add_child(ramp_model)
		HexHelper.auto_center_model(ramp_model)
		_apply_terrain_tint(ramp_model, tile)
	elif tile.elevation > 0 and _cliff_resource != null:
		# Elevated tile: cliff sits ON TOP of floor level, greentile on top of cliff.
		var cliff: Node3D = _create_cliff_column()
		cliff.position.y = _tile_model_height  # Cliff starts above the floor surface.
		wrapper.add_child(cliff)
		# Greentile on top of cliff.
		var top_y: float = _tile_model_height + _cliff_model_height
		var top_model: Node3D = _instantiate_resource(_tile_resource)
		if top_model == null:
			top_model = _create_fallback_tile()
		top_model.scale = tile_model_scale
		top_model.rotation.y = deg_to_rad(30)
		top_model.position.y = top_y
		wrapper.add_child(top_model)
		HexHelper.auto_center_model(top_model)
		_apply_terrain_tint(top_model, tile)
	else:
		# Ground-level tile: just greentile at Y=0.
		var top_model: Node3D = _instantiate_resource(_tile_resource)
		if top_model == null:
			top_model = _create_fallback_tile()
		top_model.scale = tile_model_scale
		top_model.rotation.y = deg_to_rad(30)
		top_model.position.y = 0.0
		wrapper.add_child(top_model)
		HexHelper.auto_center_model(top_model)
		_apply_terrain_tint(top_model, tile)

	# Procedural decorations on top.
	_add_terrain_decoration(wrapper, tile, coord)

	return wrapper


## Create a cliff column using the model as-is (no Y-scaling).
## Each cliff model represents a fixed number of layers at its natural size.
## Currently only threelayercliff.glb exists; 1-layer and 2-layer models
## will be added later and selected here based on elevation.
func _create_cliff_column() -> Node3D:
	var cliff: Node3D = _instantiate_resource(_cliff_resource)
	if cliff == null:
		return _create_fallback_cliff()

	cliff.scale = tile_model_scale
	cliff.rotation.y = deg_to_rad(30)
	cliff.position.y = 0.0
	HexHelper.auto_center_model(cliff)

	return cliff


## Fallback procedural cliff when no model is loaded.
func _create_fallback_cliff() -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = hex_grid.hex_size * 0.85
	mesh.bottom_radius = hex_grid.hex_size * 0.9
	mesh.height = _cliff_model_height if _cliff_model_height > 0.001 else 3.0
	mesh.radial_segments = 6
	mi.mesh = mesh
	mi.position.y = mesh.height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.38, 0.3)
	mi.set_surface_override_material(0, mat)
	return mi


func _create_ramp_instance(tile: HexTile) -> Node3D:
	var resource: Variant = _ramp_corner_resource
	if resource == null:
		resource = _ramp_edge_resource
	var instance: Node3D = _instantiate_resource(resource)
	if instance == null:
		return null
	if tile.ramp_exit_dir >= 0:
		var angle: float = tile.ramp_exit_dir * (TAU / 6.0)
		instance.rotation.y = angle
	return instance


func _instantiate_resource(res: Variant) -> Node3D:
	if res == null:
		return null
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		return mi
	return null


func _create_fallback_tile() -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = hex_grid.hex_size
	mesh.bottom_radius = hex_grid.hex_size
	mesh.height = 0.1
	mesh.radial_segments = 6
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.55, 0.3)
	mi.set_surface_override_material(0, mat)
	return mi


func _apply_terrain_tint(instance: Node3D, tile: HexTile) -> void:
	var tint: Color
	match tile.terrain:
		HexTile.TerrainType.GRASS:
			tint = Color(1.0, 1.0, 1.0)
		HexTile.TerrainType.MOUNTAIN:
			tint = Color(0.6, 0.55, 0.5)
		HexTile.TerrainType.FOREST:
			tint = Color(0.55, 0.75, 0.4)
		HexTile.TerrainType.HIVE:
			tint = Color(1.1, 0.95, 0.7)
		HexTile.TerrainType.WATER:
			tint = Color(0.4, 0.6, 0.9)
		_:
			tint = Color(1.0, 1.0, 1.0)

	# Elevation brightness boost on the top surface.
	if tile.elevation > 0 and not tile.is_ramp:
		tint *= Color(1.15, 1.15, 1.15)

	_traverse_and_tint(instance, tint)


func _add_terrain_decoration(wrapper: Node3D, tile: HexTile, coord: Vector2i) -> void:
	match tile.terrain:
		HexTile.TerrainType.MOUNTAIN:
			if not tile.is_ramp:
				_add_mountain_decoration(wrapper, tile, coord)
		HexTile.TerrainType.FOREST:
			_add_forest_decoration(wrapper, tile, coord)


func _add_mountain_decoration(wrapper: Node3D, tile: HexTile, coord: Vector2i) -> void:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = coord.x * 7919 + coord.y * 6271

	var rock_count: int = local_rng.randi_range(1, 2)
	for i: int in range(rock_count):
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = hex_grid.hex_size * (0.2 + local_rng.randf() * 0.15)
		mesh.top_radius = mesh.bottom_radius * (0.15 + local_rng.randf() * 0.25)
		mesh.height = hex_grid.hex_size * (0.5 + local_rng.randf() * 0.5)
		mesh.radial_segments = 5 + local_rng.randi_range(0, 2)
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		var shade: float = 0.35 + local_rng.randf() * 0.15
		mat.albedo_color = Color(shade + 0.05, shade, shade - 0.03)
		mi.set_surface_override_material(0, mat)
		var base_y: float = float(tile.elevation) * hex_grid.elevation_height
		mi.position.y = base_y + mesh.height * 0.5
		var offset_angle: float = local_rng.randf() * TAU
		var offset_dist: float = local_rng.randf() * hex_grid.hex_size * 0.25
		mi.position.x = cos(offset_angle) * offset_dist
		mi.position.z = sin(offset_angle) * offset_dist
		mi.rotation.y = local_rng.randf() * TAU
		wrapper.add_child(mi)


func _add_forest_decoration(wrapper: Node3D, tile: HexTile, coord: Vector2i) -> void:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = coord.x * 4507 + coord.y * 3571

	var tree_count: int = local_rng.randi_range(1, 3)
	var base_y: float = float(tile.elevation) * hex_grid.elevation_height

	for i: int in range(tree_count):
		var tree := Node3D.new()

		var trunk_mi := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.025
		trunk_mesh.bottom_radius = 0.045
		trunk_mesh.height = 0.25 + local_rng.randf() * 0.2
		trunk_mesh.radial_segments = 5
		trunk_mi.mesh = trunk_mesh
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Color(0.4, 0.3, 0.2)
		trunk_mi.set_surface_override_material(0, trunk_mat)
		trunk_mi.position.y = trunk_mesh.height * 0.5
		tree.add_child(trunk_mi)

		var canopy_mi := MeshInstance3D.new()
		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = 0.1 + local_rng.randf() * 0.08
		canopy_mesh.height = canopy_mesh.radius * 2.0
		canopy_mesh.radial_segments = 8
		canopy_mesh.rings = 4
		canopy_mi.mesh = canopy_mesh
		var canopy_mat := StandardMaterial3D.new()
		canopy_mat.albedo_color = Color(
			0.15 + local_rng.randf() * 0.15,
			0.4 + local_rng.randf() * 0.25,
			0.1 + local_rng.randf() * 0.1
		)
		canopy_mi.set_surface_override_material(0, canopy_mat)
		canopy_mi.position.y = trunk_mesh.height + canopy_mesh.radius * 0.6
		tree.add_child(canopy_mi)

		var offset_angle: float = local_rng.randf() * TAU
		var offset_dist: float = local_rng.randf() * hex_grid.hex_size * 0.35
		tree.position.x = cos(offset_angle) * offset_dist
		tree.position.z = sin(offset_angle) * offset_dist
		tree.position.y = base_y

		wrapper.add_child(tree)


func _traverse_and_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var original: Material = mi.mesh.surface_get_material(i)
			if original is StandardMaterial3D:
				var mat: StandardMaterial3D = (original as StandardMaterial3D).duplicate()
				mat.albedo_color *= tint
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_traverse_and_tint(child, tint)


func _create_highlight_meshes() -> void:
	_hover_highlight = _create_hex_disc(Color(1.0, 0.85, 0.3, 0.3))
	_hover_highlight.visible = false
	add_child(_hover_highlight)


func _create_hex_disc(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = hex_grid.hex_size * 0.95
	mesh.bottom_radius = hex_grid.hex_size * 0.95
	mesh.height = 0.05
	mesh.radial_segments = 6
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.set_surface_override_material(0, mat)
	return mi


# -- Map editor support --

## Rebuild a single tile's visual (used by map editor for live updates).
func rebuild_tile(coord: Vector2i) -> void:
	if _tile_instances.has(coord):
		var old: Node3D = _tile_instances[coord]
		old.queue_free()
		_tile_instances.erase(coord)

	var tile: HexTile = hex_grid.get_tile(coord)
	if tile == null:
		return
	var instance: Node3D = _create_tile_instance(tile, coord)
	if instance:
		add_child(instance)
		_tile_instances[coord] = instance


## Rebuild all tile visuals (used after map load).
func rebuild_all_tiles() -> void:
	for coord: Vector2i in _tile_instances:
		var old: Node3D = _tile_instances[coord]
		old.queue_free()
	_tile_instances.clear()
	_create_all_tiles()


# -- Scale editor support --

func _load_scale_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://config/model_scales.cfg") == OK:
		var s: float = cfg.get_value("tile", "scale", tile_model_scale.x)
		tile_model_scale = Vector3(s, s, s)


func update_tile_scale(new_scale: Vector3) -> void:
	tile_model_scale = new_scale
	for coord: Vector2i in _tile_instances:
		var wrapper: Node3D = _tile_instances[coord]
		if wrapper.get_child_count() > 0:
			var model: Node3D = wrapper.get_child(0)
			model.scale = new_scale
			HexHelper.auto_center_model(model)


func _process(_delta: float) -> void:
	_handle_mouse()


func _handle_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		if _hovered_coord != null:
			_hovered_coord = null
			_hover_highlight.visible = false
			hex_grid.tile_unhovered.emit()
		return

	var hex_coord: Vector2i = hex_grid.world_to_hex(world_pos)

	if hex_grid.has_tile(hex_coord):
		if _hovered_coord != hex_coord:
			_hovered_coord = hex_coord
			hex_grid.tile_hovered.emit(hex_coord)
		var tile_pos: Vector3 = hex_grid.hex_to_world(hex_coord)
		_hover_highlight.position = tile_pos + Vector3(0, 0.06, 0)
		_hover_highlight.visible = true
	else:
		if _hovered_coord != null:
			_hovered_coord = null
			_hover_highlight.visible = false
			hex_grid.tile_unhovered.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_coord != null:
				var coord: Vector2i = _hovered_coord as Vector2i
				hex_grid.tile_clicked.emit(coord)
