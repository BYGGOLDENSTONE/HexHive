# HexHive - Project Guide

## Project Overview
**HexHive** is a bee-themed base defense strategy game built in Godot 4.6 with 3/4 perspective view. Players command a bee colony, defending their hive during day waves and building/upgrading during night phases. Features a hero unit with WASD control, auto-attacks, special abilities, and an aura system.

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
- Example: a unit with tags `["flying", "armored", "poison_immune"]` instead of `is_flying`, `is_armored` booleans

### 4. SVG Art Pipeline
- All visuals are hand-crafted SVGs with high detail (70-100 draw calls per entity is fine)
- SVGs are baked to textures at startup/export for 1 draw call per entity at runtime
- Humanoid bee aesthetic: bipedal bodies with arms/legs, weapons, bee-themed armor
- Color palette: warm golds/ambers for allies, red/black and purple/black for enemies

### 5. Performance Strategy
- Bake SVGs to sprite sheets / textures before gameplay
- Use C++ GDExtension for performance-critical systems (pathfinding, large battles)
- Object pooling for projectiles, particles, and temporary effects

### 6. Native Language
- All code, comments, variable names, signals, and documentation in **English**
- User communication in Turkish

## Tech Stack
- **Engine:** Godot 4.6 (Forward Plus, D3D12)
- **Language:** GDScript (with C++ GDExtension for hot paths)
- **Art:** SVG → baked textures
- **Grid:** Dual hex grid (large hexes for buildings, small hexes for units — 7 small per 1 large)

## Game Design Summary

### Core Loop
- **Day Phase:** Defend hive from enemy waves (wasps/hornets)
- **Night Phase:** Collect honey from flowers + enemy drops → build/upgrade → prepare for next wave

### Economy
- Single currency: **Honey**
- Used for: buildings, towers, walls, unit production, upgrades

### Hero Unit
- WASD movement, auto-attack
- Special ability (TBD)
- Aura zone with buffs for nearby allied units

### Units & Commands
- Producible bee units (workers, soldiers, etc.)
- No direct control — issue simple commands ("defend this position", "patrol here")

### Enemies
- Wasps and hornets with humanoid bee bodies
- Color schemes: red/black, purple/black
- Wave-based, daytime attacks

### Map
- Medium-sized (similar to Thronefall / They Are Billions scale)
- Not fully visible at once, but no excessive scrolling needed

## Project Structure
```
res://
├── CLAUDE.md
├── project.godot
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

## Current Status
- **Phase:** Project setup
- **Completed:** Initial Godot project, CLAUDE.md created
- **Next:** GitHub repo setup, core architecture scaffolding
