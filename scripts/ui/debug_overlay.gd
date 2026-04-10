class_name DebugOverlay
extends CanvasLayer
## Visual debug overlay toggled with F3.
## Shows: hex coordinates, walkability, pathfinding, attack ranges, enemy targets.

enum DebugMode { OFF, COORDS, WALKABILITY, RANGES, TARGETS, ALL }

const MODE_NAMES: Array[String] = ["OFF", "COORDS", "WALKABILITY", "RANGES", "TARGETS", "ALL"]

var _current_mode: DebugMode = DebugMode.OFF
var _label: Label
var _draw_node: Control

# References cached on first use.
var _hex_grid: HexGrid
var _camera: Camera3D


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Mode label.
	_label = Label.new()
	_label.position = Vector2(10, 60)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_label.visible = false
	add_child(_label)

	# Draw surface (full-screen Control for 2D drawing over 3D).
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.visible = false
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F3:
			_cycle_mode()
			get_viewport().set_input_as_handled()


func _cycle_mode() -> void:
	_current_mode = ((_current_mode as int) + 1) % DebugMode.size() as DebugMode
	var is_on: bool = _current_mode != DebugMode.OFF
	_label.visible = is_on
	_draw_node.visible = is_on
	if is_on:
		_label.text = "Debug: %s (F3 to cycle)" % MODE_NAMES[_current_mode]
		if DevConsole:
			DevConsole.log_system("Debug overlay: %s" % MODE_NAMES[_current_mode])
	else:
		if DevConsole:
			DevConsole.log_system("Debug overlay: OFF")


func _process(_delta: float) -> void:
	if _current_mode == DebugMode.OFF:
		return
	_draw_node.queue_redraw()


func _ensure_refs() -> void:
	if _hex_grid == null:
		_hex_grid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	if _camera == null:
		_camera = get_viewport().get_camera_3d()


func _on_draw() -> void:
	if _current_mode == DebugMode.OFF:
		return
	_ensure_refs()
	if _hex_grid == null or _camera == null:
		return

	match _current_mode:
		DebugMode.COORDS:
			_draw_hex_coords()
		DebugMode.WALKABILITY:
			_draw_walkability()
		DebugMode.RANGES:
			_draw_ranges()
		DebugMode.TARGETS:
			_draw_targets()
		DebugMode.ALL:
			_draw_walkability()
			_draw_ranges()
			_draw_targets()


func _world_to_screen(world_pos: Vector3) -> Vector2:
	if not _camera.is_position_behind(world_pos):
		return _camera.unproject_position(world_pos)
	return Vector2(-1000, -1000)


func _draw_hex_coords() -> void:
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	var hero_hex: Vector2i = Vector2i.ZERO
	if hero and "current_hex" in hero:
		hero_hex = hero.current_hex

	# Draw coords for hexes near the hero (performance: limit to radius 6).
	var visible_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(hero_hex, 6)
	var font: Font = ThemeDB.fallback_font
	for coord in visible_hexes:
		if not _hex_grid.has_tile(coord):
			continue
		var world_pos: Vector3 = _hex_grid.hex_to_world(coord) + Vector3(0, 0.2, 0)
		var screen_pos: Vector2 = _world_to_screen(world_pos)
		if screen_pos.x < -500:
			continue
		var text: String = "%d,%d" % [coord.x, coord.y]
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		_draw_node.draw_string(font, screen_pos - text_size * 0.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8, 0.7))


func _draw_walkability() -> void:
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	var hero_hex: Vector2i = Vector2i.ZERO
	if hero and "current_hex" in hero:
		hero_hex = hero.current_hex

	var visible_hexes: Array[Vector2i] = HexHelper.get_hexes_in_range(hero_hex, 6)
	for coord in visible_hexes:
		var tile: HexTile = _hex_grid.get_tile(coord)
		if tile == null:
			continue
		var world_pos: Vector3 = _hex_grid.hex_to_world(coord) + Vector3(0, 0.15, 0)
		var screen_pos: Vector2 = _world_to_screen(world_pos)
		if screen_pos.x < -500:
			continue
		var color: Color = Color(0.2, 0.8, 0.2, 0.25) if tile.is_walkable() else Color(0.9, 0.2, 0.2, 0.35)
		_draw_node.draw_circle(screen_pos, 8.0, color)

		if tile.has_building:
			_draw_node.draw_circle(screen_pos + Vector2(0, 12), 4.0, Color(0.9, 0.7, 0.2, 0.5))


func _draw_ranges() -> void:
	# Hero attack range.
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero:
		_draw_range_circle(hero.global_position, hero.attack_range, Color(0.3, 0.7, 1.0, 0.3), "Hero Range")

	# Building attack ranges.
	var buildings: Node3D = get_tree().current_scene.get_node_or_null("Buildings") as Node3D
	if buildings:
		for child in buildings.get_children():
			if child is Building and child.data and child.data.is_offensive():
				var range_val: float = child.data.get_attack_range(child.level)
				_draw_range_circle(child.global_position, range_val, Color(1.0, 0.7, 0.2, 0.2), "L%d" % child.level)


func _draw_range_circle(center: Vector3, radius: float, color: Color, label_text: String = "") -> void:
	var segments: int = 24
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		var world: Vector3 = center + Vector3(cos(angle) * radius, 0.1, sin(angle) * radius)
		var screen: Vector2 = _world_to_screen(world)
		if screen.x < -500:
			return
		points.append(screen)

	if points.size() >= 2:
		for i in range(points.size() - 1):
			_draw_node.draw_line(points[i], points[i + 1], color, 1.5)

	if label_text != "" and not points.is_empty():
		var font: Font = ThemeDB.fallback_font
		_draw_node.draw_string(font, points[0] + Vector2(4, -4), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func _draw_targets() -> void:
	var enemies: Array = get_tree().get_nodes_in_group(&"enemies")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if not e.has_method("is_alive") or not e.is_alive():
			continue

		var enemy_screen: Vector2 = _world_to_screen(e.global_position + Vector3(0, 0.3, 0))
		if enemy_screen.x < -500:
			continue

		# Draw line to current target.
		if "current_target" in e and e.current_target != null and is_instance_valid(e.current_target):
			var target_screen: Vector2 = _world_to_screen(e.current_target.global_position + Vector3(0, 0.3, 0))
			if target_screen.x > -500:
				var line_color: Color
				if e.current_target.is_in_group(&"hero"):
					line_color = Color(1.0, 0.3, 0.3, 0.6)
				elif e.current_target is Building:
					line_color = Color(1.0, 0.7, 0.2, 0.6)
				else:
					line_color = Color(0.8, 0.8, 0.8, 0.4)
				_draw_node.draw_line(enemy_screen, target_screen, line_color, 1.5)

				# Small diamond at enemy position.
				var diamond_size: float = 4.0
				var diamond_points: PackedVector2Array = PackedVector2Array([
					enemy_screen + Vector2(0, -diamond_size),
					enemy_screen + Vector2(diamond_size, 0),
					enemy_screen + Vector2(0, diamond_size),
					enemy_screen + Vector2(-diamond_size, 0),
				])
				_draw_node.draw_colored_polygon(diamond_points, line_color)

	# Draw hero auto-walk path.
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero and "is_auto_walking" in hero and hero.is_auto_walking and "_auto_walk_path" in hero:
		var path: Array = hero._auto_walk_path
		if path.size() >= 2:
			for i in range(path.size() - 1):
				var from_pos: Vector3 = _hex_grid.hex_to_world(path[i]) + Vector3(0, 0.3, 0)
				var to_pos: Vector3 = _hex_grid.hex_to_world(path[i + 1]) + Vector3(0, 0.3, 0)
				var from_screen: Vector2 = _world_to_screen(from_pos)
				var to_screen: Vector2 = _world_to_screen(to_pos)
				if from_screen.x > -500 and to_screen.x > -500:
					_draw_node.draw_line(from_screen, to_screen, Color(0.3, 1.0, 0.3, 0.5), 2.0)
