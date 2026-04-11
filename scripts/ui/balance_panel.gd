class_name BalancePanel
extends CanvasLayer
## Runtime balance tuning panel toggled with F5.
## Adjust enemy, building, hero, and wave stats with sliders. Save to .tres files.

var _visible: bool = false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _category_selector: OptionButton

enum Category { HERO, ENEMIES, BUILDINGS, WAVES }
const CATEGORY_NAMES: Array[String] = ["Hero", "Enemies", "Buildings", "Waves"]

var _current_category: Category = Category.HERO
var _sliders: Dictionary = {}  # key -> {slider, value_label, default_value}
var _dirty: bool = false

## Undo stack — each entry is {key: String, from: float, to: float}.
var _undo_stack: Array[Dictionary] = []
const UNDO_STACK_MAX: int = 20
## True while performing an undo so the value_changed handler doesn't push.
var _suppress_push: bool = false


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -320.0
	_panel.offset_right = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.09, 0.92)
	style.border_color = Color(0.5, 0.4, 0.2, 0.6)
	style.border_width_left = 2
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	_panel.add_child(main_vbox)

	# Title.
	var title := Label.new()
	title.text = "BALANCE TUNING"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	main_vbox.add_child(title)

	# Category selector.
	_category_selector = OptionButton.new()
	for cat_name in CATEGORY_NAMES:
		_category_selector.add_item(cat_name)
	_category_selector.item_selected.connect(_on_category_changed)
	main_vbox.add_child(_category_selector)

	# Separator.
	main_vbox.add_child(HSeparator.new())

	# Scroll area.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

	# Buttons.
	var btn_box := HBoxContainer.new()
	main_vbox.add_child(btn_box)

	var save_btn := Button.new()
	save_btn.text = "SAVE"
	save_btn.pressed.connect(_on_save)
	save_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	btn_box.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	reset_btn.pressed.connect(_on_reset)
	reset_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	btn_box.add_child(reset_btn)

	var apply_btn := Button.new()
	apply_btn.text = "APPLY LIVE"
	apply_btn.pressed.connect(_on_apply_live)
	apply_btn.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	btn_box.add_child(apply_btn)

	var undo_btn := Button.new()
	undo_btn.text = "UNDO"
	undo_btn.pressed.connect(_on_undo)
	undo_btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	btn_box.add_child(undo_btn)

	add_child(_panel)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F5:
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_populate_category()
	if DevConsole:
		DevConsole.log_system("Balance panel: %s" % ("ON" if _visible else "OFF"))


func _on_category_changed(idx: int) -> void:
	_current_category = idx as Category
	_populate_category()


func _populate_category() -> void:
	# Clear existing sliders.
	for child in _content.get_children():
		child.queue_free()
	_sliders.clear()

	match _current_category:
		Category.HERO:
			_populate_hero()
		Category.ENEMIES:
			_populate_enemies()
		Category.BUILDINGS:
			_populate_buildings()
		Category.WAVES:
			_populate_waves()


func _populate_hero() -> void:
	_add_section("Hero Stats")
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero == null:
		_add_label("Hero not found in scene.")
		return
	_add_slider("hero.move_speed", "Move Speed", hero.move_speed, 1.0, 15.0, 0.5)
	_add_slider("hero.max_hp", "Max HP", hero.max_hp, 10.0, 1000.0, 10.0)
	_add_slider("hero.attack_damage", "Attack Damage", hero.attack_damage, 1.0, 100.0, 1.0)
	_add_slider("hero.attack_range", "Attack Range", hero.attack_range, 1.0, 15.0, 0.5)
	_add_slider("hero.attack_speed", "Attack Speed", hero.attack_speed, 0.1, 10.0, 0.1)
	_add_slider("hero.respawn_delay", "Respawn Delay", hero.respawn_delay, 0.5, 15.0, 0.5)
	_add_slider("hero.night_speed_multiplier", "Night Speed Multi", hero.night_speed_multiplier, 1.0, 5.0, 0.1)


func _populate_enemies() -> void:
	var all_enemies: Array = EnemyRegistry.get_all()
	for data in all_enemies:
		_add_section(data.display_name)
		var key_prefix: String = "enemy.%s" % data.id
		_add_slider("%s.max_hp" % key_prefix, "Max HP", data.max_hp, 1.0, 500.0, 5.0)
		_add_slider("%s.move_speed" % key_prefix, "Move Speed", data.move_speed, 0.5, 10.0, 0.25)
		_add_slider("%s.attack_damage" % key_prefix, "Attack Damage", data.attack_damage, 1.0, 100.0, 1.0)
		_add_slider("%s.attack_speed" % key_prefix, "Attack Speed", data.attack_speed, 0.1, 5.0, 0.1)
		_add_slider("%s.attack_range" % key_prefix, "Attack Range", data.attack_range, 0.3, 5.0, 0.1)


func _populate_buildings() -> void:
	var all_buildings: Array = BuildingRegistry.get_all()
	for data in all_buildings:
		_add_section("%s (L1-L%d)" % [data.display_name, data.max_level])
		var key_prefix: String = "building.%s" % data.id
		for lvl in range(1, data.max_level + 1):
			_add_slider("%s.hp.%d" % [key_prefix, lvl], "L%d Max HP" % lvl, data.get_max_hp(lvl), 10.0, 2000.0, 10.0)
			if data.is_offensive():
				_add_slider("%s.dmg.%d" % [key_prefix, lvl], "L%d Damage" % lvl, data.get_attack_damage(lvl), 1.0, 100.0, 1.0)
				_add_slider("%s.range.%d" % [key_prefix, lvl], "L%d Range" % lvl, data.get_attack_range(lvl), 1.0, 15.0, 0.5)
				_add_slider("%s.aspd.%d" % [key_prefix, lvl], "L%d Atk Speed" % lvl, data.get_attack_speed(lvl), 0.1, 5.0, 0.1)


func _populate_waves() -> void:
	_add_section("Wave Scaling")
	_add_slider("wave.base_wasps", "Base Wasp Count", 3.0, 1.0, 20.0, 1.0)
	_add_slider("wave.wasps_per_day", "Wasps per Day", 2.0, 0.0, 10.0, 1.0)
	_add_slider("wave.hornet_start", "Hornet Start Day", 2.0, 1.0, 10.0, 1.0)
	_add_slider("wave.spawn_interval", "Spawn Interval (s)", 0.45, 0.1, 2.0, 0.05)


func _add_section(title: String) -> void:
	var sep := HSeparator.new()
	_content.add_child(sep)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_content.add_child(label)


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_content.add_child(label)


func _add_slider(key: String, label_text: String, default_val: float, min_val: float, max_val: float, step: float) -> void:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120.0
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 100.0
	hbox.add_child(slider)

	var value_label := Label.new()
	value_label.text = _format_value(default_val)
	value_label.custom_minimum_size.x = 50.0
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	hbox.add_child(value_label)

	var last_val_ref := {"value": default_val}
	slider.value_changed.connect(func(val: float) -> void:
		value_label.text = _format_value(val)
		_dirty = true
		if not _suppress_push:
			_push_undo(key, float(last_val_ref["value"]), val)
		last_val_ref["value"] = val
	)

	_sliders[key] = {"slider": slider, "value_label": value_label, "default": default_val}
	_content.add_child(hbox)


func _format_value(val: float) -> String:
	if absf(val - roundf(val)) < 0.01:
		return "%.0f" % val
	return "%.2f" % val


func _on_apply_live() -> void:
	_apply_hero_stats()
	_apply_enemy_stats()
	_apply_building_stats()
	_apply_wave_stats()
	_dirty = false
	if DevConsole:
		DevConsole.log_system("Balance changes applied live.")


func _apply_hero_stats() -> void:
	var hero: Node3D = get_tree().get_first_node_in_group(&"hero")
	if hero == null:
		return
	_apply_if_exists("hero.move_speed", func(v: float) -> void: hero.move_speed = v)
	_apply_if_exists("hero.max_hp", func(v: float) -> void:
		hero.max_hp = v
		if hero.health:
			hero.health.set_max_hp(v, false)
	)
	_apply_if_exists("hero.attack_damage", func(v: float) -> void: hero.attack_damage = v)
	_apply_if_exists("hero.attack_range", func(v: float) -> void: hero.attack_range = v)
	_apply_if_exists("hero.attack_speed", func(v: float) -> void: hero.attack_speed = v)
	_apply_if_exists("hero.respawn_delay", func(v: float) -> void: hero.respawn_delay = v)
	_apply_if_exists("hero.night_speed_multiplier", func(v: float) -> void: hero.night_speed_multiplier = v)


func _apply_enemy_stats() -> void:
	var all_enemies: Array = EnemyRegistry.get_all()
	for data in all_enemies:
		var prefix: String = "enemy.%s" % data.id
		_apply_if_exists("%s.max_hp" % prefix, func(v: float) -> void: data.max_hp = v)
		_apply_if_exists("%s.move_speed" % prefix, func(v: float) -> void: data.move_speed = v)
		_apply_if_exists("%s.attack_damage" % prefix, func(v: float) -> void: data.attack_damage = v)
		_apply_if_exists("%s.attack_speed" % prefix, func(v: float) -> void: data.attack_speed = v)
		_apply_if_exists("%s.attack_range" % prefix, func(v: float) -> void: data.attack_range = v)


func _apply_building_stats() -> void:
	var all_buildings: Array = BuildingRegistry.get_all()
	for data in all_buildings:
		var prefix: String = "building.%s" % data.id
		for lvl in range(1, data.max_level + 1):
			var idx: int = lvl - 1
			_apply_if_exists("%s.hp.%d" % [prefix, lvl], func(v: float) -> void:
				if idx < data.max_hp_per_level.size():
					data.max_hp_per_level[idx] = v
			)
			if data.is_offensive():
				_apply_if_exists("%s.dmg.%d" % [prefix, lvl], func(v: float) -> void:
					if idx < data.attack_damage_per_level.size():
						data.attack_damage_per_level[idx] = v
				)
				_apply_if_exists("%s.range.%d" % [prefix, lvl], func(v: float) -> void:
					if idx < data.attack_range_per_level.size():
						data.attack_range_per_level[idx] = v
				)
				_apply_if_exists("%s.aspd.%d" % [prefix, lvl], func(v: float) -> void:
					if idx < data.attack_speed_per_level.size():
						data.attack_speed_per_level[idx] = v
				)


func _apply_wave_stats() -> void:
	var wave_mgr: Node = get_tree().current_scene.get_node_or_null("WaveManager")
	if wave_mgr == null:
		return
	# Wave stats are applied via metadata - WaveManager reads them on next wave.
	_apply_if_exists("wave.spawn_interval", func(v: float) -> void:
		if "spawn_interval" in wave_mgr:
			wave_mgr.spawn_interval = v
	)


func _apply_if_exists(key: String, setter: Callable) -> void:
	if _sliders.has(key):
		setter.call(_sliders[key]["slider"].value)


func _on_save() -> void:
	_on_apply_live()

	# Save enemy data.
	var all_enemies: Array = EnemyRegistry.get_all()
	for data in all_enemies:
		ResourceSaver.save(data, data.resource_path)

	# Save building data.
	var all_buildings: Array = BuildingRegistry.get_all()
	for data in all_buildings:
		ResourceSaver.save(data, data.resource_path)

	_dirty = false
	if DevConsole:
		DevConsole.log_system("Balance data saved to .tres files.")


func _on_reset() -> void:
	# Reload resources from disk.
	_suppress_push = true
	for key: String in _sliders:
		var info: Dictionary = _sliders[key]
		info["slider"].value = info["default"]
		info["value_label"].text = _format_value(info["default"])
	_suppress_push = false
	_undo_stack.clear()
	_dirty = false
	if DevConsole:
		DevConsole.log_system("Balance values reset to defaults.")


func _push_undo(key: String, from_value: float, to_value: float) -> void:
	if is_equal_approx(from_value, to_value):
		return
	_undo_stack.append({"key": key, "from": from_value, "to": to_value})
	if _undo_stack.size() > UNDO_STACK_MAX:
		_undo_stack.pop_front()


func _on_undo() -> void:
	if _undo_stack.is_empty():
		if DevConsole:
			DevConsole.log_warning("Undo stack is empty.")
		return
	var entry: Dictionary = _undo_stack.pop_back()
	var key: String = entry["key"]
	if not _sliders.has(key):
		return
	_suppress_push = true
	var info: Dictionary = _sliders[key]
	info["slider"].value = float(entry["from"])
	info["value_label"].text = _format_value(float(entry["from"]))
	_suppress_push = false
	if DevConsole:
		DevConsole.log_system("Undo: %s %.2f -> %.2f" % [key, float(entry["to"]), float(entry["from"])])
