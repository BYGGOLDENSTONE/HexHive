class_name GameCamera
extends Camera3D
## Isometric-style 3D camera that follows the hero with smooth movement and zoom.

## Camera pitch angle in degrees (measured from horizontal).
@export var pitch_angle: float = 55.0

## Default distance from the target.
@export var default_distance: float = 15.0

## Minimum zoom distance.
@export var zoom_min: float = 5.0

## Maximum zoom distance.
@export var zoom_max: float = 35.0

## Zoom step per scroll wheel tick.
@export var zoom_step: float = 1.0

## Smooth zoom interpolation speed.
@export var zoom_smoothing: float = 8.0

## Camera follow interpolation speed (higher = snappier).
@export var follow_smoothing: float = 8.0

## Target distance for smooth interpolation.
var _target_distance: float = 30.0

## Current smoothed distance.
var _current_distance: float = 30.0

## The node to follow.
@onready var _target: Node3D = %Hero


func _ready() -> void:
	_target_distance = default_distance
	_current_distance = default_distance
	if _target:
		_update_transform(_target.global_position)


func _process(delta: float) -> void:
	_follow_target(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_distance = clampf(_target_distance - zoom_step, zoom_min, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_distance = clampf(_target_distance + zoom_step, zoom_min, zoom_max)


func _follow_target(delta: float) -> void:
	if _target == null:
		return
	var target_pos: Vector3 = _target.global_position
	# Smooth follow the target's XZ position at ground level.
	var current_look: Vector3 = _get_look_at_point()
	var t: float = minf(follow_smoothing * delta, 1.0)
	var smoothed_pos: Vector3 = current_look.lerp(target_pos, t)
	_update_transform(smoothed_pos)


func _smooth_zoom(delta: float) -> void:
	_current_distance = lerpf(_current_distance, _target_distance, zoom_smoothing * delta)
	if _target:
		_update_transform(_get_look_at_point())


func _update_transform(look_at_pos: Vector3) -> void:
	var pitch_rad: float = deg_to_rad(pitch_angle)
	var offset: Vector3 = Vector3(
		0.0,
		sin(pitch_rad) * _current_distance,
		cos(pitch_rad) * _current_distance
	)
	global_position = look_at_pos + offset
	look_at(look_at_pos, Vector3.UP)


func _get_look_at_point() -> Vector3:
	# Reverse-compute where the camera is currently looking at.
	var pitch_rad: float = deg_to_rad(pitch_angle)
	var offset: Vector3 = Vector3(
		0.0,
		sin(pitch_rad) * _current_distance,
		cos(pitch_rad) * _current_distance
	)
	return global_position - offset
