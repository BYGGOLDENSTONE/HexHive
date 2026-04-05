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

## Color for inner slot outlines (debug)
@export var slot_outline_color: Color = Color(0.6, 0.85, 1.0, 0.5)

## Size of inner flat-top slot hexes (computed for perfect fit)
var slot_visual_size: float

## Whether to show inner slots on hover
@export var show_slots_on_hover: bool = true

## Whether to show coordinate labels
@export var show_coords: bool = true

## Coordinate label color
@export var coord_label_color: Color = Color(1.0, 1.0, 1.0, 0.4)

## Currently hovered hex coordinate (null if none)
var _hovered_coord: Variant = null

## Whether slots are being shown (after click)
var _show_slots_coord: Variant = null

## Camera reference for culling
var _camera: Camera2D = null

## Cached visible rect for draw culling
var _visible_rect: Rect2 = Rect2()


func _ready() -> void:
	z_index = -1
	slot_visual_size = hex_grid.slot_radius / sqrt(3.0)


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
				# Toggle slot display on click
				if _show_slots_coord == coord:
					_show_slots_coord = null
				else:
					_show_slots_coord = coord


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

	# Draw inner slots
	var slots_coord: Variant = _show_slots_coord if _show_slots_coord != null else (_hovered_coord if show_slots_on_hover else null)
	if slots_coord != null:
		var coord: Vector2i = slots_coord as Vector2i
		var slot_positions: Array[Vector2] = hex_grid.get_tile_slot_positions(coord)
		for i in range(slot_positions.size()):
			var slot_center: Vector2 = slot_positions[i]
			var slot_corners: PackedVector2Array = HexHelper.get_flat_hex_corners(slot_center, slot_visual_size)
			# Center slot slightly different color
			var color: Color = slot_outline_color
			if i == 0:
				color = Color(1.0, 0.9, 0.4, 0.6)
			_draw_hex_outline(slot_corners, color, 1.5)
			# Slot fill
			var fill_color: Color = color
			fill_color.a = 0.1
			draw_colored_polygon(slot_corners, fill_color)


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
