extends Node
## Global audio bus. Listens to SignalBus events and plays SFX via pooled
## AudioStreamPlayer nodes. Missing files log a one-time warning and are silent
## — so the system is safe to ship without audio assets.
##
## SFX files live under res://assets/audio/sfx/ using the conventional names
## below. Replace the placeholder .ogg/.wav files with CC0 / licensed assets;
## see assets/audio/LICENSES.md for sourcing notes.

## Mapping from event id (StringName) to expected file path.
const SFX_PATHS: Dictionary = {
	&"build_place":       "res://assets/audio/sfx/build_place.ogg",
	&"projectile_fire":   "res://assets/audio/sfx/projectile_fire.ogg",
	&"projectile_hit":    "res://assets/audio/sfx/projectile_hit.ogg",
	&"enemy_death":       "res://assets/audio/sfx/enemy_death.ogg",
	&"hive_hit":          "res://assets/audio/sfx/hive_hit.ogg",
	&"phase_transition":  "res://assets/audio/sfx/phase_transition.ogg",
}

## Base volume per event in decibels (negative = quieter).
const SFX_VOLUME_DB: Dictionary = {
	&"build_place": -4.0,
	&"projectile_fire": -12.0,
	&"projectile_hit": -8.0,
	&"enemy_death": -6.0,
	&"hive_hit": -2.0,
	&"phase_transition": -4.0,
}

## Random pitch variance per event (±half_range).
const SFX_PITCH_VARIANCE: float = 0.12

## Pool size for rapid-fire events (projectiles / hits overlap).
const POOL_SIZE: int = 8

## Master volume multiplier (0-1). Bus-level control.
@export_range(0.0, 1.0) var master_volume: float = 0.85

## Per-event stream cache (StringName -> AudioStream or null if missing).
var _streams: Dictionary = {}

## Pool of AudioStreamPlayer nodes — round-robin.
var _pool: Array = []
var _pool_index: int = 0

## Tracks event names we've already warned about so we don't spam logs.
var _warned_missing: Dictionary = {}


func _ready() -> void:
	_build_player_pool()
	_preload_streams()
	_connect_signals()


func _build_player_pool() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % i
		player.bus = &"Master"
		add_child(player)
		_pool.append(player)


func _preload_streams() -> void:
	for event_name in SFX_PATHS.keys():
		var path: String = SFX_PATHS[event_name]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			_streams[event_name] = stream
		else:
			_streams[event_name] = null


func _connect_signals() -> void:
	# Building placement feedback.
	SignalBus.building_placed.connect(func(_id: StringName, _coord: Vector2i, _level: int) -> void:
		play(&"build_place")
	)
	# Building upgrade reuses the place sound at slightly higher pitch.
	SignalBus.building_upgraded.connect(func(_coord: Vector2i, _new_level: int) -> void:
		play(&"build_place", 1.15)
	)
	# Enemy death.
	SignalBus.enemy_died.connect(func(_enemy: Node) -> void:
		play(&"enemy_death")
	)
	# Hive damage — big warning sound, no pitch variance.
	SignalBus.hive_damaged.connect(func(_amount: float, _current: float, _maximum: float) -> void:
		play(&"hive_hit", 1.0, 0.0)
	)
	# Phase transitions.
	SignalBus.day_started.connect(func(_day: int) -> void:
		play(&"phase_transition", 1.1)
	)
	SignalBus.night_started.connect(func(_night: int) -> void:
		play(&"phase_transition", 0.9)
	)
	# Projectile fire is invoked directly from hero/turret code (no signal yet).


## Public: play a named SFX. Optional pitch multiplier and custom pitch variance.
## If the stream is missing, silently no-op (and warn once).
func play(event_name: StringName, pitch_multiplier: float = 1.0, pitch_variance: float = SFX_PITCH_VARIANCE) -> void:
	if not _streams.has(event_name):
		return
	var stream: AudioStream = _streams[event_name]
	if stream == null:
		if not _warned_missing.has(event_name):
			_warned_missing[event_name] = true
			var path: String = SFX_PATHS.get(event_name, "<unknown>")
			push_warning("[AudioBus] Missing SFX file: %s (event %s). Silent fallback." % [path, event_name])
		return

	var player: AudioStreamPlayer = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = stream
	var base_db: float = float(SFX_VOLUME_DB.get(event_name, 0.0))
	player.volume_db = base_db + linear_to_db(master_volume)
	var variance: float = pitch_variance
	player.pitch_scale = clampf(pitch_multiplier + randf_range(-variance, variance), 0.5, 2.0)
	player.play()
