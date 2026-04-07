extends Resource
## Defines an enemy type with stats, tags, and visual data.
## Each enemy type is a .tres file in resources/enemies/.

## Unique identifier for this enemy type.
@export var id: StringName = &""

## Display name shown in UI/debug.
@export var display_name: String = ""

## Tags for the tag-based system (e.g. &"flying", &"armored", &"swarm").
@export var tags: Array[StringName] = []

## Maximum hit points.
@export var max_hp: float = 30.0

## Movement speed in pixels per second.
@export var move_speed: float = 90.0

## Damage dealt per attack.
@export var attack_damage: float = 5.0

## Attacks per second (1.5 = one attack every ~0.67s).
@export var attack_speed: float = 1.5

## Attack reach in world pixels (target must be within this distance to be hit).
@export var attack_range: float = 36.0

## Time after spawn before AI is enabled (lets fade-in animation play).
@export var spawn_delay: float = 0.25

## Visual size in pixels (radius of the body).
@export var visual_size: float = 18.0

## Body fill color.
@export var body_color: Color = Color(0.95, 0.85, 0.2, 1.0)

## Stripe / accent color.
@export var accent_color: Color = Color(0.1, 0.08, 0.05, 1.0)

## Wing color (semi-transparent).
@export var wing_color: Color = Color(0.95, 0.95, 1.0, 0.55)

## Eye glow color.
@export var eye_color: Color = Color(1.0, 0.3, 0.2, 1.0)
