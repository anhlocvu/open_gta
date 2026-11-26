# Tasks: Speed-Aware Auto-Drive Wall Braking (`P`) & `F` Fire/Melee + Vehicle Hitbox Alignment

## Phase 1: Setup & Specification
- [x] T001 Create SpecKit artifacts in `specs/006-autodrive-braking-and-f-fire/` (`spec.md`, `plan.md`, `tasks.md`) and update `.specify/feature.json`

## Phase 2: TDD Red Phase (Tests First)
- [x] T002 [P] [US1] Add failing tests in `tests/test_accessibility.gd` for Auto-Drive top-speed cruise on wide road, 20m wall detection/braking/steering avoidance without wall damage (`hp == 100.0`, `exploded == false`), and resuming cruise once clear
- [x] T003 [P] [US2] Add failing tests in `tests/test_game_integration.gd` for `KEY_F` firing equipped gun in open air (decrementing magazine), `KEY_F` damaging a facing vehicle at horizon pitch (`-0.04`), holding `KEY_F` for full-auto rifle, and `KEY_F` unarmed punch

## Phase 3: US1 — Safe High-Speed Auto-Drive & 20m Wall Braking
- [x] T004 [US1] Update `Vehicle._build_collision()` (`1.48m` height) and separate non-drifting Auto-Drive ABS braking from manual handbrake drift in `scripts/vehicle.gd`
- [x] T005 [US1] Implement wide-road max-speed cruise, 3-ray bumper corridor + side-width scanning, 20m progressive braking, corner slowdown, latched wall steering, boxed-in safety, arrival ABS retention, and beacon waypoint isolation in `scripts/accessibility/a11y_navigation.gd`

## Phase 4: US2 — Context-Sensitive `F` Fire/Melee & Prompts
- [x] T006 [US2] Route `melee` (`F`) to `_try_fire()` when armed (press/hold/release) and `_try_punch()` when unarmed in `scripts/game.gd` and `scripts/player.gd`
- [x] T007 [P] [US2] Update `melee` label, HUD prompt, and NVDA context help text in `scripts/hud.gd`, `scripts/game.gd`, and `scripts/accessibility/a11y_gameplay_controller.gd`

## Phase 5: Verification, Review & Logging
- [x] T008 Run all headless test suites (`tests/test_*.gd`) after final edit and confirm 0 failures
- [x] T009 Review diffs against GDScript/ECC quality standards, update `GEMINI.md`, and verify headless app launch
