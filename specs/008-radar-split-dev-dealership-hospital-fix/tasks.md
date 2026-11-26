# Tasks: Radar Split, Dev Mode (`anhloc.env`), Vehicle Dealership & Hospital Navigation Fix

## Phase 1: Setup & Specification
- [x] T001 Create SpecKit artifacts in `specs/008-radar-split-dev-dealership-hospital-fix/` (`spec.md`, `plan.md`, `tasks.md`) and update `.specify/feature.json`

## Phase 2: TDD Red Phase (Tests First)
- [x] T002 [P] [US1] Add failing tests in `tests/test_accessibility.gd` for separate `VEHICLES`, `PLACES` (all 8 landmarks city-wide), and `ASSETS` (`My Assets` tracking bought & stolen vehicles/aircraft city-wide)
- [x] T003 [P] [US2] Add failing tests in `tests/test_accessibility.gd` verifying `hospital_pos`, `station_pos`, and `health_spawns[0]` are outside building colliders and Auto-Walk reaches `Hospital` without looping
- [x] T004 [P] [US3] Add failing tests in `tests/test_game_integration.gd` for `DevMode` `anhloc.env` (`lll20042004`) validation, `F1` Dev Panel gating, Infinite Money, Infinite Ammo, and Clear Wanted Level
- [x] T005 [P] [US4] Add failing tests in `tests/test_save_and_audio.gd` & `tests/test_game_integration.gd` for full `GameModels.dealership_catalog()`, `Enter` opening Dealership menu, buying car & AN-2 aircraft spawning outside + auto-seating, and Save/Load round-trip of `bought_veh:*` / `bought_air:*` / `player_owned`

## Phase 3: US1 — Radar Split (`Vehicles`, `Places`, `My Assets`)
- [x] T006 [US1] Add `player_owned`, `custom_model_path`, `custom_display_name` (and `Aircraft.civilian_variant`) + serialization in `scripts/vehicle.gd` and `scripts/aircraft.gd`
- [x] T007 [US1] Split `A11yRadar.Category` into `VEHICLES`, `PLACES`, and `ASSETS` in `scripts/accessibility/a11y_radar.gd`, update `Radar._draw()` in `scripts/radar.gd`, and mark `player_owned = true` on vehicle/aircraft entry in `scripts/game.gd`

## Phase 4: US2 — Hospital & Station Navigation Fix
- [x] T008 [US2] Move Hospital and Police Station buildings back from `hospital_pos`/`station_pos`, move `health_spawns` outside walls, and add `dealership_pos` + `dealership_spawn_pos` showroom in `scripts/city.gd` (and update `_respawn()` in `scripts/game.gd`)

## Phase 5: US3 — Dev Mode (`anhloc.env`) & `F1` Dev Panel
- [x] T009 [US3] Implement `scripts/dev_mode.gd`, register `dev_panel` (`F1`) in `scripts/combat_input.gd`, add `Player.infinite_ammo` in `scripts/player.gd`, and build NVDA-accessible Dev Panel in `scripts/hud.gd` + `scripts/game.gd`

## Phase 6: US4 — Vehicle Dealership & Save/Load Persistence
- [x] T010 [US4] Add `GameModels.dealership_catalog()` and custom car/plane variant support in `scripts/models.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`
- [x] T011 [US4] Implement `Enter` dealership trigger, NVDA-accessible Dealership menu in `scripts/hud.gd`, outside spawn + instant seating + dynamic Save/Load persistence in `scripts/game.gd`

## Phase 7: Verification, Review & Release
- [x] T012 Run all headless test suites (`tests/test_*.gd`) and `godot_console --headless --quit-after 5`
- [x] T013 Run `code-reviewer` / `gdscript-reviewer` audit, fix any findings, update `GEMINI.md`, re-export `export/windows/OperationChaos.exe`, and verify `.exe --headless --quit-after 5`
