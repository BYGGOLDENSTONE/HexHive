class_name PhaseHUD
extends CanvasLayer
## Displays the current phase, day/night number, and day timer.
## Shows a "Start Day" prompt during night phase.

## Phase label node.
@onready var phase_label: Label = %PhaseLabel

## Day timer progress bar.
@onready var day_progress: ProgressBar = %DayProgress

## Start day prompt container.
@onready var start_day_prompt: PanelContainer = %StartDayPrompt

## Phase banner that shows briefly on transitions.
@onready var phase_banner: Label = %PhaseBanner

## Banner tween reference.
var _banner_tween: Tween


func _ready() -> void:
	SignalBus.day_started.connect(_on_day_started)
	SignalBus.night_started.connect(_on_night_started)

	# Initial state — Night 0
	_show_night(0)


func _process(_delta: float) -> void:
	if DayNightManager.is_day():
		day_progress.value = DayNightManager.get_day_progress() * 100.0
		var remaining: float = DayNightManager.get_day_time_remaining()
		phase_label.text = "Day %d  —  %ds" % [DayNightManager.day_number, ceili(remaining)]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_day"):
		SignalBus.start_day_requested.emit()


func _on_day_started(day_number: int) -> void:
	_show_day(day_number)
	_show_banner("Day %d" % day_number, Color(1.0, 0.85, 0.3))


func _on_night_started(night_number: int) -> void:
	_show_night(night_number)
	if night_number > 0:
		_show_banner("Night %d" % night_number, Color(0.6, 0.7, 1.0))


func _show_day(day_number: int) -> void:
	phase_label.text = "Day %d" % day_number
	phase_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	day_progress.visible = true
	day_progress.value = 0.0
	start_day_prompt.visible = false


func _show_night(night_number: int) -> void:
	phase_label.text = "Night %d" % night_number
	phase_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	day_progress.visible = false
	start_day_prompt.visible = true


func _show_banner(text: String, color: Color) -> void:
	phase_banner.text = text
	phase_banner.add_theme_color_override("font_color", color)
	phase_banner.modulate.a = 1.0
	phase_banner.visible = true

	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_tween = create_tween()
	_banner_tween.set_ease(Tween.EASE_IN)
	_banner_tween.set_trans(Tween.TRANS_CUBIC)
	_banner_tween.tween_interval(1.5)
	_banner_tween.tween_property(phase_banner, "modulate:a", 0.0, 1.0)
	_banner_tween.tween_callback(func(): phase_banner.visible = false)
