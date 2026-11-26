# Research Findings: Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance

## Root Cause Analysis (Observed in Source & Geometry)

### 1. Vehicle Dealership & Storefront Trap (`scripts/city.gd`, `scripts/road_graph.gd`, `scripts/accessibility/a11y_navigation.gd`)
- **Geometry**: `City._shops()` builds `Vehicle Dealership`, `Gun Shop`, and `Bar` using `_storefront(pos, wall, neon, w, d)`, which places three solid `StaticBody3D` walls (back `-Z`, left `-X`, right `+X`) and leaves only the front `+Z` face open.
  - For `Vehicle Dealership`, `dealership_pos = (75, 0.15, -92)` and `dealer_center = (75, 0, -97)` (`w=14.0`, `d=8.0` -> `x: 68..82`, `z: -101..-93`).
- **Pathfinding Gap**: `RoadGraph` only contains the `11 x 15` street intersection grid (`ave_xs x st_zs`) and has zero portal/doorway/apron nodes. When the player stands inside the showroom (`z <= -93`) and targets an exterior vehicle (e.g., on `st_zs[4]=-114`, `ave_xs[6]=50`, or `ave_xs[7]=100`), `RoadGraph.nearest_clear()` shoots a single zero-width ray to the 8 nearest intersections—either failing/falling back to an intersection behind the wall (`ranked[0]`) or grazing the doorway edge. `_tick_autowalk()` then steers straight into the side/back wall and oscillates indefinitely.

### 2. Pay and Spray (`spray_pos`) & Drop Warehouse (`garage_pos`) Building Overlap (`scripts/city.gd`)
- **Geometry**: In `City._grid()` and `_civic_zones()`:
  - `spray_pos = (-175, 0.15, 19)` (`(st_zs[7]+st_zs[8])*0.5`), while `_building(spray_pos + Vector3(0, 0, -6.0), Vector3(14, 10, 12), "concrete")` creates a `StaticBody3D` concrete base (`size.z + 0.22 = 12.22`) spanning `z = 6.89 .. 19.11`!
  - Thus the building wall **overlaps `spray_pos` (`z = 19.0`) itself** and covers half of `_spray` (`9x9` pad at `z = 14.5 .. 23.5`).
  - With `AUTODRIVE_BUMPER_OFFSET = 2.15m`, `AUTODRIVE_EMERGENCY_DIST = 3.8m`, and `arrive_radius = 4.4m`, an approaching car triggers `_handle_autodrive_recovery()` at `z = 19.11 + 2.15 + 3.8 = 25.06` (`6.06m > 4.4m`), reverses, penalizes the road edge, and loops endlessly around the block.
  - Similarly, `garage_pos` (`-209.0`) has its warehouse building at `garage_pos + (0, 0, -7.0)` (`max_z = -209.89`), overlapping the `9x9` `_garage` pad (`z = -213.5 .. -204.5`) and placing `_crate` props at `garage_pos + (±4, 0.45, -8)`.

### 3. Hospital -> Vehicle Dealership Auto-Walk Loop (`scripts/accessibility/a11y_navigation.gd`, `scripts/road_graph.gd`)
- **Backward Waypoint Snapping**: `_refresh_route()` runs `compute_route_waypoint()` from scratch every `0.5s` (`_route_timer = 0.5`). `compute_route_waypoint()` passes `mask = 1 | 4 | 8` (static buildings + parked/moving cars) and `RoadGraph.astar_path()` selects `start_i = nearest_clear(origin)` (often the already-passed intersection behind the player once `origin` is `> 8.0m` past `pts[0]`). Whenever any parked or traffic vehicle along the street blocks the thin `_corridor_clear(origin, pts[1])` ray (`42cm` wide), `start_idx` stays `0`, snapping `current_waypoint` **180° backward** to `pts[0]` and trapping the pedestrian in an infinite back-and-forth loop between intersections.
- **Turn-Rate Overshoot & Wall-Snap Oscillation**: `_tick_autowalk()` applies full forward `move_vec = (0, -1)` (`5.2 m/s`) while `camera.yaw` turns at `7.5 rad/s` on 90°/180° transitions, overshooting intersections/doors; and its avoidance checks only a single `center_hit` along `desired_dir`, snapping back into the wall as soon as `center_hit` clears by centimeters.
- **Circular-Wandering Blindness**: `_stall_timer` resets whenever `origin` moves `> 0.65m` (walk) or `> 1.1m` (drive) from `_progress_anchor`, so circling in place with radius `>= 1.5m` never triggers recovery!

## Architectural Decisions
- **Decision 1 (Zone/Portal Registry in `City` + Multi-Layer `RoadGraph`)**: Represent all landmarks as explicit `nav_zones` (`bounds`, `interior_pos`, `door_pos`, `apron_pos`, `drive_pos`, `walk_only_entry`) and build `RoadGraph` with typed nodes/edges (`"road"`, `"sidewalk"`, `"park"`, `"apron"`, `"door"`, `"interior"`), filtering `"drive"` vs `"walk"` traversal.
  - *Rationale*: Lightweight, deterministic, 100% compatible with procedural `City` generation and existing `RoadGraph.grid()` unit calls; avoids expensive async NavMesh rebaking on `City`'s batched geometry while providing exact semantic entrance/exit awareness.
- **Decision 2 (Static-Only Macro A* + Monotonic Waypoint Tracking)**: Separate static world topology (`mask = 1`) for macro `RoadGraph` routing from dynamic obstacle steering (`mask = 1 | 4 | 8`) in local navigation, and advance `_path_idx` monotonically instead of rebuilding from scratch every `0.5s`.
  - *Rationale*: Moving/parked vehicles should be steered around locally, never causing the global street path to flip backward 180°.
- **Decision 3 (Multi-Ray Fan + Hysteresis + Net-Progress Loop Detector)**: Upgrade `_tick_autowalk()` to evaluate a 7-ray fan + sharp-turn stride throttling, and add `_best_wp_dist` / `_no_progress_timer` to both `_tick_autowalk()` and `_tick_autodrive()`.
  - *Rationale*: Eliminates wall-corner oscillation and catches circular loops reliably.
