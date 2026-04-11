extends Control
## Main menu with Play Game and Map Editor options.


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Full screen background.
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center container.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "HexHive"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	# Subtitle.
	var subtitle := Label.new()
	subtitle.text = "Defend Your Hive"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	vbox.add_child(subtitle)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	# Play button.
	var play_btn := _create_menu_button("Play Game", Color(0.3, 0.6, 0.2))
	play_btn.pressed.connect(_on_play)
	vbox.add_child(play_btn)

	# Map Editor button.
	var editor_btn := _create_menu_button("Map Editor", Color(0.2, 0.45, 0.65))
	editor_btn.pressed.connect(_on_map_editor)
	vbox.add_child(editor_btn)

	# Quit button.
	var quit_btn := _create_menu_button("Quit", Color(0.5, 0.3, 0.3))
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)


func _create_menu_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 55)
	btn.add_theme_font_size_override("font_size", 22)

	var normal := StyleBoxFlat.new()
	normal.bg_color = color * 0.7
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color
	hover.set_corner_radius_all(8)
	hover.set_content_margin_all(12)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color * 1.2
	pressed.set_corner_radius_all(8)
	pressed.set_content_margin_all(12)
	btn.add_theme_stylebox_override("pressed", pressed)

	return btn


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")


func _on_map_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/main/map_editor_scene.tscn")


func _on_quit() -> void:
	get_tree().quit()
