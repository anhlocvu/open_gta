# Data Model: Smart Navigation Zones & Multi-Layer Graph

## 1. Navigation Zone (`City.nav_zones: Array[Dictionary]`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Stable identifier (`"dealership"`, `"gun_shop"`, `"bar"`, `"spray"`, `"garage"`, `"hospital"`, `"station"`, `"army_base"`, `"army_hangar"`) |
| `bounds` | `Rect2` | XZ footprint enclosing the interior/pad (`position = (min_x, min_z)`, `size = (w, d)`) |
| `interior_pos` | `Vector3` | Interior interaction/target coordinate |
| `door_pos` | `Vector3` | Open doorway or gate threshold coordinate |
| `apron_pos` | `Vector3` | Clear exterior apron/sidewalk point outside the doorway/gate |
| `drive_pos` | `Vector3` | Safe vehicle arrival coordinate (`apron_pos` for walk-in storefronts; pad center for drive-in services) |
| `enclosed` | `bool` | `true` for 3-walled rooms/fenced compounds requiring portal routing (`dealership`, `gun_shop`, `bar`, `army_base`, `army_hangar`) |
| `walk_only_entry` | `bool` | `true` when vehicles cannot enter `door_pos -> interior_pos` (`dealership`, `gun_shop`, `bar`, `army_hangar`) |

## 2. Multi-Layer Graph Extensions (`RoadGraph`)

| Field | Type | Description |
|-------|------|-------------|
| `nodes` | `Array[Vector3]` | World positions of intersections, sidewalks, park nodes, aprons, doors, and interiors |
| `links` | `Array` | Adjacency list of neighbor node indices |
| `node_kinds` | `Array[String]` | `"road"`, `"sidewalk"`, `"park"`, `"apron"`, `"door"`, `"interior"` |
| `edge_modes` | `Dictionary` | Keyed by `edge_key(a, b)` -> `"both"` or `"walk"` (walk-only edges excluded during `"drive"` A*) |
| `zones` | `Array[Dictionary]` | Reference to `City.nav_zones` for start/goal portal containment checks |

## 3. Loop & Progress State (`A11yNavigation`)

| Field | Type | Description |
|-------|------|-------------|
| `_best_wp_dist` | `float` | Closest planar distance achieved to current waypoint since advancing |
| `_no_progress_timer` | `float` | Seconds elapsed without reducing `_best_wp_dist` by minimum progress delta |
| `_route_origin_anchor` | `Vector3` | Position snapshot for detecting drift off the active segment |
| `_resolved_drive_target` | `Vector3` | Drive-safe exterior target returned by `City.resolve_drive_target()` |
