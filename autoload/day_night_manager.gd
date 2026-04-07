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

## Whether a phase transition is currently in progress.
var _transitioning: bool = false

## Live wave state — populated by SignalBus wave signals.
var _wave_total: int = 0
var _wave_remaining: int = 0


func _ready() -> void:
	SignalBus.start_day_requested.connect(_on_start_day_requested)
	SignalBus.day_wave_cleared.connect(_on_day_wave_cleared)
	SignalBus.wave_started.connect(_on_wave_started)
	SignalBus.wave_progress_changed.connect(_on_wave_progress_changed)
	SignalBus.restart_requested.connect(_on_restart_requested)

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


func _on_wave_started(_day: int, total: int) -> void:
	_wave_total = total
	_wave_remaining = total


func _on_wave_progress_changed(remaining: int, total: int) -> void:
	_wave_remaining = remaining
	_wave_total = total


func _on_restart_requested() -> void:
	# Reset state for a fresh run.
	day_number = 0
	night_number = 0
	_wave_total = 0
	_wave_remaining = 0
	_transitioning = false
	_enter_night()


func _transition_to_day() -> void:
	_transitioning = true
	day_number += 1
	current_phase = Phase.DAY

	SignalBus.phase_changed.emit(&"day")
	SignalBus.day_started.emit(day_number)

	_transitioning = false


func _transition_to_night() -> void:
	_transitioning = true
	night_number += 1
	current_phase = Phase.NIGHT
	_wave_total = 0
	_wave_remaining = 0

	SignalBus.phase_changed.emit(&"night")
	SignalBus.night_started.emit(night_number)

	_transitioning = false


func _enter_night() -> void:
	current_phase = Phase.NIGHT
	SignalBus.phase_changed.emit(&"night")
	SignalBus.night_started.emit(night_number)


## Returns wave progress as 0-1 fraction (defeated / total). 0 if no wave active.
func get_day_progress() -> float:
	if current_phase != Phase.DAY or _wave_total <= 0:
		return 0.0
	var defeated: int = _wave_total - _wave_remaining
	return clampf(float(defeated) / float(_wave_total), 0.0, 1.0)


## Returns the current wave's remaining enemy count (alive + queued).
func get_wave_remaining() -> int:
	return _wave_remaining


## Returns the current wave's total enemy count.
func get_wave_total() -> int:
	return _wave_total


## Returns true if currently in night phase.
func is_night() -> bool:
	return current_phase == Phase.NIGHT


## Returns true if currently in day phase.
func is_day() -> bool:
	return current_phase == Phase.DAY
