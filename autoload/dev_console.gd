extends CanvasLayer
## In-game developer console with logging and command execution.
## Toggle with backtick/tilde (~) key. Logs game events, asset errors, and combat info.
## Other systems call DevConsole.log_info/log_warning/log_error/log_combat/log_wave.

## Maximum log lines kept in history.
const MAX_LOG_LINES: int = 500

## Console panel height as fraction of screen.
const PANEL_HEIGHT_FRACTION: float = 0.4

## Colors per log category.
const COLORS: Dictionary = {
	"info": Color(0.85, 0.85, 0.85),
	"warning": Color(1.0, 0.85, 0.3),
	"error": Color(1.0, 0.35, 0.25),
	"combat": Color(1.0, 0.6, 0.4),
	"wave": Color(0.5, 0.85, 1.0),
	"build": Color(0.6, 0.9, 0.5),
	"system": Color(0.7, 0.7, 0.9),
	"command": Color(0.4, 1.0, 0.7),
}

var _visible: bool = false
var _panel: PanelContainer
var _log_label: RichTextLabel
var _input_field: LineEdit
var _log_lines: Array[String] = []
var _command_history: Array[String] = []
var _history_index: int = -1


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false

	# Connect game signals for automatic logging.
	_connect_signals()

	log_system("DevConsole initialized. Press ~ to toggle.")


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = PANEL_HEIGHT_FRACTION
	_panel.offset_left = 0.0
	_panel.offset_top = 0.0
	_panel.offset_right = 0.0
	_panel.offset_bottom = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(0.3, 0.5, 0.3, 0.6)
	style.border_width_bottom = 2
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)

	# Header.
	var header := Label.new()
	header.text = "DEV CONSOLE"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))
	vbox.add_child(header)

	# Log output.
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(_log_label)

	# Command input.
	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Enter command... (type 'help' for commands)"
	_input_field.add_theme_font_size_override("font_size", 14)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	input_style.border_color = Color(0.3, 0.5, 0.3, 0.5)
	input_style.border_width_bottom = 1
	input_style.border_width_top = 1
	input_style.content_margin_left = 6.0
	input_style.content_margin_right = 6.0
	_input_field.add_theme_stylebox_override("normal", input_style)
	_input_field.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
	_input_field.text_submitted.connect(_on_command_submitted)
	vbox.add_child(_input_field)

	add_child(_panel)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_QUOTELEFT:
			_toggle()
			get_viewport().set_input_as_handled()
			return
	if not _visible:
		return
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_input_field.grab_focus()
		get_tree().paused = true
	else:
		_input_field.release_focus()
		get_tree().paused = false


func _navigate_history(direction: int) -> void:
	if _command_history.is_empty():
		return
	_history_index = clampi(_history_index + direction, 0, _command_history.size() - 1)
	_input_field.text = _command_history[_history_index]
	_input_field.caret_column = _input_field.text.length()


# -- Public Logging API --

func log_info(msg: String) -> void:
	_add_log("info", msg)

func log_warning(msg: String) -> void:
	_add_log("warning", msg)
	push_warning("[DevConsole] " + msg)

func log_error(msg: String) -> void:
	_add_log("error", msg)
	push_error("[DevConsole] " + msg)

func log_combat(msg: String) -> void:
	_add_log("combat", msg)

func log_wave(msg: String) -> void:
	_add_log("wave", msg)

func log_build(msg: String) -> void:
	_add_log("build", msg)

func log_system(msg: String) -> void:
	_add_log("system", msg)

func log_command(msg: String) -> void:
	_add_log("command", msg)


func _add_log(category: String, msg: String) -> void:
	var color: Color = COLORS.get(category, Color.WHITE)
	var hex_color: String = color.to_html(false)
	var timestamp: String = _get_timestamp()
	var line: String = "[color=#888888]%s[/color] [color=#%s][%s][/color] %s" % [timestamp, hex_color, category.to_upper(), msg]
	_log_lines.append(line)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	if _log_label:
		_log_label.clear()
		_log_label.append_text("\n".join(_log_lines))


func _get_timestamp() -> String:
	@warning_ignore("integer_division")
	var ticks: int = int(Time.get_ticks_msec() / 1000.0)
	@warning_ignore("integer_division")
	var m: int = ticks / 60
	var s: int = ticks % 60
	return "%02d:%02d" % [m, s]


# -- Command Processing --

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_command_history.append(text)
	_history_index = _command_history.size()
	_input_field.clear()
	log_command("> " + text)
	_execute_command(text.strip_edges())


func _execute_command(raw: String) -> void:
	var parts: PackedStringArray = raw.split(" ", false)
	if parts.is_empty():
		return
	var cmd: String = parts[0].to_lower()
	var args: PackedStringArray = parts.slice(1)

	match cmd:
		"help":
			_cmd_help()
		"clear":
			_log_lines.clear()
			if _log_label:
				_log_label.clear()
			log_system("Console cleared.")
		"god":
			_cmd_god()
		"killall":
			_cmd_killall()
		"skipday", "skip":
			_cmd_skipday(args)
		"spawn":
			_cmd_spawn(args)
		"timescale", "ts":
			_cmd_timescale(args)
		"freebuild", "fb":
			_cmd_freebuild()
		"heal":
			_cmd_heal()
		"damage", "dmg":
			_cmd_damage(args)
		"day":
			_cmd_day()
		"night":
			_cmd_night()
		"status":
			_cmd_status()
		"honey":
			_cmd_honey(args)
		_:
			log_warning("Unknown command: '%s'. Type 'help' for available commands." % cmd)


func _cmd_help() -> void:
	log_system("--- Available Commands ---")
	log_system("  god          - Toggle god mode (hero + hive invulnerable)")
	log_system("  killall      - Kill all alive enemies instantly")
	log_system("  skip [N]     - Skip to day N (default: next day)")
	log_system("  spawn <type> [count] - Spawn enemies (wasp/hornet)")
	log_system("  ts <value>   - Set time scale (0.25, 0.5, 1, 2, 4)")
	log_system("  fb           - Toggle free build (build anywhere)")
	log_system("  heal         - Full heal hero and hive")
	log_system("  dmg <amount> - Deal damage to hero (testing)")
	log_system("  day          - Force start day")
	log_system("  night        - Force start night")
	log_system("  status       - Show current game state")
	log_system("  honey <N>    - Set honey balance")
	log_system("  clear        - Clear console log")
	log_system("  help         - Show this help")


func _cmd_god() -> void:
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero and hero.health:
		hero.health.invulnerable = not hero.health.invulnerable
		var state: String = "ON" if hero.health.invulnerable else "OFF"
		log_system("God mode: %s" % state)
		# Also make hive invulnerable.
		var hive: Variant = _get_hive()
		if hive and hive.health:
			hive.health.invulnerable = hero.health.invulnerable
	else:
		log_error("Hero not found.")


func _cmd_killall() -> void:
	var enemies: Array = get_tree().get_nodes_in_group(&"enemies")
	var count: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.has_method("take_damage") and e.has_method("is_alive") and e.is_alive():
			e.take_damage(99999.0)
			count += 1
	log_system("Killed %d enemies." % count)


func _cmd_skipday(args: PackedStringArray) -> void:
	var target_day: int = DayNightManager.day_number + 1
	if args.size() > 0 and args[0].is_valid_int():
		target_day = args[0].to_int()
	if target_day < 1:
		target_day = 1
	DayNightManager.day_number = target_day - 1
	if DayNightManager.is_day():
		# Kill current wave first.
		_cmd_killall()
	# Wait a frame then start the day.
	await get_tree().process_frame
	if DayNightManager.is_night():
		SignalBus.start_day_requested.emit()
	log_system("Skipping to Day %d." % target_day)


func _cmd_spawn(args: PackedStringArray) -> void:
	if args.is_empty():
		log_warning("Usage: spawn <wasp|hornet> [count]")
		return
	var enemy_type: String = args[0].to_lower()
	var count: int = 1
	if args.size() > 1 and args[1].is_valid_int():
		count = clampi(args[1].to_int(), 1, 50)

	var hex_grid: HexGrid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	var enemies_container: Node3D = get_tree().current_scene.get_node_or_null("Enemies") as Node3D
	if hex_grid == null or enemies_container == null:
		log_error("Scene nodes not found.")
		return

	var data := EnemyRegistry.get_enemy(StringName(enemy_type))
	if data == null:
		log_error("Unknown enemy type: '%s'. Available: wasp, hornet" % enemy_type)
		return

	var enemy_scene: PackedScene = preload("res://scenes/entities/enemy.tscn")
	for i in range(count):
		var ring: Array[Vector2i] = HexHelper.get_hex_ring(Vector2i.ZERO, hex_grid.map_radius)
		var spawn_hex: Vector2i = ring[randi() % ring.size()]
		var spawn_pos: Vector3 = hex_grid.hex_to_world(spawn_hex)
		var enemy = enemy_scene.instantiate()
		enemies_container.add_child(enemy)
		enemy.setup(data, hex_grid, spawn_pos)
		SignalBus.enemy_spawned.emit(enemy)

	log_system("Spawned %d %s(s)." % [count, enemy_type])


func _cmd_timescale(args: PackedStringArray) -> void:
	if args.is_empty():
		log_info("Current time scale: %.2f" % Engine.time_scale)
		return
	if args[0].is_valid_float():
		var ts: float = clampf(args[0].to_float(), 0.1, 10.0)
		Engine.time_scale = ts
		log_system("Time scale set to %.2f" % ts)
	else:
		log_warning("Usage: ts <0.1-10.0>")


func _cmd_freebuild() -> void:
	# Toggle free build mode via a global flag on BuildManager.
	var build_mgr: Node = get_tree().current_scene.get_node_or_null("BuildManager")
	if build_mgr and "free_build" in build_mgr:
		build_mgr.free_build = not build_mgr.free_build
		var state: String = "ON" if build_mgr.free_build else "OFF"
		log_system("Free build: %s" % state)
	else:
		log_warning("BuildManager not found or free_build not supported.")


func _cmd_heal() -> void:
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero and hero.health:
		hero.health.heal(hero.health.max_hp)
		log_system("Hero healed to full HP.")
	var hive: Variant = _get_hive()
	if hive and hive.health:
		hive.health.heal(hive.health.max_hp)
		log_system("Hive healed to full HP.")


func _cmd_damage(args: PackedStringArray) -> void:
	if args.is_empty():
		log_warning("Usage: dmg <amount>")
		return
	if args[0].is_valid_float():
		var amount: float = args[0].to_float()
		var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
		if hero and hero.has_method("take_damage"):
			hero.take_damage(amount)
			log_system("Dealt %.0f damage to hero." % amount)
	else:
		log_warning("Usage: dmg <amount>")


func _cmd_day() -> void:
	if DayNightManager.is_night():
		SignalBus.start_day_requested.emit()
		log_system("Forced day start.")
	else:
		log_warning("Already in day phase.")


func _cmd_night() -> void:
	if DayNightManager.is_day():
		_cmd_killall()
		log_system("Forced night (killed all enemies).")
	else:
		log_warning("Already in night phase.")


func _cmd_honey(args: PackedStringArray) -> void:
	if args.is_empty():
		log_info("Current honey: %d" % EconomyManager.get_honey())
		return
	if not args[0].is_valid_int():
		log_warning("Usage: honey <amount>")
		return
	var amount: int = args[0].to_int()
	EconomyManager.set_honey(amount)
	log_system("Honey set to %d." % amount)


func _cmd_status() -> void:
	var phase: String = "Day %d" % DayNightManager.day_number if DayNightManager.is_day() else "Night %d" % DayNightManager.night_number
	log_system("Phase: %s" % phase)

	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero and hero.health:
		log_system("Hero HP: %.0f / %.0f" % [hero.health.current_hp, hero.health.max_hp])

	var hive: Variant = _get_hive()
	if hive and hive.health:
		log_system("Hive HP: %.0f / %.0f" % [hive.health.current_hp, hive.health.max_hp])

	var enemies: Array = get_tree().get_nodes_in_group(&"enemies")
	var alive_count: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.has_method("is_alive") and e.is_alive():
			alive_count += 1
	log_system("Enemies alive: %d" % alive_count)

	var buildings: Node3D = get_tree().current_scene.get_node_or_null("Buildings") as Node3D
	if buildings:
		log_system("Buildings placed: %d" % buildings.get_child_count())

	log_system("Time scale: %.2f" % Engine.time_scale)
	log_system("Honey: %d" % EconomyManager.get_honey())


func _get_hive() -> Variant:
	var hex_grid: HexGrid = get_tree().current_scene.get_node_or_null("HexGrid") as HexGrid
	if hex_grid:
		return hex_grid.get_building_at(Vector2i.ZERO)
	return null


# -- Auto-logging via Signal Bus --

func _connect_signals() -> void:
	SignalBus.day_started.connect(func(day: int) -> void: log_wave("Day %d started." % day))
	SignalBus.night_started.connect(func(night: int) -> void: log_wave("Night %d started." % night))
	SignalBus.wave_started.connect(func(day: int, total: int) -> void: log_wave("Wave started: Day %d, %d enemies." % [day, total]))
	SignalBus.day_wave_cleared.connect(func() -> void: log_wave("Wave cleared!"))
	SignalBus.enemy_spawned.connect(func(enemy: Node) -> void:
		if enemy and "data" in enemy and enemy.data:
			log_combat("Enemy spawned: %s" % enemy.data.display_name)
	)
	SignalBus.enemy_died.connect(func(enemy: Node) -> void:
		if enemy and "data" in enemy and enemy.data:
			log_combat("Enemy died: %s" % enemy.data.display_name)
	)
	SignalBus.hero_damaged.connect(func(amount: float, current: float, maximum: float) -> void:
		log_combat("Hero took %.0f dmg (HP: %.0f/%.0f)" % [amount, current, maximum])
	)
	SignalBus.hero_died.connect(func() -> void: log_combat("Hero died! Respawning..."))
	SignalBus.hero_respawned.connect(func() -> void: log_combat("Hero respawned."))
	SignalBus.hive_damaged.connect(func(amount: float, current: float, maximum: float) -> void:
		log_combat("Hive took %.0f dmg (HP: %.0f/%.0f)" % [amount, current, maximum])
	)
	SignalBus.hive_destroyed.connect(func() -> void: log_error("HIVE DESTROYED! Game Over."))
	SignalBus.building_placed.connect(func(id: StringName, coord: Vector2i, level: int) -> void:
		log_build("Built %s at (%d,%d) L%d" % [id, coord.x, coord.y, level])
	)
	SignalBus.building_upgraded.connect(func(coord: Vector2i, level: int) -> void:
		log_build("Upgraded building at (%d,%d) to L%d" % [coord.x, coord.y, level])
	)
	SignalBus.building_destroyed.connect(func(building: Node, coord: Vector2i) -> void:
		var name_str: String = ""
		if building and "data" in building and building.data:
			name_str = building.data.display_name
		log_combat("Building destroyed: %s at (%d,%d)" % [name_str, coord.x, coord.y])
	)
	SignalBus.game_over.connect(func(final_day: int) -> void:
		log_error("GAME OVER on Day %d." % final_day)
	)
	SignalBus.run_won.connect(func(final_day: int) -> void:
		log_system("RUN WON on Day %d!" % final_day)
	)
	SignalBus.honey_changed.connect(func(new_amount: int, delta: int, reason: StringName) -> void:
		if reason == &"initial" or reason == &"restart":
			return
		var sign_str: String = "+" if delta >= 0 else ""
		log_info("Honey %s%d -> %d (%s)" % [sign_str, delta, new_amount, reason])
	)
