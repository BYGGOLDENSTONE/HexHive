extends Node
## Central signal bus for cross-system communication.
## All game-wide signals live here so modules never reference each other directly.

# -- Day/Night Cycle --

## Emitted when the game phase changes. phase is "day" or "night".
signal phase_changed(phase: StringName)

## Emitted at the start of a new day. day_number starts at 1.
signal day_started(day_number: int)

## Emitted at the start of a new night. night_number starts at 0.
signal night_started(night_number: int)

## Emitted when all enemies in a day wave are cleared (triggers night transition).
signal day_wave_cleared()

## Emitted when the player requests to start the next day.
signal start_day_requested()

# -- Building System --

## Player selected a building type from the build menu.
signal build_requested(building_id: StringName)

## Build preview ghost activated for a building type.
signal build_preview_started(building_data: Resource)

## Build preview moved to a new hex with validity info.
signal build_preview_moved(coord: Vector2i, is_valid: bool)

## Build preview ended (cancelled or placed).
signal build_preview_ended()

## Hero should auto-walk toward target hex for building.
signal build_walk_requested(target_coord: Vector2i)

## Hero auto-walk was cancelled by player input.
signal build_walk_cancelled()

## Hero reached within build range of the target hex.
signal hero_reached_build_range(target_coord: Vector2i)

## A building was successfully placed on the map.
signal building_placed(building_id: StringName, coord: Vector2i, level: int)

## A building was upgraded to a new level.
signal building_upgraded(coord: Vector2i, new_level: int)

## Hero is within range of an existing building.
signal hero_near_building(building_node: Node2D, coord: Vector2i)

## Hero left the proximity of a building.
signal hero_left_building()

## Upgrade requested for building at coord.
signal upgrade_requested(coord: Vector2i)

# -- Combat: Enemies --

## Emitted when an enemy spawns. enemy is the runtime Node2D.
signal enemy_spawned(enemy: Node2D)

## Emitted when an enemy dies. enemy is the runtime Node2D (still in tree this frame).
signal enemy_died(enemy: Node2D)

## Emitted when an enemy takes damage. amount > 0.
signal enemy_damaged(enemy: Node2D, amount: float)

# -- Combat: Hero --

## Emitted when the hero takes damage.
signal hero_damaged(amount: float, current_hp: float, max_hp: float)

## Emitted when the hero's HP reaches zero.
signal hero_died()

## Emitted when the hero respawns at the Hive.
signal hero_respawned()

# -- Combat: Hive & Buildings --

## Emitted when the Hive takes damage.
signal hive_damaged(amount: float, current_hp: float, max_hp: float)

## Emitted when the Hive HP reaches zero (game over trigger).
signal hive_destroyed()

## Emitted when any building takes damage.
signal building_damaged(building_node: Node2D, amount: float)

## Emitted when a non-Hive building is destroyed by enemies.
signal building_destroyed(building_node: Node2D, coord: Vector2i)

# -- Combat: Waves --

## Emitted when a new wave begins. total_enemies is the planned spawn count.
signal wave_started(day_number: int, total_enemies: int)

## Emitted whenever the alive enemy count changes during a wave.
signal wave_progress_changed(alive: int, total: int)

# -- Combat: Game State --

## Emitted when the game ends (Hive destroyed).
signal game_over(final_day: int)

## Emitted when the player requests a restart from the game over screen.
signal restart_requested()
