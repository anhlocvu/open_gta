# Tasks: Full Vehicle Save/Load Persistence & Smooth Natural Engine Audio

## Phase 1: Setup & Specification
- [x] T001 Create SpecKit artifacts in `specs/007-vehicle-save-and-smooth-engine-audio/` (`spec.md`, `plan.md`, `tasks.md`) and update `.specify/feature.json`

## Phase 2: TDD Red Phase (Tests First)
- [x] T002 [P] [US1] Add failing tests in `tests/test_save_and_audio.gd` for driverless stolen vehicle staying parked on `_exit_vehicle()`, full Save/Load persistence of `PARKED`/`CIVILIAN`/`Aircraft` and active non-coupe occupancy across fresh scene reload
- [x] T003 [P] [US2] Add failing tests in `tests/test_save_and_audio.gd` for smooth gradual engine pitch ramping under rapid acceleration and sudden deceleration (no abrupt single-frame pitch jumps)

## Phase 3: US1 — Persistent World Vehicles & Post-Exit Parking
- [x] T004 [US1] Add `save_id`, `throttle_input`, material backup/restore on `repair()`, `to_save_dict()`, and `apply_save_dict()` in `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/save_manager.gd`, and deterministic model selection in `scripts/models.gd`
- [x] T005 [US1] Assign deterministic `save_id`s, keep driverless stolen vehicles parked in `_exit_vehicle()`, `_update_cops()`, and `_update_civilians()`, and serialize/restore all vehicles, aircraft, and active vehicle occupancy in `scripts/game.gd`

## Phase 4: US2 — Smooth Natural Engine Audio
- [x] T006 [US2] Upgrade `CityAudio.make_engine()`, `engine_pitch()`, and inertial slew-rate-limited `_tick_engine(delta, vehicle)` in `scripts/city_audio.gd` (with braking effort guard and pause stop)
- [x] T007 [P] [US2] Smooth 3D traffic slot and aircraft engine `pitch_scale` per frame in `scripts/accessibility/a11y_spatial_audio.gd`

## Phase 5: Verification, Review & Logging
- [x] T008 Run all headless test suites (`tests/test_*.gd`) and `godot_console --headless --quit-after 5` after final edit
- [x] T009 Run `gdscript-reviewer` audit, fix all findings, update `GEMINI.md`, and re-export Windows build
