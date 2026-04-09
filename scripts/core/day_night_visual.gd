class_name DayNightVisual
extends Node3D
## Controls 3D lighting for day/night transitions.
## Manages a DirectionalLight3D (sun) and WorldEnvironment (ambient).

## Night sun color — cool moonlight.
@export var night_light_color: Color = Color(0.4, 0.45, 0.7)
## Night sun energy.
@export var night_light_energy: float = 0.3
## Night ambient light color.
@export var night_ambient_color: Color = Color(0.15, 0.18, 0.3)
## Night ambient energy.
@export var night_ambient_energy: float = 0.4

## Day sun color — warm sunlight.
@export var day_light_color: Color = Color(1.0, 0.95, 0.85)
## Day sun energy.
@export var day_light_energy: float = 1.2
## Day ambient light color.
@export var day_ambient_color: Color = Color(0.6, 0.58, 0.52)
## Day ambient energy.
@export var day_ambient_energy: float = 0.6

## Transition duration in seconds.
@export var transition_duration: float = 1.5

## Sun direction (Euler degrees).
@export var sun_rotation: Vector3 = Vector3(-55, -30, 0)

## Background clear color.
@export var bg_color: Color = Color(0.45, 0.65, 0.85)

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _environment: Environment
var _tween: Tween


func _ready() -> void:
	# Create DirectionalLight3D (sun)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = sun_rotation
	_sun.light_color = night_light_color
	_sun.light_energy = night_light_energy
	_sun.shadow_enabled = true
	add_child(_sun)

	# Create WorldEnvironment
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = bg_color
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = night_ambient_color
	_environment.ambient_light_energy = night_ambient_energy
	# Tonemap and SSAO configured via editor if needed.

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = _environment
	add_child(_world_env)

	SignalBus.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: StringName) -> void:
	if phase == &"day":
		_tween_to_day()
	else:
		_tween_to_night()


func _tween_to_day() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_sun, "light_color", day_light_color, transition_duration)
	_tween.tween_property(_sun, "light_energy", day_light_energy, transition_duration)
	_tween.tween_property(_environment, "ambient_light_color", day_ambient_color, transition_duration)
	_tween.tween_property(_environment, "ambient_light_energy", day_ambient_energy, transition_duration)


func _tween_to_night() -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_sun, "light_color", night_light_color, transition_duration)
	_tween.tween_property(_sun, "light_energy", night_light_energy, transition_duration)
	_tween.tween_property(_environment, "ambient_light_color", night_ambient_color, transition_duration)
	_tween.tween_property(_environment, "ambient_light_energy", night_ambient_energy, transition_duration)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
