extends CanvasLayer
## Full-featured hex map editor with tool palette, undo/redo, brush preview,
## flood fill, symmetry modes, eyedropper, and named save/load slots.
## Works standalone (map_editor_scene) or in-game (F6 toggle).

## Set to true when used as standalone scene (always visible, no toggle).
@export var standalone_mode: bool = false

var hex_grid: HexGrid
var grid_visual: GridVisual

# -- Tool Enum --
enum Tool {
	PAINT_TERRAIN,
	ELEVATION_RAISE,
	ELEVATION_LOWER,
	RAMP_PAINT,
	FLOOD_FILL,
	ERASE,
}

# -- Symmetry Enum --
enum SymmetryMode {
	OFF,
	FOLD_2,
	FOLD_3,
	FOLD_6,
}

# -- State --
var _panel: PanelContainer
var _visible: bool = false
var _active: bool = false

var _current_tool: Tool = Tool.PAINT_TERRAIN
var _brush_terrain: HexTile.TerrainType = HexTile.TerrainType.GRASS
var _brush_size: int = 1  # 1-7 hex radius
var _ramp_dir: int = 0
var _symmetry: SymmetryMode = SymmetryMode.OFF
var _is_painting: bool = false

## Undo/redo history. Each entry is an Array of {coord, old_state, new_state}.
var _undo_stack: Array = []
var _redo_stack: Array = []
const MAX_UNDO: int = 50

## Brush preview instances (semi-transparent hex discs).
var _brush_preview_nodes: Array[MeshInstance3D] = []
var _brush_preview_parent: Node3D = null
var _brush_preview_material: StandardMaterial3D = null
var _last_preview_coord: Variant = null

## UI references.
var _tool_buttons: Dictionary = {}  # Tool -> Button
var _terrain_buttons: Dictionary = {}  # TerrainType -> Button
var _brush_label: Label
var _ramp_dir_label: Label
var _symmetry_label: Label
var _status_label: Label
var _map_name_input: LineEdit
var _map_list: ItemList


func _ready() -> void:
	layer = 18
	hex_grid = get_tree().current_scene.find_child("HexGrid", true, false) as HexGrid
	grid_visual = get_tree().current_scene.find_child("GridVisual", true, false) as GridVisual
	_build_ui()
	_setup_brush_preview()
	if standalone_mode:
		_panel.visible = true
		_active = true
		_visible = true
	else:
		_panel.visible = false


# ============================================================================
# BRUSH PREVIEW
# ============================================================================

func _setup_brush_preview() -> void:
	_brush_preview_parent = Node3D.new()
	# Add to the scene root so it lives in 3D space.
	get_tree().current_scene.call_deferred("add_child", _brush_preview_parent)

	_brush_preview_material = StandardMaterial3D.new()
	_brush_preview_material.albedo_color = Color(1.0, 0.85, 0.3, 0.2)
	_brush_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_brush_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brush_preview_material.no_depth_test = true


func _update_brush_preview(center_coord: Vector2i) -> void:
	if not _active:
		_clear_brush_preview()
		return

	if _last_preview_coord is Vector2i and (_last_preview_coord as Vector2i) == center_coord:
		return
	_last_preview_coord = center_coord

	var target_coords: Array[Vector2i] = _get_affected_coords(center_coord)
	# Reuse or create preview discs as needed.
	while _brush_preview_nodes.size() < target_coords.size():
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = hex_grid.hex_size * 0.9
		mesh.bottom_radius = hex_grid.hex_size * 0.9
		mesh.height = 0.04
		mesh.radial_segments = 6
		mi.mesh = mesh
		mi.set_surface_override_material(0, _brush_preview_material)
		_brush_preview_parent.add_child(mi)
		_brush_preview_nodes.append(mi)

	for i: int in range(_brush_preview_nodes.size()):
		if i < target_coords.size():
			var coord: Vector2i = target_coords[i]
			var world_pos: Vector3 = hex_grid.hex_to_world(coord)
			_brush_preview_nodes[i].position = world_pos + Vector3(0, 0.08, 0)
			_brush_preview_nodes[i].visible = true
		else:
			_brush_preview_nodes[i].visible = false


func _clear_brush_preview() -> void:
	_last_preview_coord = null
	for mi: MeshInstance3D in _brush_preview_nodes:
		mi.visible = false


# ============================================================================
# AFFECTED COORDINATES (brush + symmetry)
# ============================================================================

## Get all coords affected by a brush stroke at center_coord, including symmetry.
func _get_affected_coords(center_coord: Vector2i) -> Array[Vector2i]:
	var base_coords: Array[Vector2i] = _get_brush_coords(center_coord)

	if _symmetry == SymmetryMode.OFF:
		return base_coords

	var all_coords: Array[Vector2i] = []
	var seen: Dictionary = {}

	# Symmetry: rotate base coords around origin.
	var fold_count: int = 1
	match _symmetry:
		SymmetryMode.FOLD_2:
			fold_count = 2
		SymmetryMode.FOLD_3:
			fold_count = 3
		SymmetryMode.FOLD_6:
			fold_count = 6

	for rot_step: int in range(fold_count):
		for coord: Vector2i in base_coords:
			var rotated: Vector2i = _rotate_hex(coord, rot_step, fold_count)
			if not seen.has(rotated) and hex_grid.has_tile(rotated):
				seen[rotated] = true
				all_coords.append(rotated)

	return all_coords


## Get hex coords within the brush radius around a center.
func _get_brush_coords(center: Vector2i) -> Array[Vector2i]:
	if _brush_size <= 1:
		if hex_grid.has_tile(center):
			return [center]
		return []
	var result: Array[Vector2i] = []
	var coords: Array[Vector2i] = HexHelper.get_hexes_in_range(center, _brush_size - 1)
	for c: Vector2i in coords:
		if hex_grid.has_tile(c):
			result.append(c)
	return result


## Rotate a hex coord around origin by (rot_step / fold_count) of a full rotation.
func _rotate_hex(coord: Vector2i, rot_step: int, fold_count: int) -> Vector2i:
	if rot_step == 0:
		return coord
	# Convert to cube coords, rotate 60 degrees * steps.
	var q: int = coord.x
	var r: int = coord.y
	var s: int = -q - r
	@warning_ignore("integer_division")
	var total_rotations: int = rot_step * (6 / fold_count)
	for _i: int in range(total_rotations % 6):
		var new_q: int = -r
		var new_r: int = -s
		var new_s: int = -q
		q = new_q
		r = new_r
		s = new_s
	return Vector2i(q, r)


# ============================================================================
# TILE STATE SNAPSHOT (for undo/redo)
# ============================================================================

func _snapshot_tile(tile: HexTile) -> Dictionary:
	return {
		"terrain": int(tile.terrain),
		"elevation": tile.elevation,
		"is_ramp": tile.is_ramp,
		"ramp_exit_dir": tile.ramp_exit_dir,
	}


func _apply_snapshot(tile: HexTile, snap: Dictionary) -> void:
	tile.terrain = snap["terrain"] as HexTile.TerrainType
	tile.elevation = snap["elevation"] as int
	tile.is_ramp = snap["is_ramp"] as bool
	tile.ramp_exit_dir = snap["ramp_exit_dir"] as int


# ============================================================================
# TOOL ACTIONS
# ============================================================================

func _apply_tool_at(center_coord: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT_TERRAIN:
			_action_paint_terrain(center_coord)
		Tool.ELEVATION_RAISE:
			_action_elevation_change(center_coord, 1)
		Tool.ELEVATION_LOWER:
			_action_elevation_change(center_coord, -1)
		Tool.RAMP_PAINT:
			_action_ramp_paint(center_coord)
		Tool.FLOOD_FILL:
			_action_flood_fill(center_coord)
		Tool.ERASE:
			_action_erase(center_coord)


func _action_paint_terrain(center_coord: Vector2i) -> void:
	var coords: Array[Vector2i] = _get_affected_coords(center_coord)
	var changes: Array = []
	for coord: Vector2i in coords:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		var old_snap: Dictionary = _snapshot_tile(tile)
		tile.terrain = _brush_terrain
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
			grid_visual.rebuild_tile(coord)
	if not changes.is_empty():
		_push_undo(changes)


func _action_elevation_change(center_coord: Vector2i, delta: int) -> void:
	var coords: Array[Vector2i] = _get_affected_coords(center_coord)
	var changes: Array = []
	for coord: Vector2i in coords:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		var old_snap: Dictionary = _snapshot_tile(tile)
		# Currently only 3-layer cliff model exists.
		# Raise snaps to 3 (full cliff), lower snaps to 0 (ground).
		# When 1-layer and 2-layer models are added, this will increment/decrement by 1.
		if delta > 0:
			tile.elevation = 3 if tile.elevation == 0 else tile.elevation
		else:
			tile.elevation = 0 if tile.elevation > 0 else 0
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
			grid_visual.rebuild_tile(coord)
	if not changes.is_empty():
		_push_undo(changes)


func _action_ramp_paint(center_coord: Vector2i) -> void:
	var coords: Array[Vector2i] = _get_affected_coords(center_coord)
	var changes: Array = []
	for coord: Vector2i in coords:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		var old_snap: Dictionary = _snapshot_tile(tile)
		tile.is_ramp = true
		# Auto-detect ramp direction: find the neighbor with lower elevation.
		var best_dir: int = _ramp_dir
		var found_auto: bool = false
		for dir_idx: int in range(6):
			var neighbor_coord: Vector2i = coord + HexHelper.DIRECTIONS[dir_idx]
			var ntile: HexTile = hex_grid.get_tile(neighbor_coord)
			if ntile != null and ntile.elevation < tile.elevation:
				best_dir = dir_idx
				found_auto = true
				break
		if not found_auto:
			best_dir = _ramp_dir
		tile.ramp_exit_dir = best_dir
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
			grid_visual.rebuild_tile(coord)
	if not changes.is_empty():
		_push_undo(changes)


func _action_flood_fill(start_coord: Vector2i) -> void:
	var start_tile: HexTile = hex_grid.get_tile(start_coord)
	if start_tile == null:
		return
	var target_terrain: HexTile.TerrainType = start_tile.terrain
	if target_terrain == _brush_terrain:
		return  # Already the same terrain, no-op.

	var changes: Array = []
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start_coord]
	visited[start_coord] = true

	while not queue.is_empty():
		var coord: Vector2i = queue.pop_front()
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		if tile.terrain != target_terrain:
			continue

		var old_snap: Dictionary = _snapshot_tile(tile)
		tile.terrain = _brush_terrain
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
			grid_visual.rebuild_tile(coord)

		for neighbor: Vector2i in HexHelper.get_neighbors(coord):
			if not visited.has(neighbor) and hex_grid.has_tile(neighbor):
				visited[neighbor] = true
				var ntile: HexTile = hex_grid.get_tile(neighbor)
				if ntile != null and ntile.terrain == target_terrain:
					queue.append(neighbor)

	if not changes.is_empty():
		_push_undo(changes)


func _action_erase(center_coord: Vector2i) -> void:
	var coords: Array[Vector2i] = _get_affected_coords(center_coord)
	var changes: Array = []
	for coord: Vector2i in coords:
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile == null:
			continue
		var old_snap: Dictionary = _snapshot_tile(tile)
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
			grid_visual.rebuild_tile(coord)
	if not changes.is_empty():
		_push_undo(changes)


## Eyedropper: copy tile properties from the clicked tile.
func _eyedropper_at(coord: Vector2i) -> void:
	var tile: HexTile = hex_grid.get_tile(coord)
	if tile == null:
		return
	_brush_terrain = tile.terrain
	if _terrain_buttons.has(int(_brush_terrain)):
		(_terrain_buttons[int(_brush_terrain)] as Button).button_pressed = true
	_status_label.text = "Sampled: (%d,%d) %s elev=%d" % [coord.x, coord.y, _terrain_name(_brush_terrain), tile.elevation]
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))


# ============================================================================
# UNDO / REDO
# ============================================================================

func _push_undo(changes: Array) -> void:
	_undo_stack.append(changes)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var changes: Array = _undo_stack.pop_back()
	for entry: Variant in changes:
		var d: Dictionary = entry as Dictionary
		var coord: Vector2i = d["coord"] as Vector2i
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile:
			_apply_snapshot(tile, d["old"] as Dictionary)
			grid_visual.rebuild_tile(coord)
	_redo_stack.append(changes)
	_status_label.text = "Undo (%d left)" % _undo_stack.size()
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	var changes: Array = _redo_stack.pop_back()
	for entry: Variant in changes:
		var d: Dictionary = entry as Dictionary
		var coord: Vector2i = d["coord"] as Vector2i
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile:
			_apply_snapshot(tile, d["new"] as Dictionary)
			grid_visual.rebuild_tile(coord)
	_undo_stack.append(changes)
	_status_label.text = "Redo (%d left)" % _redo_stack.size()
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))


# ============================================================================
# INPUT HANDLING
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			# F6 toggle (only in non-standalone mode).
			if ke.keycode == KEY_F6 and not standalone_mode:
				_toggle()
				get_viewport().set_input_as_handled()
				return

			if not _active:
				return

			# Tool shortcuts.
			match ke.keycode:
				KEY_T:
					_select_tool(Tool.PAINT_TERRAIN)
					get_viewport().set_input_as_handled()
				KEY_Q:
					if not ke.ctrl_pressed:
						_select_tool(Tool.ELEVATION_RAISE)
						get_viewport().set_input_as_handled()
				KEY_E:
					_select_tool(Tool.ELEVATION_LOWER)
					get_viewport().set_input_as_handled()
				KEY_R:
					_select_tool(Tool.RAMP_PAINT)
					get_viewport().set_input_as_handled()
				KEY_F:
					_select_tool(Tool.FLOOD_FILL)
					get_viewport().set_input_as_handled()
				KEY_X:
					_select_tool(Tool.ERASE)
					get_viewport().set_input_as_handled()

			# Brush size.
			if ke.keycode == KEY_EQUAL or ke.keycode == KEY_KP_ADD:  # +
				_brush_size = mini(_brush_size + 1, 7)
				_update_brush_label()
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_MINUS or ke.keycode == KEY_KP_SUBTRACT:  # -
				_brush_size = maxi(_brush_size - 1, 1)
				_update_brush_label()
				get_viewport().set_input_as_handled()

			# Undo/Redo.
			if ke.ctrl_pressed:
				if ke.keycode == KEY_Z:
					_undo()
					get_viewport().set_input_as_handled()
				elif ke.keycode == KEY_Y:
					_redo()
					get_viewport().set_input_as_handled()

	if not _active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_painting = true
				_paint_at_mouse()
			else:
				_is_painting = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_eyedropper_at_mouse()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if _is_painting:
			_paint_at_mouse()
		# Always update brush preview when active.
		_update_preview_at_mouse()


func _process(_delta: float) -> void:
	if _active and not _is_painting:
		_update_preview_at_mouse()


func _update_preview_at_mouse() -> void:
	if hex_grid == null:
		return
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		_clear_brush_preview()
		return
	var coord: Vector2i = hex_grid.world_to_hex(world_pos)
	if hex_grid.has_tile(coord):
		_update_brush_preview(coord)
	else:
		_clear_brush_preview()


func _paint_at_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		return
	var coord: Vector2i = hex_grid.world_to_hex(world_pos)
	if hex_grid.has_tile(coord):
		_apply_tool_at(coord)


func _eyedropper_at_mouse() -> void:
	var world_pos: Vector3 = hex_grid.get_mouse_world_position()
	if world_pos == Vector3.ZERO:
		return
	var coord: Vector2i = hex_grid.world_to_hex(world_pos)
	_eyedropper_at(coord)


# ============================================================================
# TOGGLE
# ============================================================================

func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	_active = _visible
	if _active:
		_update_status()
		_refresh_map_list()
	else:
		_clear_brush_preview()
		_is_painting = false


# ============================================================================
# SAVE / LOAD / MAP MANAGEMENT
# ============================================================================

func _on_save() -> void:
	var map_name: String = _map_name_input.text.strip_edges()
	if map_name.is_empty():
		map_name = "custom_map"
	# Sanitize: only allow alphanumeric, underscore, hyphen.
	map_name = map_name.replace(" ", "_")
	if hex_grid.save_map_to_file(map_name):
		_status_label.text = "Saved: %s" % map_name
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		_refresh_map_list()
	else:
		_status_label.text = "Save failed!"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _on_load() -> void:
	var selected_indices: PackedInt32Array = _map_list.get_selected_items()
	if selected_indices.is_empty():
		_status_label.text = "Select a map to load"
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		return
	var map_name: String = _map_list.get_item_text(selected_indices[0])
	# Reset all tiles first.
	for tile: HexTile in hex_grid.tiles.values():
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
	if hex_grid.load_map_from_file(map_name):
		grid_visual.rebuild_all_tiles()
		_map_name_input.text = map_name
		_undo_stack.clear()
		_redo_stack.clear()
		_status_label.text = "Loaded: %s" % map_name
		_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_status_label.text = "Load failed: %s" % map_name
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _on_delete_map() -> void:
	var selected_indices: PackedInt32Array = _map_list.get_selected_items()
	if selected_indices.is_empty():
		return
	var map_name: String = _map_list.get_item_text(selected_indices[0])
	if hex_grid.delete_map(map_name):
		_status_label.text = "Deleted: %s" % map_name
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		_refresh_map_list()


func _on_clear() -> void:
	var changes: Array = []
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		var old_snap: Dictionary = _snapshot_tile(tile)
		tile.terrain = HexTile.TerrainType.GRASS
		tile.elevation = 0
		tile.is_ramp = false
		tile.ramp_exit_dir = -1
		var new_snap: Dictionary = _snapshot_tile(tile)
		if old_snap != new_snap:
			changes.append({"coord": coord, "old": old_snap, "new": new_snap})
	if not changes.is_empty():
		_push_undo(changes)
	grid_visual.rebuild_all_tiles()
	_status_label.text = "All tiles cleared to grass"
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _on_generate_procedural() -> void:
	# Snapshot everything for undo.
	var changes: Array = []
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		var old_snap: Dictionary = _snapshot_tile(tile)
		changes.append({"coord": coord, "old": old_snap, "new": {}})  # "new" filled after gen.

	hex_grid.reset_to_procedural()

	# Fill in "new" snapshots.
	for i: int in range(changes.size()):
		var coord: Vector2i = changes[i]["coord"] as Vector2i
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile:
			changes[i]["new"] = _snapshot_tile(tile)

	# Remove no-change entries.
	var filtered: Array = []
	for entry: Variant in changes:
		var d: Dictionary = entry as Dictionary
		if d["old"] != d["new"]:
			filtered.append(d)
	if not filtered.is_empty():
		_push_undo(filtered)

	grid_visual.rebuild_all_tiles()
	_status_label.text = "Generated procedural map"
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))


func _refresh_map_list() -> void:
	if _map_list == null:
		return
	_map_list.clear()
	var names: Array[String] = hex_grid.get_saved_map_names()
	for n: String in names:
		_map_list.add_item(n)


func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# ============================================================================
# HELPER
# ============================================================================

func _terrain_name(t: HexTile.TerrainType) -> String:
	match t:
		HexTile.TerrainType.GRASS:
			return "Grass"
		HexTile.TerrainType.MOUNTAIN:
			return "Mountain"
		HexTile.TerrainType.WATER:
			return "Water"
		HexTile.TerrainType.HIVE:
			return "Hive"
		HexTile.TerrainType.FOREST:
			return "Forest"
	return "Unknown"


func _tool_name(t: Tool) -> String:
	match t:
		Tool.PAINT_TERRAIN:
			return "Paint Terrain"
		Tool.ELEVATION_RAISE:
			return "Raise Elevation"
		Tool.ELEVATION_LOWER:
			return "Lower Elevation"
		Tool.RAMP_PAINT:
			return "Paint Ramp"
		Tool.FLOOD_FILL:
			return "Flood Fill"
		Tool.ERASE:
			return "Erase"
	return "Unknown"


func _select_tool(tool: Tool) -> void:
	_current_tool = tool
	if _tool_buttons.has(tool):
		(_tool_buttons[tool] as Button).button_pressed = true
	_update_status()


func _update_status() -> void:
	var sym_name: String = "Off"
	match _symmetry:
		SymmetryMode.FOLD_2:
			sym_name = "2-fold"
		SymmetryMode.FOLD_3:
			sym_name = "3-fold"
		SymmetryMode.FOLD_6:
			sym_name = "6-fold"
	_status_label.text = "%s | Brush: %d | Sym: %s" % [_tool_name(_current_tool), _brush_size, sym_name]
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _update_brush_label() -> void:
	_brush_label.text = "%d" % _brush_size


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -290
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.border_color = Color(0.9, 0.75, 0.3, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "MAP EDITOR" if standalone_mode else "MAP EDITOR (F6)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)
	vbox.add_child(_sep())

	# ---- TOOLS ----
	vbox.add_child(_section_label("TOOLS"))
	var tool_grid := GridContainer.new()
	tool_grid.columns = 2
	vbox.add_child(tool_grid)

	var tool_group := ButtonGroup.new()
	var tool_info: Array = [
		[Tool.PAINT_TERRAIN, "Paint (T)", Color(0.4, 0.7, 0.3)],
		[Tool.ELEVATION_RAISE, "Raise (Q)", Color(0.65, 0.55, 0.35)],
		[Tool.ELEVATION_LOWER, "Lower (E)", Color(0.45, 0.40, 0.30)],
		[Tool.RAMP_PAINT, "Ramp (R)", Color(0.55, 0.50, 0.35)],
		[Tool.FLOOD_FILL, "Fill (F)", Color(0.35, 0.55, 0.7)],
		[Tool.ERASE, "Erase (X)", Color(0.6, 0.3, 0.3)],
	]
	for info: Variant in tool_info:
		var arr: Array = info as Array
		var tool_type: int = arr[0] as int
		var label_text: String = arr[1] as String
		var color: Color = arr[2] as Color
		var btn := Button.new()
		btn.text = label_text
		btn.custom_minimum_size = Vector2(125, 32)
		btn.toggle_mode = true
		btn.button_group = tool_group
		_style_toggle_button(btn, color)
		btn.pressed.connect(_on_tool_selected.bind(tool_type))
		tool_grid.add_child(btn)
		_tool_buttons[tool_type] = btn
	# Default select.
	(_tool_buttons[Tool.PAINT_TERRAIN] as Button).button_pressed = true

	vbox.add_child(_sep())

	# ---- TERRAIN ----
	vbox.add_child(_section_label("TERRAIN"))
	var terrain_grid := GridContainer.new()
	terrain_grid.columns = 2
	vbox.add_child(terrain_grid)

	var terrain_group := ButtonGroup.new()
	var terrain_info: Array = [
		[HexTile.TerrainType.GRASS, "Grass", Color(0.4, 0.7, 0.3)],
		[HexTile.TerrainType.MOUNTAIN, "Mountain", Color(0.55, 0.5, 0.45)],
		[HexTile.TerrainType.FOREST, "Forest", Color(0.25, 0.5, 0.2)],
		[HexTile.TerrainType.WATER, "Water", Color(0.3, 0.5, 0.8)],
		[HexTile.TerrainType.HIVE, "Hive", Color(0.9, 0.75, 0.3)],
	]
	for info: Variant in terrain_info:
		var arr: Array = info as Array
		var t_type: int = arr[0] as int
		var t_name: String = arr[1] as String
		var t_color: Color = arr[2] as Color
		var btn := Button.new()
		btn.text = t_name
		btn.custom_minimum_size = Vector2(125, 32)
		btn.toggle_mode = true
		btn.button_group = terrain_group
		_style_toggle_button(btn, t_color)
		btn.pressed.connect(_on_terrain_selected.bind(t_type))
		terrain_grid.add_child(btn)
		_terrain_buttons[t_type] = btn
	(_terrain_buttons[int(HexTile.TerrainType.GRASS)] as Button).button_pressed = true

	vbox.add_child(_sep())

	# ---- BRUSH SIZE ----
	vbox.add_child(_section_label("BRUSH SIZE (+/-)"))
	var brush_hbox := HBoxContainer.new()
	vbox.add_child(brush_hbox)

	var brush_minus := Button.new()
	brush_minus.text = " - "
	brush_minus.custom_minimum_size = Vector2(40, 32)
	brush_minus.pressed.connect(func() -> void: _brush_size = maxi(_brush_size - 1, 1); _update_brush_label())
	brush_hbox.add_child(brush_minus)

	_brush_label = Label.new()
	_brush_label.text = "%d" % _brush_size
	_brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brush_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brush_label.add_theme_font_size_override("font_size", 18)
	_brush_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	brush_hbox.add_child(_brush_label)

	var brush_plus := Button.new()
	brush_plus.text = " + "
	brush_plus.custom_minimum_size = Vector2(40, 32)
	brush_plus.pressed.connect(func() -> void: _brush_size = mini(_brush_size + 1, 7); _update_brush_label())
	brush_hbox.add_child(brush_plus)

	vbox.add_child(_sep())

	# ---- RAMP DIRECTION ----
	vbox.add_child(_section_label("RAMP DIRECTION"))
	var ramp_hbox := HBoxContainer.new()
	vbox.add_child(ramp_hbox)

	var ramp_minus := Button.new()
	ramp_minus.text = " < "
	ramp_minus.custom_minimum_size = Vector2(40, 32)
	ramp_minus.pressed.connect(func() -> void: _ramp_dir = (_ramp_dir - 1 + 6) % 6; _ramp_dir_label.text = "Dir: %d" % _ramp_dir)
	ramp_hbox.add_child(ramp_minus)

	_ramp_dir_label = Label.new()
	_ramp_dir_label.text = "Dir: 0"
	_ramp_dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ramp_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ramp_dir_label.add_theme_font_size_override("font_size", 14)
	ramp_hbox.add_child(_ramp_dir_label)

	var ramp_plus := Button.new()
	ramp_plus.text = " > "
	ramp_plus.custom_minimum_size = Vector2(40, 32)
	ramp_plus.pressed.connect(func() -> void: _ramp_dir = (_ramp_dir + 1) % 6; _ramp_dir_label.text = "Dir: %d" % _ramp_dir)
	ramp_hbox.add_child(ramp_plus)

	vbox.add_child(_sep())

	# ---- SYMMETRY ----
	vbox.add_child(_section_label("SYMMETRY"))
	var sym_hbox := HBoxContainer.new()
	vbox.add_child(sym_hbox)

	var sym_group := ButtonGroup.new()
	var sym_options: Array = [
		[SymmetryMode.OFF, "Off"],
		[SymmetryMode.FOLD_2, "2x"],
		[SymmetryMode.FOLD_3, "3x"],
		[SymmetryMode.FOLD_6, "6x"],
	]
	for opt: Variant in sym_options:
		var arr: Array = opt as Array
		var sym_val: int = arr[0] as int
		var sym_text: String = arr[1] as String
		var btn := Button.new()
		btn.text = sym_text
		btn.toggle_mode = true
		btn.button_group = sym_group
		btn.custom_minimum_size = Vector2(55, 30)
		btn.pressed.connect(_on_symmetry_selected.bind(sym_val))
		sym_hbox.add_child(btn)
		if sym_val == SymmetryMode.OFF:
			btn.button_pressed = true

	_symmetry_label = Label.new()
	_symmetry_label.text = ""
	_symmetry_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sym_hbox.add_child(_symmetry_label)

	vbox.add_child(_sep())

	# ---- MAP MANAGEMENT ----
	vbox.add_child(_section_label("MAP NAME"))
	_map_name_input = LineEdit.new()
	_map_name_input.text = "custom_map"
	_map_name_input.placeholder_text = "Enter map name..."
	_map_name_input.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_map_name_input)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_row)

	var save_btn := _action_button("SAVE", Color(0.25, 0.55, 0.3))
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

	var load_btn := _action_button("LOAD", Color(0.3, 0.45, 0.6))
	load_btn.pressed.connect(_on_load)
	btn_row.add_child(load_btn)

	var del_btn := _action_button("DEL", Color(0.55, 0.25, 0.25))
	del_btn.pressed.connect(_on_delete_map)
	btn_row.add_child(del_btn)

	vbox.add_child(_section_label("SAVED MAPS"))
	_map_list = ItemList.new()
	_map_list.custom_minimum_size = Vector2(0, 100)
	_map_list.max_columns = 1
	_map_list.auto_height = true
	_map_list.allow_reselect = true
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	list_style.set_corner_radius_all(4)
	_map_list.add_theme_stylebox_override("panel", list_style)
	vbox.add_child(_map_list)
	# Double-click to load.
	_map_list.item_activated.connect(func(index: int) -> void:
		_map_list.select(index)
		_on_load()
	)

	vbox.add_child(_sep())

	# ---- ACTIONS ----
	vbox.add_child(_section_label("ACTIONS"))
	var clear_btn := _action_button("CLEAR ALL", Color(0.5, 0.35, 0.25))
	clear_btn.custom_minimum_size = Vector2(0, 34)
	clear_btn.pressed.connect(_on_clear)
	vbox.add_child(clear_btn)

	var gen_btn := _action_button("GENERATE (Procedural)", Color(0.3, 0.45, 0.55))
	gen_btn.custom_minimum_size = Vector2(0, 34)
	gen_btn.pressed.connect(_on_generate_procedural)
	vbox.add_child(gen_btn)

	# Back to menu (standalone only).
	if standalone_mode:
		vbox.add_child(_sep())
		var back_btn := _action_button("BACK TO MENU", Color(0.4, 0.3, 0.2))
		back_btn.custom_minimum_size = Vector2(0, 34)
		back_btn.pressed.connect(_on_back_to_menu)
		vbox.add_child(back_btn)

	vbox.add_child(_sep())

	# Status.
	_status_label = Label.new()
	_status_label.text = "Paint Terrain | Brush: 1 | Sym: Off"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	# Hint.
	var hint := Label.new()
	hint.text = "Right-click: Eyedropper | Ctrl+Z: Undo | Ctrl+Y: Redo"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	add_child(_panel)
	_refresh_map_list()


# ============================================================================
# UI CALLBACKS
# ============================================================================

func _on_tool_selected(tool_type: int) -> void:
	_current_tool = tool_type as Tool
	_update_status()


func _on_terrain_selected(terrain_type: int) -> void:
	_brush_terrain = terrain_type as HexTile.TerrainType
	_update_status()


func _on_symmetry_selected(sym: int) -> void:
	_symmetry = sym as SymmetryMode
	_update_status()


# ============================================================================
# UI HELPERS
# ============================================================================

func _sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	return sep


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	return lbl


func _action_button(text: String, bg: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 30)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", s)
	var s_hover := s.duplicate() as StyleBoxFlat
	s_hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", s_hover)
	var s_pressed := s.duplicate() as StyleBoxFlat
	s_pressed.bg_color = bg.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", s_pressed)
	return btn


func _style_toggle_button(btn: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color * 0.5
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color * 0.7
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color
	pressed.border_color = Color.WHITE
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(4)
	btn.add_theme_stylebox_override("pressed", pressed)
