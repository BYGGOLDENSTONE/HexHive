class_name GameCamera
extends Camera2D
## Camera with pan (WASD/arrow keys/middle mouse drag) and zoom (scroll wheel).

## Zoom limits
@export var zoom_min: float = 0.3
@export var zoom_max: float = 3.0
@export var zoom_step: float = 0.1

## Pan speed in pixels/second (at zoom 1.0)
@export var pan_speed: float = 600.0

## Smooth zoom lerp factor
@export var zoom_smoothing: float = 10.0

## Whether middle mouse drag is active
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

## Target zoom for smooth interpolation
var _target_zoom: float = 1.0


func _ready() -> void:
	_target_zoom = zoom.x


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Scroll wheel zoom
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom + zoom_step, zoom_min, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom - zoom_step, zoom_min, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_is_dragging = true
				_drag_start = mb.position
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = false

	# Middle mouse drag pan
	if event is InputEventMouseMotion and _is_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		position -= motion.relative / zoom.x


func _handle_keyboard_pan(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1.0

	if input_dir != Vector2.ZERO:
		position += input_dir.normalized() * pan_speed * delta / zoom.x


func _smooth_zoom(delta: float) -> void:
	var current: float = zoom.x
	var new_zoom: float = lerpf(current, _target_zoom, zoom_smoothing * delta)
	zoom = Vector2(new_zoom, new_zoom)
