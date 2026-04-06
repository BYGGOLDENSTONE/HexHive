class_name BuildMenu
extends CanvasLayer
## Build menu panel that shows available buildings during night phase.
## Automatically opens at night, closes at day.

@onready var panel: PanelContainer = %BuildPanel
@onready var button_container: VBoxContainer = %ButtonContainer

## Currently highlighted button (for selected building).
var _selected_button: Button = null

## Ordered list of building ids matching button order.
var _building_ids: Array[StringName] = []

## Quick-build action map (1-indexed).
var _quick_actions: Array[StringName] = [&"quick_build_1", &"quick_build_2", &"quick_build_3"]

## Slide tween reference.
var _slide_tween: Tween


func _ready() -> void:
	layer = 10
	SignalBus.phase_changed.connect(_on_phase_changed)
	SignalBus.build_preview_started.connect(_on_build_preview_started)
	SignalBus.build_preview_ended.connect(_on_build_preview_ended)

	_populate_buttons()
	# Start hidden (game starts at night but we show after a brief delay)
	panel.modulate.a = 0.0
	panel.visible = false
	# Night 0 auto-show
	call_deferred("_show_menu")


func _populate_buttons() -> void:
	# Clear existing children
	for child in button_container.get_children():
		child.queue_free()

	_building_ids.clear()
	var buildable := BuildingRegistry.get_all_buildable()

	for i in range(buildable.size()):
		var data: Resource = buildable[i]
		_building_ids.append(data.id)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(130, 60)
		btn.text = "%s\n%s" % [data.display_name, data.description]

		# Shortcut number label
		if i < _quick_actions.size():
			btn.text = "[%d] %s\n%s" % [i + 1, data.display_name, data.description]

		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.12, 0.08, 0.85)
		style.border_color = Color(0.6, 0.5, 0.3, 0.6)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", style)

		var hover_style := style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.25, 0.2, 0.12, 0.9)
		hover_style.border_color = Color(0.9, 0.7, 0.3, 0.8)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = Color(0.3, 0.25, 0.1, 0.95)
		pressed_style.border_color = Color(1.0, 0.8, 0.3, 1.0)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.5))

		var building_id: StringName = data.id
		btn.pressed.connect(func(): _on_button_pressed(building_id))
		button_container.add_child(btn)


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	# Quick-build shortcuts (1, 2, 3)
	for i in range(_quick_actions.size()):
		if i < _building_ids.size() and event.is_action_pressed(_quick_actions[i]):
			_on_button_pressed(_building_ids[i])
			get_viewport().set_input_as_handled()
			return


func _on_button_pressed(building_id: StringName) -> void:
	SignalBus.build_requested.emit(building_id)


func _on_phase_changed(phase: StringName) -> void:
	if phase == &"night":
		_show_menu()
	else:
		_hide_menu()


func _on_build_preview_started(building_data: Resource) -> void:
	# Highlight the selected button
	_clear_selection()
	var idx := _building_ids.find(building_data.id)
	if idx >= 0 and idx < button_container.get_child_count():
		_selected_button = button_container.get_child(idx) as Button
		if _selected_button:
			var sel_style := StyleBoxFlat.new()
			sel_style.bg_color = Color(0.35, 0.28, 0.1, 0.95)
			sel_style.border_color = Color(1.0, 0.85, 0.3, 1.0)
			sel_style.set_border_width_all(3)
			sel_style.set_corner_radius_all(6)
			sel_style.set_content_margin_all(8)
			_selected_button.add_theme_stylebox_override("normal", sel_style)


func _on_build_preview_ended() -> void:
	_clear_selection()


func _clear_selection() -> void:
	if _selected_button:
		# Restore default style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.12, 0.08, 0.85)
		style.border_color = Color(0.6, 0.5, 0.3, 0.6)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		_selected_button.add_theme_stylebox_override("normal", style)
		_selected_button = null


func _show_menu() -> void:
	panel.visible = true
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(panel, "modulate:a", 1.0, 0.4)


func _hide_menu() -> void:
	_clear_selection()
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_IN)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	_slide_tween.tween_callback(func(): panel.visible = false)
