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
| 3 | **Day/Night Cycle** | State machine: Night → Day → Night, manual day trigger | Pending |
| 4 | **Building Placement** | Hero walks to hex, place/upgrade buildings at night | Pending |
| 5 | **Combat Basics** | Enemy spawning, hero auto-attack, basic enemy AI | Pending |
| 6 | **Economy (Honey)** | Enemy drops, flower collection, spending on buildings | Pending |

> After Phase 6: core loop is playable (build → defend → earn → repeat).
> Future phases: units, roguelite choices, procedural maps, meta-progression, bosses.

## Current Status
- **Phase:** Phase 2 complete, ready for Phase 3
- **Completed:** Project setup, GDD, market research, roadmap, Phase 1 (Hex Grid), Phase 2 (Hero + Camera)
- **Next:** Phase 3 — Day/Night Cycle (state machine, manual day trigger)

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
