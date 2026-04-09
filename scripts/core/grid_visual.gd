class_name GridVisual
extends Node2D
## Renders the hex grid visually. Draws hex outlines, hover highlights,
## elevation visuals (cliff faces, ramps), and gameplay overlays.

## Reference to the HexGrid node
@onready var hex_grid: HexGrid = %HexGrid

## -- Visual Settings --

## Color of hex tile outlines (low ground)
@export var outline_color: Color = Color(0.85, 0.75, 0.55, 0.4)

## Outline thickness
@export var outline_width: float = 1.5

## -- Elevation Colors --
## Fill color for high ground hex tops
@export var high_ground_fill: Color = Color(0.37, 0.67, 0.31, 0.85)

## Fill color for low ground hex tops
@export var low_ground_fill: Color = Color(0.23, 0.39, 0.20, 0.65)

## Cliff face lit side (E/SE edges)
@export var cliff_lit_color: Color = Color(0.66, 0.55, 0.36, 0.95)

## Cliff face shadow side (SW edge)
@export var cliff_shadow_color: Color = Color(0.50, 0.40, 0.25, 0.95)

## Cliff face dark side (W/NW/NE edges)
@export var cliff_back_color: Color = Color(0.33, 0.26, 0.16, 0.80)

## Cliff top edge highlight
@export var cliff_edge_highlight: Color = Color(0.75, 0.63, 0.44, 0.5)

## How far cliff walls extend inward from the hex edge (0.0–1.0 fraction of corner distance)
@export_range(0.05, 0.6) var cliff_depth: float = 0.30

## Ramp fill color
@export var ramp_fill_color: Color = Color(0.30, 0.53, 0.24, 0.85)

## High ground outline color
@export var high_outline_color: Color = Color(0.28, 0.55, 0.22, 0.6)

## Color when a tile is hovered
@export var hover_fill_color: Color = Color(1.0, 0.85, 0.3, 0.25)

## Color of the hover outline
@export var hover_outline_color: Color = Color(1.0, 0.85, 0.3, 0.8)

## Fill color for the hero's active hex
@export var active_hex_fill_color: Color = Color(1.0, 0.7, 0.2, 0.15)

## Outline color for the hero's active hex
@export var active_hex_outline_color: Color = Color(1.0, 0.7, 0.2, 0.5)

## Whether to show coordinate labels
@export var show_coords: bool = true

## Coordinate label color
@export var coord_label_color: Color = Color(1.0, 1.0, 1.0, 0.4)

## Currently hovered hex coordinate (null if none)
var _hovered_coord: Variant = null

## Reference to the hero for active hex tracking
var _hero: Node2D = null

## Camera reference for culling
var _camera: Camera2D = null

## Cached visible rect for draw culling
var _visible_rect: Rect2 = Rect2()


## Edge-to-direction mapping: edge index → HexHelper.DIRECTIONS index.
## Edge i connects corner[i] to corner[(i+1)%6] and faces the neighbor in that direction.
## Pointy-top corners: 0=top-right, 1=bottom-right, 2=bottom, 3=bottom-left, 4=top-left, 5=top
const EDGE_TO_DIR: Array[int] = [
	0,  # edge 0→1 (right side)     → E  (1, 0)
	5,  # edge 1→2 (bottom-right)   → SE (0, 1)
	4,  # edge 2→3 (bottom-left)    → SW (-1, 1)
	3,  # edge 3→4 (left side)      → W  (-1, 0)
	2,  # edge 4→5 (top-left)       → NW (0, -1)
	1,  # edge 5→0 (top-right)      → NE (1, -1)
]

## Cliff shading per edge: 0 = lit (E/SE), 1 = shadow (SW), 2 = back/dark (W/NW/NE)
const EDGE_SHADE: Array[int] = [0, 0, 1, 2, 2, 2]


func _ready() -> void:
	z_index = -1
	_hero = %Hero
	_load_tile_config()


## Load saved tile visual config from disk if it exists.
func _load_tile_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://resources/tile_visual.cfg") != OK:
		return
	for key in cfg.get_section_keys("tile_visual"):
		var value: Variant = cfg.get_value("tile_visual", key)
		if value != null:
			set(key, value)


func _process(_delta: float) -> void:
	_update_visible_rect()
	_handle_mouse()
	queue_redraw()


func _update_visible_rect() -> void:
	_camera = get_viewport().get_camera_2d()
	if _camera:
		var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
		var viewport_size: Vector2 = get_viewport_rect().size
		var top_left: Vector2 = -canvas_transform.origin / canvas_transform.x.x
		var view_size: Vector2 = viewport_size / canvas_transform.x.x
		_visible_rect = Rect2(top_left, view_size).grow(hex_grid.hex_size * 2.0)


func _handle_mouse() -> void:
	var mouse_world: Vector2 = get_global_mouse_position()
	var hex_coord: Vector2i = hex_grid.world_to_hex(mouse_world)

	if hex_grid.has_tile(hex_coord):
		if _hovered_coord != hex_coord:
			_hovered_coord = hex_coord
			hex_grid.tile_hovered.emit(hex_coord)
	else:
		if _hovered_coord != null:
			_hovered_coord = null
			hex_grid.tile_unhovered.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_coord != null:
				var coord: Vector2i = _hovered_coord as Vector2i
				hex_grid.tile_clicked.emit(coord)


func _draw() -> void:
	if not hex_grid:
		return

	var hex_size: float = hex_grid.hex_size

	# Collect visible tiles sorted by Y for back-to-front drawing
	var sorted_coords: Array[Vector2i] = []
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		if _visible_rect.has_point(tile.pixel_center):
			sorted_coords.append(coord)

	var _grid_ref: HexGrid = hex_grid
	sorted_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _grid_ref.tiles[a].pixel_center.y < _grid_ref.tiles[b].pixel_center.y)

	# === MAIN PASS: Draw each hex (fill + cliff walls + outline) ===
	for coord: Vector2i in sorted_coords:
		var tile: HexTile = hex_grid.tiles[coord]
		var center: Vector2 = tile.pixel_center
		var corners: PackedVector2Array = HexHelper.get_hex_corners(center, hex_size)

		if tile.is_ramp:
			_draw_ramp_tile(tile, coord, corners, hex_size)
		elif tile.elevation > 0:
			_draw_high_tile(tile, coord, corners, center)
		else:
			_draw_low_tile(corners)

	# === OVERLAY PASS: Buildings, hero, hover ===
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		if tile.has_building and _visible_rect.has_point(tile.pixel_center):
			var b_corners: PackedVector2Array = HexHelper.get_hex_corners(tile.pixel_center, hex_size)
			draw_colored_polygon(b_corners, Color(0.9, 0.7, 0.2, 0.08))
			_draw_hex_outline(b_corners, Color(0.9, 0.6, 0.2, 0.5), 2.0)

	if _hero:
		var active_coord: Vector2i = _hero.get("current_hex")
		var active_tile: HexTile = hex_grid.get_tile(active_coord)
		if active_tile:
			var active_corners: PackedVector2Array = HexHelper.get_hex_corners(active_tile.pixel_center, hex_size)
			draw_colored_polygon(active_corners, active_hex_fill_color)
			_draw_hex_outline(active_corners, active_hex_outline_color, 2.0)

	if _hovered_coord != null:
		var coord: Vector2i = _hovered_coord as Vector2i
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile:
			var corners: PackedVector2Array = HexHelper.get_hex_corners(tile.pixel_center, hex_size)
			draw_colored_polygon(corners, hover_fill_color)
			_draw_hex_outline(corners, hover_outline_color, 2.5)
			if show_coords:
				var label_text: String = "%d, %d" % [coord.x, coord.y]
				_draw_coord_label(tile.pixel_center, label_text)


# ── Tile drawing helpers ──────────────────────────────────────────────

## Draw a LOW ground tile: dark green fill + outline.
func _draw_low_tile(corners: PackedVector2Array) -> void:
	draw_colored_polygon(corners, low_ground_fill)
	_draw_hex_outline(corners, outline_color, outline_width)


## Draw a HIGH ground tile.
## Interior tiles (all neighbors HIGH): full hex bright green.
## Cliff border tiles: small hex shifted away from cliff edges, cliff fills the rest.
func _draw_high_tile(_tile: HexTile, coord: Vector2i, corners: PackedVector2Array, center: Vector2) -> void:
	var hex_size: float = hex_grid.hex_size

	# Determine which edges need cliff
	var cliff_edges: Array[bool] = []
	cliff_edges.resize(6)
	var has_any_cliff: bool = false
	for edge_i in range(6):
		var dir_i: int = EDGE_TO_DIR[edge_i]
		var neighbor_coord: Vector2i = coord + HexHelper.DIRECTIONS[dir_i]
		var neighbor: HexTile = hex_grid.get_tile(neighbor_coord)
		var needs: bool = (neighbor == null) or (neighbor.elevation == 0 and not neighbor.is_ramp)
		cliff_edges[edge_i] = needs
		if needs:
			has_any_cliff = true

	if not has_any_cliff:
		# Interior elevated tile: full hex bright green, no inner hex
		draw_colored_polygon(corners, high_ground_fill)
		_draw_hex_outline(corners, high_outline_color, outline_width)
		return

	# --- Cliff border tile ---
	# Compute average cliff direction (toward LOW neighbors)
	var cliff_dir: Vector2 = Vector2.ZERO
	for edge_i in range(6):
		if cliff_edges[edge_i]:
			var mid: Vector2 = (corners[edge_i] + corners[(edge_i + 1) % 6]) * 0.5
			cliff_dir += (mid - center).normalized()
	cliff_dir = cliff_dir.normalized()

	# Inner hex: shifted AWAY from cliff direction
	var inner_size: float = hex_size * (1.0 - cliff_depth)
	var shift_amount: float = hex_size * cliff_depth * 0.5
	var inner_center: Vector2 = center - cliff_dir * shift_amount
	var inner_corners: PackedVector2Array = HexHelper.get_hex_corners(inner_center, inner_size)

	# 1. Fill full hex with bright green base
	draw_colored_polygon(corners, high_ground_fill)

	# 2. Draw cliff bands on cliff edges (between outer hex and shifted inner hex)
	for edge_i in range(6):
		if cliff_edges[edge_i]:
			_draw_cliff_band(corners, inner_corners, edge_i)

	# 3. Draw shifted inner hex surface on top
	draw_colored_polygon(inner_corners, high_ground_fill.lightened(0.06))
	_draw_hex_outline(inner_corners, high_outline_color, 1.0)

	# Outer hex outline
	_draw_hex_outline(corners, high_outline_color, outline_width)


## Draw a cliff band between outer and inner hex corners on one edge.
## Uses concentric hex corners so the inner surface remains a perfect hexagon.
func _draw_cliff_band(outer: PackedVector2Array, inner: PackedVector2Array, edge_i: int) -> void:
	var oa: Vector2 = outer[edge_i]
	var ob: Vector2 = outer[(edge_i + 1) % 6]
	var ia: Vector2 = inner[edge_i]
	var ib: Vector2 = inner[(edge_i + 1) % 6]

	# Extend slightly along edge to fill seams with adjacent hex cliff bands
	var edge_dir: Vector2 = (ob - oa).normalized()
	var overlap: float = 2.5
	var oa_ext: Vector2 = oa - edge_dir * overlap
	var ob_ext: Vector2 = ob + edge_dir * overlap
	var ia_ext: Vector2 = ia - edge_dir * overlap
	var ib_ext: Vector2 = ib + edge_dir * overlap

	# Pick color based on edge facing direction
	var shade: int = EDGE_SHADE[edge_i]
	var face_color: Color
	match shade:
		0: face_color = cliff_lit_color
		1: face_color = cliff_shadow_color
		_: face_color = cliff_back_color

	# Draw cliff wall polygon (ring segment between outer and inner hex)
	var wall: PackedVector2Array = PackedVector2Array([ia_ext, ib_ext, ob_ext, oa_ext])
	draw_colored_polygon(wall, face_color)

	# Stone texture lines (use non-extended points for clean look)
	var line_color: Color = Color(0.35, 0.27, 0.19, 0.3) if shade < 2 else Color(0.25, 0.18, 0.12, 0.2)
	for i in range(1, 3):
		var t: float = float(i) / 3.0
		var left: Vector2 = ia.lerp(oa, t)
		var right: Vector2 = ib.lerp(ob, t)
		draw_line(left, right, line_color, 0.6, true)

	# Highlight line at cliff top (inner hex edge)
	draw_line(ia, ib, cliff_edge_highlight, 1.0, true)


## Draw a RAMP tile: gradient fill, cliff bands on non-exit LOW edges, chevrons.
func _draw_ramp_tile(tile: HexTile, coord: Vector2i, corners: PackedVector2Array, hex_size: float) -> void:
	var center: Vector2 = tile.pixel_center

	# Ramp base fill
	draw_colored_polygon(corners, ramp_fill_color)

	# Draw cliff bands on non-exit edges that face LOW
	for edge_i in range(6):
		var dir_i: int = EDGE_TO_DIR[edge_i]
		if dir_i == tile.ramp_exit_dir:
			continue
		var neighbor_coord: Vector2i = coord + HexHelper.DIRECTIONS[dir_i]
		var neighbor: HexTile = hex_grid.get_tile(neighbor_coord)
		var needs_cliff: bool = (neighbor == null) or (neighbor.elevation == 0 and not neighbor.is_ramp)
		if not needs_cliff:
			continue
		# Slightly thinner cliff band for ramps
		var corner_a: Vector2 = corners[edge_i]
		var corner_b: Vector2 = corners[(edge_i + 1) % 6]
		var inner_a: Vector2 = corner_a.lerp(center, cliff_depth * 0.7)
		var inner_b: Vector2 = corner_b.lerp(center, cliff_depth * 0.7)
		var shade: int = EDGE_SHADE[edge_i]
		var face_color: Color
		match shade:
			0: face_color = cliff_lit_color.darkened(0.1)
			1: face_color = cliff_shadow_color.darkened(0.1)
			_: face_color = cliff_back_color.darkened(0.1)
		draw_colored_polygon(PackedVector2Array([inner_a, inner_b, corner_b, corner_a]), face_color)
		draw_line(inner_a, inner_b, cliff_edge_highlight.darkened(0.2), 0.8, true)

	# Chevron arrows showing slope direction
	if tile.ramp_exit_dir >= 0:
		var exit_edge: int = -1
		for e in range(6):
			if EDGE_TO_DIR[e] == tile.ramp_exit_dir:
				exit_edge = e
				break
		if exit_edge >= 0:
			var mid_a: Vector2 = corners[exit_edge]
			var mid_b: Vector2 = corners[(exit_edge + 1) % 6]
			var edge_mid: Vector2 = (mid_a + mid_b) * 0.5
			var slope_dir: Vector2 = (edge_mid - center).normalized()
			var perp: Vector2 = Vector2(-slope_dir.y, slope_dir.x)
			var chevron_color: Color = Color(0.17, 0.31, 0.15, 0.5)
			for i in range(3):
				var t: float = 0.15 + float(i) * 0.3
				var pt: Vector2 = center.lerp(edge_mid, t)
				var half_w: float = hex_size * 0.35 * (1.0 - t * 0.3)
				var left: Vector2 = pt - perp * half_w - slope_dir * 4.0
				var tip: Vector2 = pt
				var right: Vector2 = pt + perp * half_w - slope_dir * 4.0
				draw_line(left, tip, chevron_color, 1.3, true)
				draw_line(right, tip, chevron_color, 1.3, true)

	_draw_hex_outline(corners, Color(0.35, 0.54, 0.29, 0.6), outline_width)


# ── Generic drawing helpers ───────────────────────────────────────────

## Draw a hex outline from corner points.
func _draw_hex_outline(corners: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(corners.size()):
		var next: int = (i + 1) % corners.size()
		draw_line(corners[i], corners[next], color, width, true)


## Draw a coordinate label at a position.
func _draw_coord_label(pos: Vector2, text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var draw_pos: Vector2 = pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, coord_label_color)
