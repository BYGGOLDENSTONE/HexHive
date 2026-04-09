extends Resource
## Defines an enemy type with stats, tags, and 3D model data.
## Each enemy type is a .tres file in resources/enemies/.

## Unique identifier for this enemy type.
@export var id: StringName = &""

## Display name shown in UI/debug.
@export var display_name: String = ""

## Tags for the tag-based system (e.g. &"flying", &"armored", &"swarm").
@export var tags: Array[StringName] = []

## Maximum hit points.
@export var max_hp: float = 30.0

## Movement speed in world units per second.
@export var move_speed: float = 4.0

## Damage dealt per attack.
@export var attack_damage: float = 5.0

## Attacks per second (1.5 = one attack every ~0.67s).
@export var attack_speed: float = 1.5

## Attack reach in world units (target must be within this distance to be hit).
@export var attack_range: float = 1.6

## Time after spawn before AI is enabled (lets fade-in animation play).
@export var spawn_delay: float = 0.25

# -- 3D Model --

## Path to the GLB model scene. Empty = no visual.
@export var model_path: String = ""

## Uniform scale multiplier for the model.
@export var model_scale: float = 1.0

## Vertical offset for the model (positive = up).
@export var model_y_offset: float = 0.0

## Material tint override (white = no tint, use model's own materials).
@export var material_tint: Color = Color.WHITE

# -- Legacy 2D fields (kept for .tres compat, ignored at runtime) --
@export var visual_size: float = 18.0
@export var sprite_dir: StringName = &""
@export var sprite_scale_factor: float = 2.4
@export var body_color: Color = Color(0.95, 0.85, 0.2, 1.0)
@export var accent_color: Color = Color(0.1, 0.08, 0.05, 1.0)
@export var wing_color: Color = Color(0.95, 0.95, 1.0, 0.55)
@export var eye_color: Color = Color(1.0, 0.3, 0.2, 1.0)
