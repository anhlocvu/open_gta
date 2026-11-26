# Feature Specification: Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance

**Feature Branch**: `009-smart-navigation-entrances`  
**Created**: 2026-11-26  
**Status**: Draft  
**Input**: User description: "Sửa lỗi kẹt khi đi bộ từ trong cửa hàng xe ra xe ở ngoài; sửa lỗi tự động lái tới chỗ sơn/sửa xe (Pay and Spray) cứ lòng vòng không tới được; sửa lỗi đi bộ từ bệnh viện sang cửa hàng xe bị đi vòng vòng; và nâng cấp hệ thống tự động đi bộ và tự động lái thông minh hơn, nhận diện được lối đi, lối ra, lối vào."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Exit Vehicle Dealership & Enclosed Storefronts Cleanly on Foot (Priority: P1)

As a player standing inside the Vehicle Dealership (or any enclosed storefront such as Gun Shop or Bar) after browsing, buying, or cancelling a purchase, when I select an outside vehicle on the Radar and start Auto-Walk (`P`), the character recognizes the doorway/exit, walks cleanly out through the open front entrance onto the street/sidewalk, and reaches the target vehicle without circling or getting trapped inside the walls.

**Why this priority**: Players who enter the Vehicle Dealership cannot leave on foot with Auto-Walk when targeting an exterior car behind or beside the building, leaving them permanently stuck inside the showroom.

**Independent Test**: Place the player inside the Vehicle Dealership interior, lock Radar/nav target to a vehicle parked behind or beside the building (north, west, or east outside the walls), activate Auto-Walk, and verify the player exits through the south doorway and arrives at the vehicle without looping.

**Acceptance Scenarios**:

1. **Given** the player is inside the Vehicle Dealership showroom and targets a vehicle parked outside (in front, behind, or to the left/right of the building), **When** Auto-Walk is activated, **Then** the player routes out through the south doorway threshold onto the exterior apron and reaches the vehicle.
2. **Given** the player is inside Gun Shop, Bar, or Army Base / Hangar and targets an outside location or vehicle, **When** Auto-Walk is activated, **Then** the player exits through that structure's open doorway/gate instead of walking into its side or back walls.

---

### User Story 2 - Unobstructed Arrival at Pay and Spray & Service Pads (Priority: P1)

As a driver (or pedestrian) navigating with Auto-Drive or Auto-Walk (`P`) to Pay and Spray (or Drop Warehouse), the destination pad is completely free of overlapping building walls and the autopilot drives smoothly onto the repair/respray pad and stops cleanly for service without circling around the block.

**Why this priority**: The Pay and Spray building collider currently overlaps the target pad and triggers emergency wall-avoidance reversals before arrival, causing Auto-Drive to circle endlessly.

**Independent Test**: Start Auto-Drive from an avenue or street toward `Pay and Spray`, verify the pad center and area are outside static building colliders, and confirm Auto-Drive reaches the pad, stops within service range, and triggers no endless loop.

**Acceptance Scenarios**:

1. **Given** the player is driving on a city street and sets the Radar target to `Pay and Spray`, **When** Auto-Drive (`P`) runs, **Then** the vehicle navigates onto the open Pay and Spray pad and arrives cleanly without hitting an invisible/overlapping wall or reversing in circles.
2. **Given** the player is on foot or driving to `Drop Warehouse`, **When** Auto-Walk or Auto-Drive runs, **Then** the target pad is clear of building walls and crates and arrival completes cleanly.

---

### User Story 3 - Reliable Cross-City Auto-Walk (Hospital to Vehicle Dealership & Beyond) (Priority: P1)

As a player walking long distances across the city with Auto-Walk (for example from Hospital to Vehicle Dealership), the pathfinder maintains steady forward progress along sidewalks, walkways, and street crossings without snapping backward to previously passed intersections or spinning in place when encountering parked cars or traffic.

**Why this priority**: Long-distance Auto-Walk currently recomputes routes from scratch every half-second, snaps backward to already-passed intersections whenever a car blocks the straight ray ahead, and oscillates around corners or vehicles.

**Independent Test**: Place the player at `Hospital` (`city.hospital_pos`), set target to `Vehicle Dealership` (`city.dealership_pos`), run Auto-Walk in a populated world with traffic and parked cars, and verify the player makes continuous forward progress, enters through the dealership apron/doorway, and arrives without looping.

**Acceptance Scenarios**:

1. **Given** the player starts at `Hospital` and activates Auto-Walk toward `Vehicle Dealership`, **When** walking past parked vehicles, traffic, and street intersections, **Then** the player never turns back toward an already-passed intersection and arrives at `Vehicle Dealership`.
2. **Given** a parked or moving vehicle temporarily blocks the direct forward line between intersections, **When** Auto-Walk steers locally around the obstacle, **Then** the macro route remains locked forward and the player resumes the path after clearing the obstacle.

---

### User Story 4 - Entrance/Exit & Walkway-Aware Smart Auto-Walk and Auto-Drive (Priority: P2)

As a player using Auto-Walk or Auto-Drive anywhere in Harbor District, the navigation system distinguishes pedestrian-accessible walkways/doorways/interiors from drivable streets/open pads, pulls cars up to the exterior entrance of walk-in storefronts, routes pedestrians through sidewalks/parks/doorways, and detects circular wandering (lack of net progress toward the waypoint) to trigger smart rerouting.

**Why this priority**: Upgrading both autopilots with semantic portal knowledge, clear-corridor node selection, smooth turn-before-stride steering, and net-progress loop detection prevents future stuck/circling failures across all landmarks and streets.

**Independent Test**: Test Auto-Drive targeting a walk-in storefront (`Gun Shop` or `Vehicle Dealership`), verify the vehicle arrives cleanly at the exterior entrance apron without ramming the storefront walls; test circular-stall detection when temporarily boxed in; and verify Auto-Walk uses pedestrian portals to enter and exit landmarks.

**Acceptance Scenarios**:

1. **Given** the player activates Auto-Drive toward a walk-in interior (`Vehicle Dealership`, `Gun Shop`, `Bar`), **When** computing the driving route, **Then** Auto-Drive targets the landmark's exterior entrance apron and stops cleanly outside the doorway.
2. **Given** either Auto-Walk or Auto-Drive makes zero net progress toward its waypoint over several seconds (e.g., circling or oscillating), **When** the loop detector triggers, **Then** it penalizes the blocked edge, executes a targeted escape maneuver, and reroutes cleanly.

### Edge Cases

- What if the player is standing deep inside `Vehicle Dealership`, `Gun Shop`, `Bar`, or `Army Base` hangar and selects a vehicle parked directly behind the back wall (`-Z`)? The zone portal graph forces exit via the open doorway/gate before routing along streets/sidewalks.
- What if a vehicle is blocking the street immediately outside a doorway or intersection? Macro routing relies on static architecture (`layer 1`) for graph connectivity while local multi-ray steering maneuvers around dynamic vehicles (`layer 4 | 8`) without flipping the global waypoint backward.
- What if the player targets a landmark from inside another enclosed landmark (e.g., `Gun Shop` -> `Vehicle Dealership`)? Auto-Walk chains exit portal -> street/sidewalk graph -> destination entrance portal cleanly.
- What if Auto-Drive approaches `Pay and Spray` from North (`z < spray_pos.z`), East, West, or South? Because the building sits behind the apron and `Pay and Spray` connects to surrounding streets via its open apron, Auto-Drive approaches from the open South/East/West lanes without colliding with the building back wall.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST ensure `Pay and Spray` (`spray_pos` and `_spray` pad) and `Drop Warehouse` (`garage_pos` and `_garage` pad) are positioned on open aprons completely clear of static building and prop colliders so vehicles can enter and stop on the pads unobstructed.
- **FR-002**: System MUST model navigable entrance, doorway/gate, exterior apron, and interior portal chains for all enclosed or semi-enclosed Harbor District landmarks (`Vehicle Dealership`, `Gun Shop`, `Bar`, `Army Base` gate & hangar, `Hospital`, `Police Station`, `Pay and Spray`, `Drop Warehouse`), as well as pedestrian walkways/sidewalks and park paths.
- **FR-003**: Auto-Walk (`P` on foot) MUST route out of enclosed interiors through the landmark's open doorway/gate before heading to exterior targets, and MUST route into enclosed interiors through their exterior apron and open doorway.
- **FR-004**: Auto-Drive (`P` in vehicle) MUST traverse only drivable street/open-apron edges and resolve pedestrian-only storefront destinations (`Vehicle Dealership`, `Gun Shop`, `Bar`) to their unobstructed exterior curb/apron arrival point.
- **FR-005**: Macro graph route selection (`nearest_clear` / `astar_path`) MUST validate corridor width clearance against static walls (`layer 1`) rather than single zero-width rays or transient traffic vehicles, and MUST enforce monotonic progress along the active path instead of resetting backward to already-passed intersections every timer tick.
- **FR-006**: Local steering for Auto-Walk MUST use multi-ray forward fan clearance with side-choice hysteresis and turn-speed moderation on sharp corners so the character turns cleanly through doorways and corners without wall-snap oscillation or street overshoots.
- **FR-007**: Both Auto-Walk and Auto-Drive MUST detect circular wandering / lack of net distance progress toward the active waypoint (not just stationary velocity stalls) and trigger edge-penalized rerouting and escape recovery.

### Key Entities

- **Navigation Zone / Portal**: Represents a landmark's interior bounds, open doorway/gate threshold, exterior apron connector, and vehicle arrival point.
- **Multi-Layer Road & Walkway Graph**: Extends `RoadGraph` with typed nodes/edges (`road`, `sidewalk`, `park`, `apron`, `door`, `interior`) supporting `"walk"` and `"drive"` traversal filters.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of enclosed storefront escape test cases (player inside `Vehicle Dealership`, `Gun Shop`, `Bar` targeting an exterior vehicle behind or beside the building) exit via the doorway and reach the target within headless simulation limits with 0 wall traps.
- **SC-002**: Auto-Drive starting from surrounding streets reaches `Pay and Spray` (`spray_contains == true`) and stops cleanly on the pad in 100% of tested approaches without triggering endless reverse-reroute circles.
- **SC-003**: Cross-city Auto-Walk from `Hospital` to `Vehicle Dealership` completes reliably without backward-snapping loops, arriving within `<= 2.4m` of `dealership_pos`.
- **SC-004**: All existing and new headless test suites pass with 0 failures and no regressions to NVDA speech announcements, manual override cancellation, or vehicle braking safety.

## Assumptions

- Open World `City` layout uses procedural grid blocks defined by `ave_xs` and `st_zs`, and all storefront openings (`Gun Shop`, `Bar`, `Vehicle Dealership`) face `+Z` (South) while `Army Base` gate opens `-Z` (North toward `st_zs[14]`).
- Existing `dealership_pos`, `hospital_pos`, `station_pos`, `gun_shop_pos`, `bar_pos`, and `base_pos` coordinates remain compatible with `near_*` interaction checks and existing Save/Load or Radar tests.
