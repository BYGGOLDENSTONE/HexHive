# HexHive - Project Guide

## Overview
Bee-themed roguelite base defense game in Godot 4.6. See `docs/GDD.md` for game design, `docs/MARKET_RESEARCH.md` for market analysis.

## Architecture Principles

### 1. Modular Design
- Each system (combat, building, economy, AI, grid) is an independent module
- Modules communicate through signals, never direct references
- Adding/removing a feature should not require changes in unrelated systems

### 2. Signal-Driven Architecture
- NO per-frame polling for game logic — use Godot signals and events
- Custom signal bus (`SignalBus` autoload) for cross-system communication
- `_process()` only for rendering/interpolation, never for logic checks

### 3. Tag-Based System
- Entities use tags (StringName arrays) instead of scripted if/elif chains
- New enemy types, buffs, buildings are defined via tags + data
- Example: `["flying", "armored", "poison_immune"]` not `is_flying`, `is_armored`

### 4. SVG Art Pipeline
- All visuals are hand-crafted SVGs (70-100 draw calls per entity OK)
- Baked to textures at startup/export → 1 draw call per entity at runtime
- Humanoid bee aesthetic, warm golds for allies, red-black/purple-black for enemies

### 5. Performance Strategy
- Bake SVGs to sprite sheets before gameplay
- C++ GDExtension for performance-critical systems (pathfinding, large battles)
- Object pooling for projectiles, particles, temporary effects

### 6. Native Language
- All code, comments, variables, signals, documentation in **English**
- User communication in Turkish

## Tech Stack
- **Engine:** Godot 4.6 (Forward Plus, D3D12)
- **Language:** GDScript (C++ GDExtension for hot paths)
- **Art:** SVG → baked textures, 2D 3/4 perspective
- **Grid:** Dual hex grid (large for buildings, small for units — 7:1 ratio)

## Project Structure
```
res://
├── CLAUDE.md
├── project.godot
├── docs/               # GDD, market research, design docs
├── autoload/           # Singletons (SignalBus, GameManager, etc.)
├── scenes/
│   ├── main/           # Main game scene, UI
│   ├── entities/       # Hero, units, enemies
│   ├── buildings/      # Towers, walls, hive structures
│   └── world/          # Map, hex grid, environment
├── scripts/
│   ├── core/           # Core systems (grid, tags, economy)
│   ├── combat/         # Combat, projectiles, abilities
│   ├── ai/             # Enemy AI, unit AI
│   └── utils/          # Helpers, constants
├── assets/
│   ├── svg/            # Source SVG files
│   ├── baked/          # Baked textures from SVGs
│   ├── audio/          # Sound effects, music
│   └── shaders/        # Custom shaders
└── addons/             # GDExtension plugins
```

## Git Workflow
- Commit after each meaningful implementation
- Commit messages: clear, descriptive, English
- Always commit AND push together
- Branch: `main` for stable, feature branches for experiments

## Implementation Roadmap

| Phase | System | Description | Status |
|-------|--------|-------------|--------|
| 1 | **Hex Grid** | Dual grid system, coordinate math, visual debug overlay | **Done** |
| 2 | **Hero + Camera** | WASD movement on grid, hero-locked camera with zoom | **Done** |
| 3 | **Day/Night Cycle** | State machine: Night → Day → Night, manual day trigger | **Done** |
| 4 | **Building Placement** | Hero walks to hex, place/upgrade buildings at night | **Done** |
| 5 | **Combat Basics** | Enemy spawning, hero auto-attack, basic enemy AI | Pending |
| 6 | **Economy (Honey)** | Enemy drops, flower collection, spending on buildings | Pending |

> After Phase 6: core loop is playable (build → defend → earn → repeat).
> Future phases: units, roguelite choices, procedural maps, meta-progression, bosses.

## Current Status
- **Phase:** Phase 4 complete, ready for Phase 5
- **Completed:** Project setup, GDD, market research, roadmap, Phase 1 (Hex Grid), Phase 2 (Hero + Camera), Phase 3 (Day/Night Cycle), Phase 4 (Building Placement)
- **Next:** Phase 5 — Combat Basics (enemy spawning, hero auto-attack, basic enemy AI)

## Phase 1 Details (Hex Grid)
- **Grid type:** Pointy-top hex grid (axial coordinates q, r)
- **Dual grid:** Each large pointy-top tile contains 7 flat-top inner slots (1 center + 6 ring)
- **Inner slots:** Flat-top hexes arranged as rosette — naturally forms pointy-top silhouette from outside
- **Perfect fit math:** slot_radius = hex_size * 3/5, slot_size = slot_radius / sqrt(3)
- **Map size:** ~40 hex diameter (map_radius = 20)
- **Files:**
  - `scripts/core/hex_helper.gd` — Static hex math (coord conversion, neighbors, distance, line, geometry)
  - `scripts/core/hex_tile.gd` — Tile data (terrain, 7 slot states, occupancy)
  - `scripts/core/hex_grid.gd` — Grid manager (tile storage, queries, world↔hex conversion)
  - `scripts/core/grid_visual.gd` — Debug rendering (outlines, hover, slot display, active hex)
  - `scenes/main/game.tscn` — Main scene

## Phase 2 Details (Hero + Camera)
- **Hero:** Small hex-sized entity (slot scale 1.1x), free WASD/arrow movement (not grid-snapped)
- **Hex tracking:** System always knows hero's nearest large tile via `pixel_to_hex` — used for range/aura calculations
- **Ranges in hex tiles:** All ranges (attack, aura, towers) measured in large hex tile distance for strategic clarity
- **Grid blocking:** Non-walkable hexes (mountain/water/out-of-bounds) blocked via coordinate check, no physics
- **Wall sliding:** Diagonal movement against walls slides along the wall instead of stopping
- **Camera:** Locked to hero with smooth follow (lerp), zoom only (no free pan)
- **Input actions:** `move_left/right/up/down` — WASD + arrow keys
- **Files:**
  - `scripts/core/hero.gd` — Hero entity (movement, hex tracking, visual)
  - `scripts/core/game_camera.gd` — Hero-locked camera with smooth follow + zoom
  - `scripts/core/grid_visual.gd` — Updated: active hex indicator (amber highlight)

## Phase 3 Details (Day/Night Cycle)
- **State machine:** NIGHT ↔ DAY via DayNightManager autoload
- **Game start:** Night 0 (safe, no enemies, cozy blue atmosphere)
- **Night → Day:** Player presses Space ("Start Day"), transitions to Day N
- **Day → Night:** Timer expires (30s placeholder) or `day_wave_cleared` signal, transitions to Night N
- **Visual feedback:** CanvasModulate tween — night (cool blue 0.45, 0.50, 0.75) ↔ day (warm white 1.0, 0.98, 0.92), 1.5s cubic transition
- **HUD:** Phase label (top-left), day progress bar, "Start Day" prompt (bottom-center), phase banner (center, fades after 1.5s)
- **Hero night speed:** 1.5x movement multiplier during night for faster building traversal
- **SignalBus:** Central signal hub autoload for cross-system communication
- **Input:** `start_day` action mapped to Space key
- **Files:**
  - `autoload/signal_bus.gd` — Central signal bus (phase_changed, day_started, night_started, day_wave_cleared, start_day_requested)
  - `autoload/day_night_manager.gd` — Phase state machine, day timer, transition logic
  - `scripts/core/day_night_visual.gd` — CanvasModulate with tween transitions
  - `scripts/ui/phase_hud.gd` — Phase UI display and input handling
  - `scenes/ui/phase_hud.tscn` — HUD scene (labels, progress bar, banner)
  - `scripts/core/hero.gd` — Updated: night speed multiplier via SignalBus

## Phase 4 Details (Building Placement)
- **Build flow:** Night starts → Build Menu auto-opens → player selects building → ghost preview follows mouse (green=valid, red=invalid) → click to place → hero auto-walks within 1 hex range → building placed with animation → stays in build mode for multi-placement
- **Buildings:** Honey Turret (defense), Wall (blocks movement), Flower Garden (economy), Hive (pre-placed base at center)
- **All buildings block movement** — hero cannot walk through any building
- **Economy:** Free (no cost system yet — added in Phase 6)
- **Upgrade:** Walk within 1 hex of existing building → popup appears on opposite side from hero → click "Upgrade" → level 1→2→3 with visual changes and stat display
- **Upgrade popup features:** Stat display per building type (damage/range/speed/HP/armor/income), connector line from popup to building, directional placement away from hero, overlap resolution (min 35° spread), auto-hide when zoomed out
- **Day duration:** Changed from 30s to 5s (no enemies yet)
- **Build data:** Resource-based system (`building_data.gd`) with `.tres` files per building type in `resources/buildings/`
- **State machine:** BuildManager with states IDLE→PREVIEWING→WALKING_TO_BUILD→BUILDING
- **Hero auto-walk:** Straight-line movement toward build target, WASD cancels, stuck detection (3s timeout)
- **Hero spawn:** Starts at hex (1,0) next to the Hive
- **Night-only:** Build menu auto-hides on day start, all build operations cancelled
- **Camera:** Max zoom out changed to 0.7x
- **Input:** `cancel_build` = ESC, `quick_build_1/2/3` = 1/2/3 keys
- **Removed:** Inner slot debug visualization from grid (Phase 1 debug feature)
- **Files:**
  - `scripts/core/building_data.gd` — Building type Resource definition (id, tags, max_level, colors, buildable_on, blocks_walkability)
  - `resources/buildings/*.tres` — 4 building definitions (honey_turret, wall, flower_garden, hive)
  - `autoload/building_registry.gd` — Autoload that loads all building data, provides lookup by id
  - `scripts/core/building.gd` — Runtime building entity (Node2D, procedural _draw, level system, placement/upgrade animations)
  - `scenes/buildings/building.tscn` — Building scene
  - `scripts/core/build_manager.gd` — Central build state machine, coordinates placement flow, places starting Hive
  - `scripts/core/build_ghost.gd` — Ghost preview renderer (mouse tracking, hex snapping, green/red validity)
  - `scripts/core/building_proximity.gd` — Detects hero within 2 hex of buildings, emits signals
  - `scripts/ui/build_menu.gd` + `scenes/ui/build_menu.tscn` — Build menu UI (auto-opens at night, 1-2-3 shortcuts)
  - `scripts/ui/upgrade_popup.gd` + `scenes/ui/upgrade_popup.tscn` — Upgrade popup above buildings
  - `autoload/signal_bus.gd` — Updated: ~15 building-related signals added
  - `scripts/core/hex_grid.gd` — Updated: place_building, remove_building, can_place_building, get_building_at
  - `scripts/core/hex_tile.gd` — Updated: building reference field, wall walkability check
  - `scripts/core/hero.gd` — Updated: auto-walk system (build_walk_requested → walk → hero_reached_build_range)
  - `scripts/core/grid_visual.gd` — Updated: building-occupied hex outline highlight
  - `autoload/day_night_manager.gd` — Updated: day_duration 30s → 5s
