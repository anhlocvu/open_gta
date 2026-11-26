# Implementation Plan: Unified Auto-Pilot, Smart Rerouting, Universal Radar Face (`O`) & Vehicle Destruction

**Branch**: `005-autopilot-radar-vehicle-destruction` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/005-autopilot-radar-vehicle-destruction/spec.md)

## Technical Context
- **Engine**: Godot 4.7.2 (`GL Compatibility`), GDScript, headless verification via `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/<suite>.gd`.
- **Navigation & Radar**: `scripts/road_graph.gd`, `scripts/accessibility/a11y_navigation.gd`, `scripts/accessibility/a11y_radar.gd`, `scripts/accessibility/a11y_aim_assist.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`.
- **Vehicle, Player, Combat & VFX/Audio**: `scripts/vehicle.gd`, `scripts/player.gd`, `scripts/game.gd`, `scripts/wanted.gd`, `scripts/shot_effects.gd`, `scripts/accessibility/a11y_spatial_audio.gd`, `scripts/combat_input.gd`, `scripts/hud.gd`.

## Architecture & Changes

1. **Weighted A* & Accessible Node Selection (`scripts/road_graph.gd`)**:
   - Add `astar_path(from_pos, to_pos, blocked_edges := {}, preferred_start := -1)` using Euclidean XZ `g + h` cost and support for penalized/blocked edges during rerouting.
   - Add `nearest_clear(pos, space, exclude_rids := [])` preferring the closest intersection node with unobstructed static-wall LOS from `pos`.

2. **Resilient Auto-Walk & Auto-Drive (`scripts/accessibility/a11y_navigation.gd`, `scripts/vehicle.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`)**:
   - Track `_path_points: PackedVector3Array`, `_path_idx`, `_blocked_edges: Dictionary`, `_recovery_timer`, `_recovery_dir`, and progress-anchor stall detection based on actual displacement rather than straight-line `dist_total`.
   - Use 3-ray corridor checks (`_has_clear_corridor`) before allowing direct-to-destination shortcuts, and multi-angle whisker raycasts (`0°`, `±28°`, `±58°`, `±85°`) for smooth wall/vehicle avoidance.
   - On foot: sidestep/back-step along clear whisker side and trigger A* reroute when stalled; try mantle/step over low curbs if needed, never aborting for `"Path blocked"`.
   - In vehicle (`Vehicle`): add `a11y_drive_override: Vector2` (`steer, throttle`) and `a11y_handbrake: bool`; steer along A* road waypoints, slow down for sharp turns, reverse-and-countersteer during stall recovery, brake smoothly on arrival (`<= 7.5m` / `<= 3.8m` for service pads), and cancel immediately on manual input or `P`.

3. **Universal Radar Target Facing `O` (`scripts/accessibility/a11y_radar.gd`, `scripts/accessibility/a11y_aim_assist.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`, `scripts/combat_input.gd`, `scripts/hud.gd`)**:
   - Extend `A11yRadar.resolve_locked_target()` to return `aim_height` and `hp` (when target is a `Vehicle`).
   - Add `A11yAimAssist.face_radar_target(game, player, camera, radar, nav)` triggered by `O` (`a11y_aim_assist`): resolves the locked Radar target (falling back to current objective or nearest radar target), rotates `camera.yaw`/`camera.pitch` (and standing `player.rotation.y` when on foot and not in cover), checks LOS, and speaks label, meters, clear/blocked status, and vehicle HP%.
   - Keep `snap_to_visible_enemy()` intact and bind `Shift+O` (`a11y_snap_enemy`) for quick combat snap.

4. **Vehicle Melee Damage, Burning Countdown & Explosions (`scripts/player.gd`, `scripts/vehicle.gd`, `scripts/game.gd`, `scripts/wanted.gd`, `scripts/shot_effects.gd`, `scripts/accessibility/a11y_spatial_audio.gd`)**:
   - Add `Player.try_punch_vehicle() -> Vehicle` checking forward melee reach (`~2.6m`) against `vehicles` group; wire into `Game._try_punch()` with metallic impact audio and crime reporting.
   - Enhance `Vehicle.apply_damage()`: emit smoke/fire feedback at durability thresholds (`50%`, `25%`), enter `burning` state (`1.8s` countdown) at `0 HP` with `"Vehicle on fire, get out!"` alert, then detonate (`_explode()`): charred appearance, `wrecked = true`, `exploded = true`, pooled `ShotEffects.emit_explosion()`, 3D `A11ySpatialAudio.play_explosion()`, AoE damage to nearby pedestrians/players/vehicles (chain reactions), and `WantedSystem` crime (`vehicle_explosion` / `destroy_cop`).

5. **TDD, Review & Verification**:
   - Write failing tests first in `tests/test_accessibility.gd` and `tests/test_combat.gd` (or dedicated checks), implement changes incrementally, run all `tests/*.gd`, audit GDScript quality, export Windows build if needed, and log in `GEMINI.md`.
