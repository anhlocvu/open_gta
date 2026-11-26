# Implementation Plan: Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance

**Branch**: `009-smart-navigation-entrances` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/009-smart-navigation-entrances/spec.md)

**Input**: Feature specification from `/specs/009-smart-navigation-entrances/spec.md`

## Summary
Eliminate Auto-Walk and Auto-Drive circling/trapping bugs across Harbor District by: (1) shifting `Pay and Spray` (`spray_pos`) and `Drop Warehouse` (`garage_pos`) pads cleanly outside their building colliders; (2) adding a structured Landmark Zone & Entrance/Exit Portal registry in `City` plus multi-layer `"walk"`/`"drive"` sidewalk, park, doorway, and apron graph connectivity in `RoadGraph`; and (3) upgrading `A11yNavigation` with static-layer macro A* routing, monotonic forward waypoint progression, multi-ray fan + sharp-turn stride steering, exterior drive-target resolution for walk-in storefronts, and net-progress anti-circle loop detection.

## Technical Context

**Language/Version**: GDScript (Godot 4.7.2 `GL Compatibility`)  
**Primary Dependencies**: Godot 4.7.2 Engine (`PhysicsDirectSpaceState3D`, `CharacterBody3D`), `RoadGraph`, `City`, `A11yNavigation`, `A11yGameplayController`  
**Storage**: N/A (runtime world geometry & graph in memory; preserves `SaveManager` schema compatibility)  
**Testing**: Headless GDScript test runner (`tests/test_accessibility.gd`, `tests/test_dealership_and_dev.gd`, `tests/test_game_integration.gd`, and all `tests/test_*.gd`)  
**Target Platform**: Windows x86_64 Desktop (+ existing Android/mobile touch compatibility)  
**Project Type**: 3D Open-World Action / Accessibility Game (`Operation Chaos` / `GTA-mini`)  
**Performance Goals**: Maintain `< 1 ms` per-frame navigation overhead; reuse `RoadGraph` topology built once on `City.build()`; zero synchronous NavMesh rebaking hitches  
**Constraints**: Preserve NVDA-only speech (`A11yUIHelper`), preserve `near_dealership()`/`near_gun_shop()`/`near_bar()`/`spray_contains()`/`garage_contains()` gameplay semantics, keep `City` MultiMesh draw call batching intact  
**Scale/Scope**: 11x15 street grid + sidewalk/park/portal extensions (~9 landmark zones), 4 primary script files + test suites

## Constitution Check

- **TDD First**: Write failing headless regression tests reproducing (a) Dealership interior escape to exterior car, (b) Pay and Spray Auto-Drive arrival, (c) Hospital -> Dealership Auto-Walk completion, and (d) storefront exterior Auto-Drive + anti-circle recovery before implementing fixes.
- **Simplicity & Maintainability**: Keep `RoadGraph` pure `RefCounted` (testable without scene tree) and split `A11yNavigation` helpers into cohesive, `< 50`-line functions.
- **Accessibility & Audio**: Preserve clear NVDA turn/reroute/arrival callouts (`A11yUIHelper.say`) without spamming or overriding critical vehicle fire warnings.

## Project Structure

### Documentation (this feature)

```text
specs/009-smart-navigation-entrances/
├── spec.md              # Feature specification & acceptance criteria
├── checklists/
│   └── requirements.md  # Spec quality checklist
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 root-cause analysis & decisions
├── data-model.md        # Zone/portal & multi-layer graph structures
└── quickstart.md        # Headless validation commands & scenarios
```

### Source Code (repository root)

```text
scripts/
├── city.gd                               # Landmark pad clearance + nav_zones portal definitions + multi-layer graph construction
├── road_graph.gd                         # Corridor-clear node lookup, portal containment routing, walk/drive filtered A*
├── game.gd                               # Crate/sign alignment for shifted spray/garage pads
└── accessibility/
    ├── a11y_navigation.gd                # Monotonic waypoint progression, multi-ray steering, drive target resolution, loop detector
    └── a11y_gameplay_controller.gd       # Mode-aware target resolution hooks if needed

tests/
└── test_accessibility.gd                 # New regression tests for Dealership escape, Pay & Spray drive, Hospital->Dealership walk, loop recovery
```

**Structure Decision**: Single Godot project layout extending the existing `City`, `RoadGraph`, and `A11yNavigation` modules without introducing unneeded autoloads or NavMesh baking overhead.

## Implementation Phases (Pending User Approval)

1. **Phase 1 — Landmark Geometry & Zone/Portal Registry (`scripts/city.gd`, `scripts/game.gd`)**:
   - Shift `spray_pos` to `(mid_x, 0.15, mid_z + 6.5)` with `Pay and Spray` building at `spray_pos + (0, 0, -11.5)` (`5.39m` clear gap behind pad) and `SPRAY` sign on south facade.
   - Shift `garage_pos` to `(mid_x, 0.15, mid_z + 6.0)` with warehouse building at `garage_pos + (0, 0, -12.0)`, `DROP` sign on south facade, and crates beside/behind building out of pad.
   - Build `City.nav_zones` covering `dealership`, `gun_shop`, `bar`, `spray`, `garage`, `hospital`, `station`, `army_base`, and `army_hangar` (`bounds`, `interior_pos`, `door_pos`, `apron_pos`, `drive_pos`, `enclosed`, `walk_only_entry`).
   - Add `City.resolve_drive_target(pos, label)` and `City.find_containing_zone(pos)`.
   - Extend `City.make_graph()` to populate portal chains (`interior <-> door <-> apron <-> street`), key pedestrian walkways/sidewalks along civic/shop blocks, and park paths through `_is_park` blocks.

2. **Phase 2 — Multi-Layer Corridor-Aware `RoadGraph` (`scripts/road_graph.gd`)**:
   - Add `node_kinds`, `edge_modes` (`"both"` vs `"walk"`), `add_node()`, `connect_nodes()`, and `zones`.
   - Upgrade `nearest_clear()` with corridor width checks (`_corridor_clear_static(space, from, to, half_w, exclude, 1)`) so corner-grazing wall rays never pick nodes behind walls.
   - Upgrade `astar_path(..., mode := "walk")` to:
     - Respect `"walk"` vs `"drive"` edge permissions (`"drive"` skips `"walk"`-only doorway/park edges).
     - Apply slight walk preference for `"sidewalk"`/`"park"`/`"apron"` over busy road centers when path lengths are comparable.
     - Automatically anchor `start_i` / `goal_i` via zone portal chains (`interior -> door -> apron` / `apron -> door -> interior`) whenever `from_pos` or `to_pos` lies inside an enclosed zone's `bounds`.

3. **Phase 3 — Smart `A11yNavigation` Engine (`scripts/accessibility/a11y_navigation.gd`)**:
   - **Monotonic Route Tracking**: Separate macro static routing (`mask = 1`) from dynamic local avoidance (`mask = 1 | 4 | 8`); advance `_path_idx` monotonically along `_path_points` (via proximity or segment pass-through) and only recompute A* on init, destination change, off-route drift, or reroute penalty—eliminating backward intersection snapping.
   - **Smart Auto-Walk Local Steering**: Replace single-ray `center_hit` snapping with a 7-ray forward fan (`0°, ±22°, ±48°, ±78°`) + capsule-width feelers (`±0.42m`), consistent `_avoid_side` hysteresis, and sharp-turn speed moderation (`> 50°` slows forward stride while turning) so doorways and 90° corners never overshoot.
   - **Drive Target Resolution & Arrival**: Resolve pedestrian-only storefront destinations (`Vehicle Dealership`, `Gun Shop`, `Bar`) to their `drive_pos` exterior apron during Auto-Drive (`"Arrived outside %s."`), while driving smoothly onto open pads (`Pay and Spray`, `Drop Warehouse`).
   - **Net-Progress Anti-Circle Loop Detection**: Track `_best_wp_dist` and `_no_progress_timer` alongside `_stall_timer` in both `_tick_autowalk()` and `_tick_autodrive()` so circular wandering triggers edge penalization, escape steering, and rerouting.

4. **Phase 4 — TDD Verification, Code Review & Export**:
   - Write & run TDD tests first (RED -> GREEN -> REFACTOR) in `tests/test_accessibility.gd` and run all 9 test suites (`tests/test_*.gd`).
   - Run `code-reviewer` / `gdscript-reviewer` checks, rebuild Windows release export (`OperationChaos.exe` / `.pck`), verify headless startup, and log session details in `GEMINI.md`.
