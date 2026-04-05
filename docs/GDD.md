# HexHive - Game Design Document

## Overview
**Genre:** Roguelite Base Defense / Strategy
**Theme:** Bee colony vs wasps/hornets
**Perspective:** 2D, 3/4 view (top-down camera, side-view sprites)
**Target Run Length:** ~15-25 minutes
**Price Target:** $12.99

### Elevator Pitch
> Defend your hive by day, build by night. A roguelite base defense where you control a hero bee on a hex grid, balancing personal combat with colony strategy.

---

## Core Loop

### Single Run Flow
```
Start Run (procedural map generated)
  → Night 0: Place initial buildings, scout map
  → Day 1: First enemy wave
  → Night 1: Build/upgrade with earned honey
  → Day 2: Harder wave, new enemy types
  → ...repeat, escalating...
  → Day N: Final boss wave
  → Win: Rewards → meta-progression
  → Lose (hive destroyed): Partial rewards → meta-progression
```

### Day Phase (Combat)
- Enemy waves attack from multiple directions
- Hero fights with auto-attacks + abilities
- Allied units and towers defend autonomously
- All enemies dead → automatic transition to night
- Waves test different strategies, not just bigger numbers

### Night Phase (Building)
- 100% safe — no enemies
- Unlimited time — player triggers next day manually
- Hero walks to hexes to place/upgrade buildings (Thronefall-style)
- Hero movement speed increased at night
- Spend honey on: buildings, towers, walls, units, upgrades
- Strategic route planning: which builds to prioritize

---

## Hero

### Controls
- WASD movement
- Auto-attack (nearest enemy in range)
- Special ability (TBD)
- Aura zone around hero

### Camera
- Locked to hero at all times (day and night)
- Zoom in/out available
- No free camera mode

### Build Paths (via roguelite choices)
| Path | Playstyle | Trade-off |
|------|-----------|-----------|
| **Support/Aura** | Buffs nearby towers and units | Hero weak alone, must stay near defenses |
| **Lone Wolf** | Strong personal combat | Can only defend one front, rest needs towers/units |
| **Hybrid** | Balanced | Jack of all trades |

### Death & Respawn
- Hero respawns on death (cooldown/penalty TBD)
- Hero death ≠ game over
- Hive destruction = game over

---

## Economy

### Currency: Honey
- Single resource for everything
- **Sources:**
  - Flower collection (map resources)
  - Enemy drops on kill
- **Sinks:**
  - Building construction
  - Building upgrades
  - Unit production
  - Hero upgrades (in-run)

---

## Hex Grid System

### Dual Grid
- **Large hexes:** Building placement grid
- **Small hexes:** Unit movement grid
- Ratio: 1 large hex = 7 small hexes (1 center + 6 surrounding)
- Buildings snap to large grid, units move on small grid

### Why Dual Grid
- Buildings feel substantial (occupy meaningful space)
- Units have precise positioning within and around buildings
- Choke points work at both scales

---

## Units

### Allied Units
- Produced from buildings using honey
- **No direct control** — player gives simple commands:
  - "Defend this position"
  - "Patrol this area"
- Unit types TBD (workers, soldiers, archers, etc.)

### Enemies
- **Visual identity:** Humanoid wasps/hornets (bipedal, armed, insectoid armor)
- **Color schemes:**
  - Red/black wasps (aggressive, melee-focused)
  - Purple/black hornets (ranged, special abilities)
- **Wave design principles:**
  - Each wave introduces a new tactical challenge
  - Not just "more of the same"
  - Mini-bosses in mid-run waves
  - Final boss wave to win the run
- Enemy types TBD (will design when implementing combat)

---

## Map

### Procedural Generation
- New terrain layout each run
- Varying elements:
  - Mountain/hill placement (natural walls)
  - Choke point locations
  - Flower/resource positions
  - Hive starting position context
- Medium-sized: not visible at a glance, but no excessive scrolling

### Map Scale Reference
- Similar to Thronefall or They Are Billions maps
- Player needs to scroll/move hero to see edges
- But full map reachable within ~10-15 seconds of hero movement

---

## Meta-Progression (Roguelite)

### Permanent Colony Upgrades
- Persist between runs
- Examples (TBD):
  - Stronger starting hive
  - Unlock new building types
  - Hero base stat upgrades
  - New unit types available
  - Starting honey bonus

### In-Run Roguelite Choices
- Rewards offered between waves (or after mini-bosses)
- Shape hero build path (support vs lone wolf vs hybrid)
- Buff towers, units, economy, or hero
- Random selection from pool — creates unique runs

---

## Difficulty & Replayability (Future)

### Heat System (Hades-inspired)
- Not priority — implement after core loop is solid
- Player voluntarily increases difficulty for better rewards
- Examples: faster enemies, more waves, limited building, etc.

---

## Visual Style

### Art Direction
- 2D SVG art, baked to textures at runtime
- 3/4 perspective: camera looks down, sprites show side view of characters
- **Allies:** Warm golds, ambers, honey tones. Cozy but warrior-like.
- **Enemies:** Red/black and purple/black. Menacing, sharp silhouettes.
- **World:** Natural environment — flowers, grass, trees, rocks, hive structures
- **Characters:** Humanoid bees/wasps — bipedal bodies, arms, legs, weapons, armor. NOT cartoony bugs. Think "bee knight", "wasp berserker".

### Reference Style
- Sprite perspective similar to: Stardew Valley, Graveyard Keeper, classic Zelda
- Strategic feel similar to: Thronefall, Kingdom: Two Crowns

---

## Content Targets

### Demo (Steam Next Fest)
| Content | Target |
|---------|--------|
| Maps | 1 procedural template |
| Enemy types | 3-5 |
| Buildings | 5-8 |
| Unit types | 1-2 + hero |
| Playtime | 15-30 min |

### Early Access
| Content | Target |
|---------|--------|
| Map templates | 3-5 procedural variations |
| Enemy types | 8-12 |
| Buildings | 12-18 |
| Unit types | 3-5 + hero |
| Meta-upgrades | 10-15 |
| Playtime | 5-10 hours |

### Full Release (1.0)
| Content | Target |
|---------|--------|
| Map templates | 5-8 procedural variations |
| Enemy types | 12-20 |
| Buildings | 18-25 |
| Unit types | 5-8 + hero |
| Meta-upgrades | 20-30 |
| Hero abilities | 5+ |
| Playtime | 8-15h main / 30h+ completionist |

---

## Open Questions
- Hero special ability design
- Hero death penalty specifics
- Exact wave count per run
- Unit type roster
- Building type roster
- Meta-progression unlock tree structure
- Night phase: any time-based events (traders, random events)?
- Multiplayer / co-op (future consideration?)
