class_name GameOverScreen
extends CanvasLayer
## Full-screen overlay shown when the Hive is destroyed.
## Displays the final day reached and a Restart button.

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
	restart_button.pressed.connect(_on_restart_pressed)


func _on_hive_destroyed() -> void:
	if _shown:
		return
	_shown = true
	# Pause briefly so the destruction animation is visible, then fade in.
	await get_tree().create_timer(0.7).timeout

	subtitle_label.text = "You fell on Day %d." % DayNightManager.day_number
	root.visible = true
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(root, "modulate:a", 1.0, 0.6)
	SignalBus.game_over.emit(DayNightManager.day_number)


func _on_restart_pressed() -> void:
	# Reload the current scene for a clean reset.
	get_tree().reload_current_scene()
