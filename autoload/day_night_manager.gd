extends Node
## Manages the Day/Night cycle state machine.
## Night = safe building phase. Day = combat phase with enemy waves.
## Game starts at Night 0. Player manually triggers each new day.

enum Phase { NIGHT, DAY }

## Current phase.
var current_phase: Phase = Phase.NIGHT

## Current night number (starts at 0).
var night_number: int = 0

## Current day number (starts at 1 on first day).
var day_number: int = 0

## Duration of a day phase in seconds (placeholder until real waves exist).
@export var day_duration: float = 30.0

## Whether a phase transition is currently in progress.
var _transitioning: bool = false

## Timer for day phase duration.
var _day_timer: Timer


func _ready() -> void:
	_day_timer = Timer.new()
	_day_timer.one_shot = true
	_day_timer.timeout.connect(_on_day_timer_timeout)
	add_child(_day_timer)

	SignalBus.start_day_requested.connect(_on_start_day_requested)
	SignalBus.day_wave_cleared.connect(_on_day_wave_cleared)

	# Start at Night 0
	_enter_night()


func _on_start_day_requested() -> void:
	if current_phase != Phase.NIGHT or _transitioning:
		return
	_transition_to_day()


func _on_day_wave_cleared() -> void:
	if current_phase != Phase.DAY or _transitioning:
		return
	_transition_to_night()


func _on_day_timer_timeout() -> void:
	# Day timer expired — treat as wave cleared (placeholder until combat exists)
	if current_phase == Phase.DAY and not _transitioning:
		_transition_to_night()


func _transition_to_day() -> void:
	_transitioning = true
	day_number += 1
	current_phase = Phase.DAY

	SignalBus.phase_changed.emit(&"day")
	SignalBus.day_started.emit(day_number)

	# Start day timer (placeholder — will be replaced by wave system)
	_day_timer.start(day_duration)

	_transitioning = false


func _transition_to_night() -> void:
	_transitioning = true
	_day_timer.stop()
	night_number += 1
	current_phase = Phase.NIGHT

	SignalBus.phase_changed.emit(&"night")
	SignalBus.night_started.emit(night_number)

	_transitioning = false


func _enter_night() -> void:
	current_phase = Phase.NIGHT
	SignalBus.phase_changed.emit(&"night")
	SignalBus.night_started.emit(night_number)


## Returns time remaining in current day, or 0.0 if night.
func get_day_time_remaining() -> float:
	if current_phase == Phase.DAY and not _day_timer.is_stopped():
		return _day_timer.time_left
	return 0.0


## Returns progress of current day (0.0 to 1.0), or 0.0 if night.
func get_day_progress() -> float:
	if current_phase == Phase.DAY and not _day_timer.is_stopped():
		return 1.0 - (_day_timer.time_left / day_duration)
	return 0.0


## Returns true if currently in night phase.
func is_night() -> bool:
	return current_phase == Phase.NIGHT


## Returns true if currently in day phase.
func is_day() -> bool:
	return current_phase == Phase.DAY
