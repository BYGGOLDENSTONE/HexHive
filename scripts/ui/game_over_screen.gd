class_name GameOverScreen
extends CanvasLayer
## Full-screen overlay shown on lose (Hive destroyed) or win (victory day cleared).
## Displays the final day reached and a Restart / New Run button.

@onready var root: Control = %Root
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var restart_button: Button = %RestartButton

var _shown: bool = false


func _ready() -> void:
	layer = 100
	root.visible = false
	root.modulate.a = 0.0
	SignalBus.hive_destroyed.connect(_on_hive_destroyed)
	SignalBus.run_won.connect(_on_run_won)
	restart_button.pressed.connect(_on_restart_pressed)


func _on_hive_destroyed() -> void:
	if _shown:
		return
	_shown = true
	# Pause briefly so the destruction animation is visible, then fade in.
	await get_tree().create_timer(0.7).timeout

	title_label.text = "Game Over"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.25))
	subtitle_label.text = "You fell on Day %d." % DayNightManager.day_number
	restart_button.text = "Restart"
	_fade_in()
	SignalBus.game_over.emit(DayNightManager.day_number)


func _on_run_won(final_day: int) -> void:
	if _shown:
		return
	_shown = true
	# Short celebration beat before the screen appears.
	await get_tree().create_timer(0.9).timeout

	title_label.text = "Victory!"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	subtitle_label.text = "You survived Day %d and saved the Hive." % final_day
	restart_button.text = "New Run"
	_fade_in()


func _fade_in() -> void:
	root.visible = true
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(root, "modulate:a", 1.0, 0.6)


func _on_restart_pressed() -> void:
	# Reset run state via the signal bus so autoloads can hear it,
	# then reload the scene for a clean visual/entity reset.
	SignalBus.restart_requested.emit()
	get_tree().reload_current_scene()
