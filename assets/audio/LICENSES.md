# HexHive Audio Assets — License and Sourcing Notes

This folder holds all audio assets for HexHive. Every file shipped in the game
must be tracked here with its license, source URL, and any attribution the
license requires.

## Folder Layout

```
assets/audio/
├── sfx/               Short sound effects (.ogg preferred, .wav accepted)
├── music/             Looping music tracks (not wired up yet)
└── LICENSES.md        This file
```

## Current SFX Slots (wired via autoload/audio_bus.gd)

The `AudioBus` autoload loads each of these files at startup. Missing files
emit a single warning and the corresponding event plays silently — the game
stays shippable without audio.

| Event             | Expected Path                                  | Trigger                                            |
|-------------------|-----------------------------------------------|----------------------------------------------------|
| build_place       | sfx/build_place.ogg                           | Any building placed (and upgrade, pitch +15%)      |
| projectile_fire   | sfx/projectile_fire.ogg                       | Hero or turret fires a honey projectile            |
| projectile_hit    | sfx/projectile_hit.ogg                        | Projectile impact                                  |
| enemy_death       | sfx/enemy_death.ogg                           | Any enemy dies                                     |
| hive_hit          | sfx/hive_hit.ogg                              | Hive takes damage (fixed pitch, warning feel)      |
| phase_transition  | sfx/phase_transition.ogg                      | Day or night starts (pitch ±10% between phases)    |

## Licensing Rules

1. **Only CC0, CC-BY, or explicitly licensed assets.** No ripped / unclear.
2. **Log every file here** before committing. Include: source URL, author, license, attribution text if required.
3. **Prefer short (<1s) SFX** for gameplay actions to keep the mix tight.
4. **Match the cozy/arcade tone** — avoid horror, dubstep, or harsh industrial.

## Tone Reference

Target aesthetic: warm, wooden/organic, bee-themed. Think:
- Cozy puzzle games (Untitled Goose Game, Slime Rancher)
- Light arcade tower defense (Kingdom Rush, Thronefall)
- NOT: dark fantasy, grimdark, metal, horror

## Ledger

_No assets licensed yet. Add entries below as files land._

```
# Template:
# - File: sfx/build_place.ogg
#   Source: https://freesound.org/people/...
#   Author: ...
#   License: CC0 / CC-BY 4.0 / ...
#   Attribution: "sound by X (freesound.org)"
```
