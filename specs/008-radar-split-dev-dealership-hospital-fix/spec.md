# Feature Specification: Radar Split (Vehicles / Places / My Assets), Dev Panel, Vehicle Dealership & Hospital Navigation Fix

**Feature Branch**: `008-radar-split-dev-dealership-hospital-fix`  
**Created**: 2026-11-26  
**Status**: Approved by User  
**Input**:
1. Split Radar `Places and Vehicles` into separate `Vehicles` and `Places` (all map locations for instant travel), plus a dedicated `My Assets` category tracking purchased and hijacked/stolen vehicles & aircraft across the map.
2. Implement a Dev Mode gated by `anhloc.env` (`lll20042004`) in the executable directory, opening an accessible Dev Panel (`F1`) with Infinite Money, Infinite Ammo, Clear Wanted Level, and practical dev utilities.
3. Add a Vehicle Dealership on the map where pressing `Enter` opens an accessible catalog of all vehicles and aircraft in the game, purchases deduct money, spawn the vehicle/aircraft outside the dealership, seat the player immediately, and persist across Save/Load.
4. Fix Hospital (and Police Station) building collision setback and health pickup placement so Auto-Walk / Auto-Drive reaches the entrance cleanly without looping around the building walls.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Split Radar Categories: Vehicles, All Map Places, and My Assets (Priority: P1)
Players using Radar (`B` / `Shift+B`, `,` / `.`, `M`, `P`, `O`) can separately browse nearby/world **Vehicles** (`Vehicles`), **all fixed Harbor District landmarks** (`Places`), and **their own purchased or hijacked vehicles and aircraft** (`My Assets`) so they never lose track of a vehicle they bought or stole, and can navigate directly to any landmark in the map.

**Independent Test**: Headless test verifies `A11yRadar.CATEGORY_NAMES` separates `Vehicles`, `Places`, and `My Assets`; verifies `Places` returns all 8 map landmarks (`Gun Shop`, `Bar`, `Pay and Spray`, `Drop Warehouse`, `Hospital`, `Police Station`, `Army Base`, `Vehicle Dealership`) without distance culling and zero vehicles; verifies `Vehicles` returns unoccupied vehicles/aircraft and zero places; verifies buying or hijacking a vehicle/aircraft marks it as `player_owned` and surfaces it in `My Assets` city-wide even beyond 120m.

**Acceptance Scenarios**:
1. **Given** gameplay is active, **When** cycling radar categories with `B` / `Shift+B`, **Then** `Vehicles`, `Places`, and `My Assets` appear as distinct filters announced via NVDA and reflected in visual Radar dimming/highlighting.
2. **Given** the player selects `Places`, **When** stepping targets with `,` / `.`, **Then** all 8 map landmarks are available regardless of distance, and `M` / `P` navigate directly to the chosen landmark.
3. **Given** the player purchases a vehicle/aircraft or hijacks/boards one in the world and later exits it, **When** selecting `My Assets`, **Then** all intact owned vehicles and aircraft (excluding the currently occupied one) appear with distance/bearing for tracking and navigation across the entire map.

---

### User Story 2 - Hospital & Police Station Entrance Navigation Fix (Priority: P1)
Players using Auto-Walk (`P`) or Auto-Drive (`P`) toward `Hospital` or `Police Station` arrive cleanly at the front entrance pad and receive `"Arrived at Hospital."` / `"Arrived at Police Station."` without colliding with a solid building facade and looping around the block.

**Independent Test**: Headless test verifies `city.hospital_pos`, `city.station_pos`, and `city.health_spawns[0]` are outside any static collider (`intersect_point` empty), and simulates Auto-Walk toward `city.hospital_pos` from the front street, asserting arrival within `<= 2.2m` without looping or wall collision.

**Acceptance Scenarios**:
1. **Given** the player targets `Hospital` on Radar and starts Auto-Walk (`P`), **When** approaching the Hospital, **Then** `hospital_pos` is clear of building walls, Auto-Walk reaches `<= 2.2m`, and announces `"Arrived at Hospital."`.
2. **Given** the player approaches `Hospital` on foot, **When** moving to the hospital health pickup, **Then** it sits outside the wall on the front apron and can be collected normally.

---

### User Story 3 - `anhloc.env` Dev Mode & Accessible `F1` Dev Panel (Priority: P1)
When `anhloc.env` containing dev code `lll20042004` is present alongside the executable, pressing `F1` opens an accessible Dev Panel during gameplay offering Infinite Money, Infinite Ammo (+ all weapons), Clear Wanted Level, Full Health/Armor, God Mode, and Repair Vehicle. When `anhloc.env` is absent or invalid, Dev Mode remains completely inactive and `F1` does nothing.

**Independent Test**: Headless unit tests verify `DevMode.verify_env_file()` accepts `lll20042004` (both bare value and `DEV_CODE=lll20042004`) and rejects missing/wrong-code files; gameplay test verifies pressing `F1` when unlocked opens the Dev Panel, activating Infinite Money grants `$999,999,999` and preserves funds across purchases, activating Infinite Ammo grants weapons and prevents magazine/ammo depletion on firing, and Clear Wanted resets `heat.stars == 0`.

**Acceptance Scenarios**:
1. **Given** `anhloc.env` with `lll20042004` exists next to the executable (or editor fallback during development), **When** the player presses `F1` in gameplay, **Then** gameplay pauses, the accessible Dev Panel opens with focus on the first action, and NVDA announces the panel and each option.
2. **Given** Infinite Money and Infinite Ammo are toggled on in Dev Panel, **When** buying weapons/vehicles or firing guns, **Then** money does not drop and weapon magazine/reserve ammo does not deplete.
3. **Given** the player has wanted stars, **When** activating Clear Wanted Level in Dev Panel, **Then** `heat.clear()` immediately sets stars to `0` and disengages police pursuit.

---

### User Story 4 - Vehicle Dealership Menu, Instant Spawn & Seat, and Save/Load Persistence (Priority: P1)
Players can visit the **Vehicle Dealership** (`AUTO`), press `Enter` (or `E` / `Interact`) to open an accessible catalog listing every vehicle and aircraft model in the game, buy any vehicle or aircraft they can afford, and immediately have it spawned on the open delivery lane outside the dealership with the player seated inside ready to drive or fly.

**Independent Test**: Headless test moves player to `city.dealership_pos`, sends `Enter`, asserts the Dealership menu opens with all catalog vehicles and aircraft (`AMBER COUPE`, `UNIT`, `PATROL JEEP`, all `CIV_CARS` & `PARKED_CARS`, and `AN-2` civilian & military aircraft), buys both a car and an `AN-2`, verifies money deduction, external spawn outside the building, immediate player seating (`active_vehicle` / `active_aircraft`), `player_owned == true`, appearance in `My Assets` after exit, and full restoration across Save/Load.

**Acceptance Scenarios**:
1. **Given** the player stands at `city.dealership_pos` on foot, **When** pressing `Enter`, **Then** the accessible Dealership menu opens and announces available vehicles/aircraft and prices via NVDA.
2. **Given** the player selects a vehicle or aircraft and confirms purchase with sufficient cash, **When** purchase succeeds, **Then** cash is deducted, the vehicle/aircraft spawns on the clear delivery street outside the dealership without clipping into buildings, marks `player_owned = true`, and seats the player inside immediately.
3. **Given** the player saves and reloads after buying vehicles/aircraft, **When** `apply_saved_state()` runs, **Then** all purchased vehicles and aircraft (`bought_veh:*`, `bought_air:*`) are recreated with their exact model, variant, position, durability, and `player_owned` status.

### Edge Cases
- **Insufficient cash at Dealership**: Selecting an item costing more than current `money` (when Dev Infinite Money is off) announces insufficient cash via NVDA + banner and keeps the menu open.
- **Multiple purchases**: Spawning subsequent bought vehicles/aircraft checks occupied spawn slots along the dealership delivery street so vehicles do not spawn stacked on top of each other.
- **Dev Panel / Dealership modal input isolation**: While Dev Panel or Dealership menu is open, gameplay movement/firing/pause-hotkey conflicts are suppressed and `Esc` (or `F1` for Dev Panel) closes the modal cleanly and returns focus/mouse capture.
- **Exploded/wrecked owned vehicles**: Wrecked/exploded vehicles are excluded from active `My Assets` tracking targets.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: `A11yRadar` MUST expose separate `VEHICLES`, `PLACES`, and `ASSETS` (`My Assets`) categories alongside `ALL`, `ENEMIES`, `CIVILIANS`, `OBJECTIVES`, and `LOOT`.
- **FR-002**: `A11yRadar` `Category.PLACES` MUST enumerate all 8 Harbor District landmarks (`Gun Shop`, `Bar`, `Pay and Spray`, `Drop Warehouse`, `Hospital`, `Police Station`, `Army Base`, `Vehicle Dealership`) across the entire map with no distance cap and zero vehicles.
- **FR-003**: `A11yRadar` `Category.VEHICLES` MUST enumerate unoccupied, non-wrecked vehicles and aircraft without landmarks.
- **FR-004**: `A11yRadar` `Category.ASSETS` (`My Assets`) MUST enumerate all intact, unoccupied vehicles and aircraft with `player_owned == true` across the entire map; `Game._enter_vehicle()` and `Game._enter_aircraft()` and Dealership purchases MUST mark `player_owned = true`.
- **FR-005**: `Radar._draw()` MUST synchronize visual blip highlight/dimming with `VEHICLES`, `PLACES`, and `ASSETS` filters.
- **FR-006**: `City._civic_zones()` and `City._markers()` MUST position Hospital and Police Station buildings behind `hospital_pos` and `station_pos` (and `health_spawns` outside walls) so front entrances are unobstructed for Auto-Walk / Auto-Drive.
- **FR-007**: `DevMode` MUST check `anhloc.env` in `OS.get_executable_path().get_base_dir()` (with `res://anhloc.env` fallback in editor/non-exported test runs and injectable path for tests) for dev code `lll20042004`.
- **FR-008**: When Dev Mode is active, `F1` (`dev_panel`) MUST toggle an NVDA-accessible Dev Panel supporting Infinite Money, Infinite Ammo (+ unlock all guns), Clear Wanted Level, Full Health/Armor, God Mode, and Repair Current Vehicle.
- **FR-009**: `City` MUST include a `Vehicle Dealership` landmark (`dealership_pos`, `dealership_spawn_pos`) and `near_dealership()` helper.
- **FR-010**: `GameModels.dealership_catalog()` MUST expose every unique vehicle and aircraft model in the game with display name, category, asset path/variant, speed tier, and price; purchasing via the accessible Dealership menu (`Enter` near dealership) MUST spawn the vehicle/aircraft outside, seat the player immediately, and persist dynamically bought vehicles/aircraft in `SaveManager` JSON.

### Success Criteria
- **SC-001**: `A11yRadar` tests verify `Places` returns exact 8 landmarks, `Vehicles` returns only vehicles/aircraft, and `My Assets` tracks bought and stolen vehicles/aircraft city-wide.
- **SC-002**: `hospital_pos`, `station_pos`, and `health_spawns[0]` pass static collision clearance checks, and Auto-Walk arrives at `Hospital` (`<= 2.2m`) without looping.
- **SC-003**: `DevMode` tests verify strict `anhloc.env` (`lll20042004`) gating, Infinite Money, Infinite Ammo, and Clear Wanted behavior.
- **SC-004**: Dealership tests verify all models present in catalog, `Enter` menu launch, purchase spawn outside dealership + immediate seating, and Save/Load round-trip for bought vehicles/aircraft.
- **SC-005**: 100% of `tests/test_*.gd` suites and headless `OperationChaos.exe --headless --quit-after 5` pass with `0` failures.
