---

description: "Task list for Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance"
---

# Tasks: Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance

**Input**: Design documents from `/specs/009-smart-navigation-entrances/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`

## Phase 1: TDD Regression Tests (Write Tests First - RED)

- [x] T001 Add headless regression tests in `tests/test_accessibility.gd` covering:
  - [US1] Dealership & Gun Shop interior escape (`player` inside showroom targeting exterior vehicle parked behind `-Z` wall exits via south doorway and arrives without trapping).
  - [US2] `spray_pos` & `garage_pos` pad collider clearance + Auto-Drive arriving onto `Pay and Spray` (`spray_contains == true`) from street without reverse-reroute loop.
  - [US3] Long-distance Auto-Walk from `Hospital` (`hospital_pos`) to `Vehicle Dealership` (`dealership_pos`) completing cleanly without backward intersection snapping.
  - [US4] Auto-Drive targeting walk-in storefront (`Vehicle Dealership` / `Gun Shop`) arrives cleanly at exterior `drive_pos` apron; net-progress loop detector triggers edge-penalized reroute when circling.
- [x] T002 Run `tests/test_accessibility.gd` via `godot_console --headless` to verify new tests FAIL before implementation (RED).

---

## Phase 2: Landmark Geometry & Navigation Zone Registry (`scripts/city.gd`, `scripts/game.gd`)

- [x] T003 [US2] Shift `spray_pos` to `(ave_xs[1]+ave_xs[2])*0.5, 0.15, (st_zs[7]+st_zs[8])*0.5 + 6.5` and place Pay & Spray building at `spray_pos + Vector3(0, 0, -11.5)` with `SPRAY` sign on south facade in `scripts/city.gd`.
- [x] T004 [US2] Shift `garage_pos` to `(ave_xs[4]+ave_xs[5])*0.5, 0.15, (st_zs[1]+st_zs[2])*0.5 + 6.0` with warehouse building at `garage_pos + Vector3(0, 0, -12.0)`, `DROP` sign on south facade, and crates placed clear of `_garage` pad in `scripts/city.gd`.
- [x] T005 [US1][US4] Add `nav_zones: Array[Dictionary]`, `find_containing_zone(pos)`, and `resolve_drive_target(pos, label)` in `scripts/city.gd` covering `dealership`, `gun_shop`, `bar`, `spray`, `garage`, `hospital`, `station`, `army_base`, and `army_hangar`.
- [x] T006 [US1][US3][US4] Extend `City.make_graph()` in `scripts/city.gd` to register zone portals (`interior <-> door <-> apron <-> street`), sidewalk walkways along civic/shop blocks, and park paths through `_is_park(4..5, 6..7)`.

---

## Phase 3: Multi-Layer Corridor-Aware `RoadGraph` (`scripts/road_graph.gd`)

- [x] T007 [US1][US4] Add `node_kinds`, `edge_modes`, `zones`, `add_node()`, and `connect_nodes()` to `scripts/road_graph.gd` preserving `RoadGraph.grid(xs, zs)` backward compatibility.
- [x] T008 [US1][US3][US4] Upgrade `nearest_clear()` with static corridor-width ray checks (`half_width` param) and add `astar_path(..., mode := "walk")` with `"walk"`/`"drive"` edge filtering, sidewalk walk preference, and zone portal containment anchoring (`interior -> door -> apron` for exits, `apron -> door -> interior` for entries).

---

## Phase 4: Smart `A11yNavigation` Engine (`scripts/accessibility/a11y_navigation.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`)

- [x] T009 [US3] Separate static macro routing (`mask = 1`) from dynamic local avoidance (`mask = 1 | 4 | 8`) in `compute_route_waypoint()` and `_refresh_route()`, enforcing monotonic forward `_path_idx` progression (eliminating 0.5s backward intersection snaps).
- [x] T010 [US1][US3] Upgrade `_tick_autowalk()` with 7-ray forward fan clearance, `_avoid_side` hysteresis, and sharp-turn speed moderation (`> 50°`) for crisp doorway/corner turns.
- [x] T011 [US4] Resolve pedestrian-only storefront targets (`Vehicle Dealership`, `Gun Shop`, `Bar`) to `City.resolve_drive_target()` in `_tick_autodrive()` (`"Arrived outside %s."`) and add net-progress anti-circle loop detection (`_best_wp_dist`, `_no_progress_timer`) to both `_tick_autowalk()` and `_tick_autodrive()`.

---

## Phase 5: Verification, Code Review & Export

- [x] T012 Run all 9 headless test suites (`tests/test_*.gd`) and verify 0 failures (GREEN).
- [x] T013 Review modified files via `code-reviewer` / `gdscript-reviewer` and refactor any complexity or duplication issues.
- [x] T014 Re-run full headless test suite after any refactor, export `export/windows/OperationChaos.exe`, verify `OperationChaos.exe --headless --quit-after 5`, and log the session in `GEMINI.md`.
