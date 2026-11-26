# Tasks: Unified Auto-Pilot, Smart Rerouting, Universal Radar Face (`O`) & Vehicle Destruction

## Phase 1: Setup & Specification
- [x] T001 Create SpecKit artifacts in `specs/005-autopilot-radar-vehicle-destruction/` (`spec.md`, `plan.md`, `tasks.md`) and update `.specify/feature.json`

## Phase 2: TDD Red Phase (Tests First)
- [x] T002 [P] Add failing tests in `tests/test_accessibility.gd` for: Auto-Drive (`P` inside `Vehicle` + manual cancel), A* obstacle rerouting around walls/dead-ends without stopping on foot & in vehicle, and `O` universal radar target facing (vehicle, place, pickup, officer, blocked vs clear)
- [x] T003 [P] Add failing tests in `tests/test_combat.gd` for: unarmed punch damaging vehicles (`Player.try_punch_vehicle`), shooting/punching vehicle to `0 HP` -> `burning` countdown -> `exploded` AoE knockdown + chain damage

## Phase 3: US1 & US2 — Weighted A*, Smart Rerouting & Vehicle Auto-Drive
- [x] T004 [US2] Implement `astar_path` and `nearest_clear` in `scripts/road_graph.gd`
- [x] T005 [US1] Add `a11y_drive_override` and `a11y_handbrake` support plus damage/burning/explosion lifecycle in `scripts/vehicle.gd`
- [x] T006 [US1] [US2] Upgrade `scripts/accessibility/a11y_navigation.gd` with corridor checks, multi-whisker avoidance, active sidestep/reverse recovery, and Auto-Drive controller
- [x] T007 [US1] Wire Auto-Drive (`P`) and arrival/cancel announcements in `scripts/accessibility/a11y_gameplay_controller.gd`

## Phase 4: US3 — Universal Radar Target Facing (`O`) & `Shift+O`
- [x] T008 [US3] Expose target `aim_height` and vehicle `hp` in `scripts/accessibility/a11y_radar.gd`
- [x] T009 [US3] Implement `face_radar_target()` in `scripts/accessibility/a11y_aim_assist.gd` and wire `O` / `Shift+O` across `scripts/combat_input.gd`, `scripts/hud.gd`, and `scripts/accessibility/a11y_gameplay_controller.gd`

## Phase 5: US4 — Vehicle Melee, Fire Warning & Explosions
- [x] T010 [P] [US4] Add `play_explosion()` and metallic vehicle punch/hit WAV cues in `scripts/accessibility/a11y_spatial_audio.gd`
- [x] T011 [P] [US4] Add pooled `emit_explosion()` VFX in `scripts/shot_effects.gd` and vehicle destruction crimes in `scripts/wanted_system.gd`
- [x] T012 [US4] Add `try_punch_vehicle()` in `scripts/player.gd` and wire punch damage + `on_vehicle_exploded()` AoE / chain reaction / wanted reporting in `scripts/game.gd`

## Phase 6: Verification, Review & Logging
- [x] T013 Run all headless test suites (`tests/test_*.gd`) after final edit and confirm 0 failures
- [x] T014 Review diffs against GDScript/ECC quality rules, verify Windows export if applicable, and append session log to `GEMINI.md`
