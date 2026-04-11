class_name OnboardingOverlay
extends CanvasLayer
## First-run welcome overlay shown on Night 0 of a new run.
## Remembered via a user:// config file so returning players skip it.
## Pauses the game while visible.

const CONFIG_PATH: String = "user://onboarding.cfg"

@onready var root: Control = %Root
@onready var title_label: Label = %TitleLabel
@onready var line1: Label = %Line1
@onready var line2: Label = %Line2
@onready var line3: Label = %Line3
@onready var got_it_button: Button = %GotItButton

var _shown: bool = false


func _ready() -> void:
	layer = 50
	root.visible = false
	root.modulate.a = 0.0
	got_it_button.pressed.connect(_on_got_it_pressed)
	# Process even while paused so the button click registers.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Show once after the scene settles.
	call_deferred("_maybe_show")


func _maybe_show() -> void:
	if _has_seen():
		return
	_show()


func _show() -> void:
	_shown = true
	root.visible = true
	get_tree().paused = true
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(root, "modulate:a", 1.0, 0.35)
	got_it_button.grab_focus()


func _on_got_it_pressed() -> void:
	_mark_seen()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		root.visible = false
		get_tree().paused = false
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not root.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_on_got_it_pressed()
		get_viewport().set_input_as_handled()


func _has_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return false
	return cfg.get_value("onboarding", "seen", false) as bool


func _mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("onboarding", "seen", true)
	cfg.save(CONFIG_PATH)


## Dev utility — reset the "seen" flag so the overlay reappears on next run.
func clear_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("onboarding", "seen", false)
	cfg.save(CONFIG_PATH)
