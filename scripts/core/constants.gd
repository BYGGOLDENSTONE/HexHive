class_name Constants
extends RefCounted
## Central repository for all magic numbers and tuning constants.
## Import with: Constants.SOME_VALUE

# -- Hero --
const HERO_MOVE_SPEED: float = 4.0
const HERO_NIGHT_SPEED_MULTIPLIER: float = 1.5
const HERO_MAX_HP: float = 100.0
const HERO_ATTACK_DAMAGE: float = 15.0
const HERO_ATTACK_RANGE: float = 3.5
const HERO_ATTACK_SPEED: float = 1.5
const HERO_RESPAWN_DELAY: float = 3.0
const HERO_PROJECTILE_SPEED: float = 12.0

# -- Hero Model --
const HERO_MODEL_PATH: String = "res://assets/models/characters/hero/friendlybee.glb"
const HERO_MODEL_SCALE: float = 0.5
const HERO_MODEL_Y_OFFSET: float = 0.15
const HERO_HOVER_FREQUENCY: float = 5.0
const HERO_HOVER_AMPLITUDE: float = 0.08
const HERO_ROTATION_SPEED: float = 12.0

# -- Hero Auto-Walk --
const HERO_AUTO_WALK_STUCK_TIMEOUT: float = 3.0
const HERO_AUTO_WALK_RANGE: int = 1

# -- Enemy --
const ENEMY_HOVER_FREQUENCY: float = 5.5
const ENEMY_HOVER_AMPLITUDE: float = 0.12
const ENEMY_ROTATION_SPEED: float = 10.0
const ENEMY_OPPORTUNITY_HEX_RANGE: int = 1
const ENEMY_RETARGET_INTERVAL: float = 0.35

# -- Projectile --
const PROJECTILE_DEFAULT_SPEED: float = 22.0
const PROJECTILE_HOMING_STRENGTH: float = 0.18
const PROJECTILE_HIT_DISTANCE: float = 0.8
const PROJECTILE_LIFETIME: float = 3.0
const PROJECTILE_RADIUS: float = 0.15

# -- Building --
const BUILDING_TURRET_PROJECTILE_SPEED: float = 11.0
const BUILDING_PROXIMITY_RANGE: int = 1

# -- Wave System --
const WAVE_SPAWN_INTERVAL: float = 0.45
const WAVE_BASE_WASP_COUNT: int = 3
const WAVE_WASP_PER_DAY: int = 2
const WAVE_HORNET_START_DAY: int = 2
const WAVE_CLEAR_DELAY: float = 0.6
const WAVE_SPAWN_PICK_ATTEMPTS: int = 12

# -- Visual Effects --
const FLASH_DURATION: float = 0.18
const SPAWN_ANIM_DURATION: float = 0.3
const DEATH_SCALE_DURATION: float = 0.18
const DEATH_SCALE: float = 1.4
const PLACE_ANIM_DURATION: float = 0.35
const UPGRADE_SCALE_UP: float = 1.25

# -- Camera --
const CAMERA_PITCH_ANGLE: float = 55.0
const CAMERA_FOLLOW_SMOOTHING: float = 8.0
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 2.0
const CAMERA_ZOOM_STEP: float = 0.1
const CAMERA_ZOOM_SMOOTHING: float = 10.0

# -- Grid --
const HEX_SIZE: float = 0.6929
const MAP_RADIUS: int = 20
const ELEVATION_HEIGHT: float = 1.0

# -- Map Generation --
const MAP_GEN_PLATEAU_RADIUS: int = 4
const MAP_GEN_PATH_COUNT: int = 3
const MAP_GEN_PATH_WIDTH: int = 2
const MAP_GEN_CHOKE_WIDTH: int = 1
const MAP_GEN_CHOKE_DISTANCE: int = 7
const MAP_GEN_NOISE_FREQUENCY: float = 0.12
const MAP_GEN_NOISE_THRESHOLD: float = 0.45
const MAP_GEN_FOREST_CLUSTER_COUNT: int = 8
const MAP_GEN_FLOWER_PATCH_COUNT: int = 6
