# Implementation Plan: Speed-Aware Auto-Drive Wall Braking (`P`) & `F` Fire/Melee + Vehicle Hitbox Alignment

**Branch**: `006-autodrive-braking-and-f-fire` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/006-autodrive-braking-and-f-fire/spec.md)

## Summary
Upgrade `A11yNavigation` + `Vehicle` so Auto-Drive cruises at `vehicle.max_speed` when the forward corridor (`> 20m` + stopping margin) and lateral surroundings (`>= 3.4m` per side) are wide open, progressively decelerates/brakes with non-drifting ABS (`a11y_handbrake`) as soon as a wall enters `20m` ahead of the front bumper (or braking lookahead), turns toward the wider clear side, and resumes top speed once clear. Additionally, update `Game` input handling so `F` (`melee`) fires the equipped gun when armed (supporting semi-auto and held full-auto) and punches when unarmed, and raise `Vehicle` collision box height to `1.48m` so horizontal shots hit vehicles cleanly.

## Technical Context
- **Language/Version**: GDScript (Godot 4.7.2 `GL Compatibility`)
- **Primary Files**: `scripts/accessibility/a11y_navigation.gd`, `scripts/vehicle.gd`, `scripts/game.gd`, `scripts/hud.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`
- **Testing**: Headless Godot test suites (`tests/test_accessibility.gd`, `tests/test_combat.gd`, plus all `tests/test_*.gd`)
- **Constraints**: Preserve `Vehicle.profile()` invariants tested by `tests/test_harbor_feel.gd`; keep manual `Space` handbrake drift intact; NVDA-only speech (`A11yUIHelper.say`); never bind `Insert` or `CapsLock`.

## Constitution Check
- Follows project SpecKit + ECC workflow (TDD red-green-refactor, GDScript static typing & small helpers, zero code duplication, `gdscript-reviewer` audit, full headless verification, and `GEMINI.md` logging).

## Architecture & Changes

1. **Non-Drifting Auto-Drive ABS Braking & Taller Vehicle Hitbox (`scripts/vehicle.gd`)**:
   - Raise `_build_collision()` `BoxShape3D` size to `Vector3(1.78, 1.48, 4.25)` at `position.y = 0.74` (ground-flush bottom at `0.0`, roof at `1.48m`).
   - Separate `manual_handbrake` (for `0.18` drift slip) from `a11y_handbrake` (for `0.04` high-grip slip) and apply strong ABS deceleration (`maxf(brake_rate * 2.8, absf(speed) * 6.5)`) when `a11y_handbrake` is engaged during Auto-Drive.
   - Keep `Vehicle.profile()` completely unchanged.

2. **Speed-Aware Auto-Drive Corridor, 20m Wall Braking & Wide-Road Cruise (`scripts/accessibility/a11y_navigation.gd`)**:
   - Prevent `_beacon_timer` in `tick()` from overwriting `current_waypoint` when `autowalk_active` is `true`.
   - Extract `_scan_drive_corridor()` helper: casts 3 forward bumper-width rays (`-0.92m`, `0.0`, `+0.92m`), angled escape rays (`±24°`, `±52°`, `±82°`), and lateral clearance rays (`±90°`), returning front bumper distance, left/right escape scores, and minimum side clearance.
   - Extract `_compute_autodrive_target_speed()` & `_apply_autodrive_speed_control()`:
     - Full `vehicle.max_speed` when `bumper_dist > max(20.0, stopping_dist + 4.0)`, `side_min >= 3.4`, and no sharp corner ahead (`_upcoming_turn_angle()`).
     - Progressive deceleration starting at `20.0m` bumper distance (ramping down smoothly to `0.0` at `3.6m`), corner slowdown within `22.0m`, and narrow-road cap when `side_min < 3.4m`.
     - Active brake/coast/throttle control comparing `vehicle.speed` against `desired_speed` (using `a11y_handbrake` + `throttle = 0.0` to brake without accidental reverse).
     - Latch avoid turn direction (`_avoid_side` + `_avoid_hold_timer`) and trigger immediate reverse-and-countersteer recovery if boxed in (`bumper_dist <= 3.6m` and `speed <= 4.0`).

3. **Context-Sensitive `F` Key & Prompts (`scripts/game.gd`, `scripts/hud.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`)**:
   - Route `melee` (`F`) press to `_try_fire()` (setting `_firing = true`) when `player.weapon != Arsenal.Id.NONE`, and to `_try_punch()` when unarmed; release `_firing` only when neither `fire` nor `melee` is pressed.
   - Update `GameHUD.ACTION_LABELS["melee"]`, `Game._sync_hud()` prompt, and `A11yGameplayController._speak_context_help()` to document `F / ; / Click`.

4. **TDD Verification & Review (`tests/test_accessibility.gd`, `tests/test_combat.gd`)**:
   - Write failing tests first (RED) for: (a) Auto-Drive top-speed cruise on wide clear road + 20m wall detection/braking/turning without wall damage/explosion, and (b) `KEY_F` firing ammo in open air, damaging a vehicle at horizon pitch (`-0.04`), and punching when unarmed.
   - Implement changes (GREEN), run full `tests/test_*.gd`, review diff, export Windows `.exe` if requested/appropriate, and update `GEMINI.md`.
