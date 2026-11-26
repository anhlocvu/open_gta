# Implementation Plan: Radar Split, Dev Mode (`anhloc.env`), Vehicle Dealership & Hospital Navigation Fix

**Branch**: `008-radar-split-dev-dealership-hospital-fix` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/008-radar-split-dev-dealership-hospital-fix/spec.md)

## Summary
Split the Open World Radar's combined `Places and Vehicles` category into `Vehicles`, `Places` (all 8 Harbor District landmarks city-wide), and `My Assets` (all purchased and stolen/boarded vehicles and aircraft city-wide); fix the Hospital and Police Station building collision overlap causing Auto-Walk loops; implement `DevMode` gated by `anhloc.env` (`lll20042004`) with an NVDA-accessible `F1` Dev Panel; and add the `Vehicle Dealership` landmark, accessible purchase menu (`Enter`), instant outside spawn + player seating, and full Save/Load support for dynamically purchased vehicles/aircraft.

## Technical Context
- **Language/Version**: GDScript (Godot 4.7.2 `GL Compatibility`)
- **Primary Files**:
  - `scripts/accessibility/a11y_radar.gd`, `scripts/radar.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`
  - `scripts/city.gd`, `scripts/models.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`
  - `scripts/dev_mode.gd` *(new)*, `scripts/combat_input.gd`, `scripts/player.gd`, `scripts/hud.gd`, `scripts/game.gd`
- **Testing**: Headless Godot suites (`tests/test_accessibility.gd`, `tests/test_save_and_audio.gd`, `tests/test_game_integration.gd`, plus all existing `tests/test_*.gd`).
- **Constraints**: Preserve NVDA-only speech (`A11yUIHelper`), protect `Insert`/`CapsLock` modifiers, keep `SaveManager.SCHEMA_VERSION = 1` backward-compatible, avoid hard-coded `anhloc.env` files in repository or release export, and keep `City` batched draw call budgets optimal.

## Constitution Check
- Follows SpecKit + ECC workflow: TDD Red -> Green -> Refactor, small single-purpose methods and helpers, `A11yUIHelper` accessible controls for every new menu/panel, `code-reviewer` + `gdscript-reviewer` review, full headless verification, Windows `.exe` export check, and `GEMINI.md` update.

## Architecture & Changes

1. **Radar Split & `My Assets` Ownership (`scripts/accessibility/a11y_radar.gd`, `scripts/radar.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/game.gd`)**:
   - Update `A11yRadar.Category`: `ALL = 0, ENEMIES = 1, CIVILIANS = 2, OBJECTIVES = 3, LOOT = 4, VEHICLES = 5, PLACES = 6, ASSETS = 7`.
   - `Category.PLACES`: emits all 8 fixed landmarks (`place:gun_shop`, `place:bar`, `place:spray`, `place:garage`, `place:hospital`, `place:station`, `place:base`, `place:dealership`) without distance culling.
   - `Category.VEHICLES`: emits unoccupied, non-wrecked vehicles (`<= 180m`, top 16 nearest) and aircraft.
   - `Category.ASSETS`: scans all `vehicles` and `aircraft` with `player_owned == true` (unoccupied, non-wrecked/non-exploded) city-wide with no distance cap, formatting labels cleanly (e.g., `"<Name> (Asset)"`).
   - Add `player_owned: bool = false`, `custom_model_path: String = ""`, `custom_display_name: String = ""` on `Vehicle` and `player_owned: bool = false`, `civilian_variant: bool = false` on `Aircraft`, persisted in `to_save_dict()` / `apply_save_dict()`.
   - Mark `player_owned = true` in `Game._enter_vehicle()`, `Game._enter_aircraft()`, and Dealership purchases.
   - Update `Radar._draw()` so `PLACES`, `VEHICLES`, and `ASSETS` highlight their respective blips accurately.

2. **Hospital & Police Station Collision Clearance (`scripts/city.gd`, `scripts/game.gd`)**:
   - In `City._grid()`, place `hospital_pos` at `Vector3((ave_xs[8] + ave_xs[9]) * 0.5, 0.15, (st_zs[12] + st_zs[13]) * 0.5 + 7.2)` and `station_pos` at `Vector3((ave_xs[9] + ave_xs[10]) * 0.5, 0.15, (st_zs[8] + st_zs[9]) * 0.5 + 7.2)` (on the open front apron inside each block, `~2.8m` clear of the north sidewalk and `~3.09m` clear of the building wall).
   - Place Hospital building at `hospital_pos + Vector3(0, 0, -9.2)` with `Vector3(20, 28, 12)` (`max_z = hospital_pos.z - 3.09`, `min_z` clear of south sidewalk) and Station building at `station_pos + Vector3(0, 0, -9.2)` with `Vector3(18, 24, 12)`.
   - Place Hospital green pad centered on `hospital_pos` (`Vector3(7, 0.05, 5)`), Station blue pad centered on `station_pos`, and `health_spawns = [hospital_pos + Vector3(2.2, 0.2, 0)]` completely outside walls.
   - Update `Game._respawn()` offsets (`+ Vector3(0, 0.2, 1.8)`) so respawn stays cleanly on the front apron/sidewalk.

3. **Dev Mode & `F1` Dev Panel (`scripts/dev_mode.gd`, `scripts/combat_input.gd`, `scripts/player.gd`, `scripts/game.gd`, `scripts/hud.gd`)**:
   - Create `DevMode` (`RefCounted` helper) resolving `anhloc.env` from `OS.get_executable_path().get_base_dir().path_join("anhloc.env")` (with `res://anhloc.env` fallback only when `OS.has_feature("editor")` or `OS.get_executable_path().get_file().to_lower().begins_with("godot")`). Parses `lll20042004` (bare token or `DEV_CODE=lll20042004`, trimming whitespace/quotes).
   - Add `dev_panel` (`KEY_F1`) in `CombatInput.install()`.
   - Add runtime dev flags on `Game` / `Player`: `dev_infinite_money`, `Player.infinite_ammo`, `dev_god_mode`.
   - When `dev_infinite_money` is active or toggled on, money is set to `999999999` and purchases do not reduce `money`.
   - When `Player.infinite_ammo` is active, `spend_shot()` keeps magazine loaded and `request_reload()` / `tick_combat()` never run dry; toggling it on also grants all 4 weapons (`PISTOL`, `SMG`, `RIFLE`, `SHOTGUN`) if missing with full magazines/ammo.
   - Build an accessible overlay modal `_dev_panel` inside `GameHUD` using `A11yUIHelper` (`wire_button`, `wire_toggle`, `grab_focus_safe`), opened/closed via `F1` or `Esc` / `CLOSE` button.

4. **Vehicle Dealership (`scripts/models.gd`, `scripts/city.gd`, `scripts/game.gd`, `scripts/hud.gd`)**:
   - Add `GameModels.dealership_catalog()` returning an ordered `Array[Dictionary]` covering **all** distinct vehicles (`AMBER COUPE`, `UNIT`, `PATROL JEEP`, every unique model in `CIV_CARS` and `PARKED_CARS`) and **both** aircraft (`AN-2 Civilian`, `AN-2 Military`), with `id`, `name`, `category`, `path`, `vehicle_kind`, `is_aircraft`, `civilian_plane`, `tint`, and `price`.
   - Place `dealership_pos` in block `(6, 4)` (`cx = (ave_xs[6] + ave_xs[7]) * 0.5`, `cz = (st_zs[4] + st_zs[5]) * 0.5`), showroom storefront facing `+Z` toward `st_zs[5]`, neon sign `AUTO`, and open delivery spawn coordinates `dealership_spawn_pos` along `st_zs[5]` directly outside the showroom.
   - Pressing `Enter` (`KEY_ENTER` / `KEY_KP_ENTER` or `interact` when near `dealership_pos` and on foot) opens the accessible Dealership menu (`_dealer_panel` in `GameHUD`).
   - Selecting and buying spawns the vehicle/aircraft (`bought_veh:<n>` / `bought_air:<n>`) at the first unobstructed slot near `dealership_spawn_pos`, sets `player_owned = true`, deducts money (unless `dev_infinite_money`), closes the menu, and seats the player inside immediately.
   - Extend `Game.apply_saved_state()` to dynamically instantiate saved `bought_veh:*` and `bought_air:*` records cleanly (and clean up stale dynamic bought items not in the loaded save).
