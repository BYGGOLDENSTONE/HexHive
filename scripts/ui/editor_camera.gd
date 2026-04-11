extends Camera3D
## Free camera for the map editor. WASD pan, scroll zoom, middle-mouse drag.

@export var pan_speed: float = 15.0
@export var zoom_speed: float = 2.0
@export var zoom_min: float = 5.0
@export var zoom_max: float = 35.0
@export var pitch_angle: float = 55.0

var _target_position: Vector3 = Vector3.ZERO
var _camera_distance: float = 18.0
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	_update_camera_transform()


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_update_camera_transform()


func _handle_keyboard_pan(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_up") or Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_down") or Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		_target_position.x += input_dir.x * pan_speed * delta
		_target_position.z += input_dir.y * pan_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(_camera_distance - zoom_speed, zoom_min)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(_camera_distance + zoom_speed, zoom_max)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = mb.pressed
			_drag_start = mb.position

	if event is InputEventMouseMotion and _is_dragging:
		var motion := event as InputEventMouseMotion
		var drag_sensitivity: float = _camera_distance * 0.003
		_target_position.x -= motion.relative.x * drag_sensitivity
		_target_position.z -= motion.relative.y * drag_sensitivity


func _update_camera_transform() -> void:
	var pitch_rad: float = deg_to_rad(pitch_angle)
	var offset := Vector3(
		0.0,
		sin(pitch_rad) * _camera_distance,
		cos(pitch_rad) * _camera_distance
	)
	global_position = _target_position + offset
	look_at(_target_position, Vector3.UP)
