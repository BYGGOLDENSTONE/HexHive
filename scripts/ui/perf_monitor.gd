class_name PerfMonitor
extends CanvasLayer
## Performance monitor overlay toggled with F4.
## Shows FPS, entity counts, pathfinding stats, memory usage.

var _visible: bool = false
var _panel: PanelContainer
var _stats_label: RichTextLabel
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.25

# Tracked counters (other systems can increment these).
var pathfinding_calls: int = 0
var pathfinding_time_ms: float = 0.0
var _last_pathfinding_calls: int = 0
var _last_pathfinding_time_ms: float = 0.0

# FPS tracking.
var _fps_history: Array[float] = []
const FPS_HISTORY_SIZE: int = 60


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -220.0
	_panel.offset_top = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = 200.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.border_color = Color(0.3, 0.4, 0.5, 0.5)
	style.border_width_left = 1
	style.border_width_bottom = 1
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.add_theme_font_size_override("normal_font_size", 12)
	_panel.add_child(_stats_label)

	add_child(_panel)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F4:
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if DevConsole:
		DevConsole.log_system("Perf monitor: %s" % ("ON" if _visible else "OFF"))


func _process(delta: float) -> void:
	if not _visible:
		return

	# Track FPS.
	var fps: float = 1.0 / maxf(delta, 0.001)
	_fps_history.append(fps)
	if _fps_history.size() > FPS_HISTORY_SIZE:
		_fps_history.pop_front()

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_refresh_stats()


func _refresh_stats() -> void:
	var text: String = ""

	# FPS.
	var current_fps: float = Engine.get_frames_per_second()
	var avg_fps: float = _calculate_avg_fps()
	var min_fps: float = _calculate_min_fps()
	var fps_color: String = _fps_color(current_fps)
	text += "[color=#8888aa]PERFORMANCE[/color]\n"
	text += "FPS: [color=#%s]%.0f[/color]  avg: %.0f  min: %.0f\n" % [fps_color, current_fps, avg_fps, min_fps]

	# Time scale.
	if Engine.time_scale != 1.0:
		text += "Time Scale: [color=#ffaa44]%.2fx[/color]\n" % Engine.time_scale

	# Entity counts.
	text += "\n[color=#8888aa]ENTITIES[/color]\n"
	var tree := get_tree()
	var enemies: Array = tree.get_nodes_in_group(&"enemies")
	var alive_enemies: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.has_method("is_alive") and e.is_alive():
			alive_enemies += 1
	text += "Enemies: [color=#ff8866]%d[/color] alive / %d total\n" % [alive_enemies, enemies.size()]

	var projectiles: Node3D = tree.current_scene.get_node_or_null("Projectiles") as Node3D
	var proj_count: int = projectiles.get_child_count() if projectiles else 0
	text += "Projectiles: %d\n" % proj_count

	var buildings: Node3D = tree.current_scene.get_node_or_null("Buildings") as Node3D
	var building_count: int = buildings.get_child_count() if buildings else 0
	text += "Buildings: %d\n" % building_count

	# Node count.
	var total_nodes: int = _count_nodes(tree.current_scene)
	text += "Total nodes: %d\n" % total_nodes

	# Pathfinding.
	text += "\n[color=#8888aa]PATHFINDING[/color]\n"
	var calls_per_sec: float = float(pathfinding_calls - _last_pathfinding_calls) / maxf(UPDATE_INTERVAL, 0.01)
	text += "Calls/s: %.1f\n" % calls_per_sec
	_last_pathfinding_calls = pathfinding_calls
	_last_pathfinding_time_ms = pathfinding_time_ms

	# Memory.
	text += "\n[color=#8888aa]MEMORY[/color]\n"
	var static_mem: float = OS.get_static_memory_usage() / 1048576.0
	text += "Static: %.1f MB\n" % static_mem

	_stats_label.clear()
	_stats_label.append_text(text)


func _calculate_avg_fps() -> float:
	if _fps_history.is_empty():
		return 0.0
	var total: float = 0.0
	for f in _fps_history:
		total += f
	return total / _fps_history.size()


func _calculate_min_fps() -> float:
	if _fps_history.is_empty():
		return 0.0
	var min_val: float = INF
	for f in _fps_history:
		min_val = minf(min_val, f)
	return min_val


func _fps_color(fps: float) -> String:
	if fps >= 55.0:
		return "44dd44"
	if fps >= 30.0:
		return "dddd44"
	return "dd4444"


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


## Call this from HexGrid.find_path() to track pathfinding performance.
func track_pathfinding(elapsed_ms: float) -> void:
	pathfinding_calls += 1
	pathfinding_time_ms += elapsed_ms
