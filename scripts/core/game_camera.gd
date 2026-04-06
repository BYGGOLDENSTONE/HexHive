class_name GameCamera
extends Camera2D
## Camera locked to the hero with smooth follow and zoom.

## Zoom limits
@export var zoom_min: float = 0.3
@export var zoom_max: float = 3.0
@export var zoom_step: float = 0.1

## Smooth zoom interpolation speed.
@export var zoom_smoothing: float = 10.0

## Camera follow interpolation speed (higher = snappier).
@export var follow_smoothing: float = 8.0

## Target zoom for smooth interpolation.
var _target_zoom: float = 1.0

## The node to follow.
@onready var _target: Node2D = %Hero


func _ready() -> void:
	_target_zoom = zoom.x
	if _target:
		position = _target.position


func _process(delta: float) -> void:
	_follow_target(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom + zoom_step, zoom_min, zoom_max)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom - zoom_step, zoom_min, zoom_max)


func _follow_target(delta: float) -> void:
	if _target:
		var t := minf(follow_smoothing * delta, 1.0)
		position = position.lerp(_target.position, t)


func _smooth_zoom(delta: float) -> void:
	var current: float = zoom.x
	var new_zoom: float = lerpf(current, _target_zoom, zoom_smoothing * delta)
	zoom = Vector2(new_zoom, new_zoom)
