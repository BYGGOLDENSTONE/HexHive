class_name GridVisual
extends Node2D
## Renders the hex grid visually. Draws hex outlines, hover highlights,
## and inner slot positions for debugging and gameplay.

## Reference to the HexGrid node
@onready var hex_grid: HexGrid = %HexGrid

## -- Visual Settings --

## Color of hex tile outlines
@export var outline_color: Color = Color(0.85, 0.75, 0.55, 0.4)

## Outline thickness
@export var outline_width: float = 1.5

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


func _ready() -> void:
	z_index = -1
	_hero = %Hero


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

	# Draw all visible hex outlines
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		var center: Vector2 = tile.pixel_center

		# Culling: skip hexes outside visible area
		if not _visible_rect.has_point(center):
			continue

		var corners: PackedVector2Array = HexHelper.get_hex_corners(center, hex_size)
		_draw_hex_outline(corners, outline_color, outline_width)

	# Draw building-occupied tiles with amber outline
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		if tile.has_building and _visible_rect.has_point(tile.pixel_center):
			var b_corners: PackedVector2Array = HexHelper.get_hex_corners(tile.pixel_center, hex_size)
			draw_colored_polygon(b_corners, Color(0.9, 0.7, 0.2, 0.08))
			_draw_hex_outline(b_corners, Color(0.9, 0.6, 0.2, 0.5), 2.0)

	# Draw hero's active hex
	if _hero:
		var active_coord: Vector2i = _hero.get("current_hex")
		var active_tile: HexTile = hex_grid.get_tile(active_coord)
		if active_tile:
			var active_corners: PackedVector2Array = HexHelper.get_hex_corners(active_tile.pixel_center, hex_size)
			draw_colored_polygon(active_corners, active_hex_fill_color)
			_draw_hex_outline(active_corners, active_hex_outline_color, 2.0)

	# Draw hover highlight
	if _hovered_coord != null:
		var coord: Vector2i = _hovered_coord as Vector2i
		var tile: HexTile = hex_grid.get_tile(coord)
		if tile:
			var corners: PackedVector2Array = HexHelper.get_hex_corners(tile.pixel_center, hex_size)
			# Fill
			draw_colored_polygon(corners, hover_fill_color)
			# Outline
			_draw_hex_outline(corners, hover_outline_color, 2.5)

			# Coordinate label
			if show_coords:
				var label_text: String = "%d, %d" % [coord.x, coord.y]
				_draw_coord_label(tile.pixel_center, label_text)



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
