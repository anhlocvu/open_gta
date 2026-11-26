# Feature Specification: Unified Auto-Pilot (Walk & Drive), Smart Obstacle Rerouting, Universal Radar Face (`O`) & Vehicle Destruction

**Feature Branch**: `005-autopilot-radar-vehicle-destruction`
**Created**: 2026-11-26
**Status**: Approved by User
**Input**:
1. Extend `P` Auto-Walk into Auto-Drive when inside a `Vehicle`, driving automatically to the currently selected Radar target or mission objective.
2. Upgrade both Auto-Walk and Auto-Drive so they navigate around walls, buildings, parked vehicles, and dead ends using weighted A* road routing, multi-ray corridor checks, local whisker obstacle avoidance, and active recovery maneuvers (sidestep/reverse-and-steer) instead of prematurely aborting with `"Path blocked"`.
3. Change `O` to face/orient toward the currently selected Radar target across **all** target categories (police, civilians, vehicles, aircraft, pickups, places, objective), reporting distance and line-of-sight status; keep `Shift+O` (or API fallback) for quick visible enemy snap-aim.
4. Enable melee punches and gunfire against vehicles to reduce vehicle durability (`hp`), trigger fire/warning countdown, and explode vehicles in a 3D audio-visual AoE blast (with chain reactions and wanted heat).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Auto-Drive (`P`) in Vehicles to Any Radar Target (Priority: P1)
While driving any `Vehicle`, pressing `P` activates Auto-Drive toward the locked `A11yRadar` target (or the current mission objective if no radar target is locked). The vehicle accelerates, steers along `RoadGraph` intersections, slows for sharp turns, avoids obstacles/traffic, and stops smoothly upon arrival while announcing status via NVDA. Pressing `P` again or pressing any manual driving input (`W/A/S/D`, arrow keys, or handbrake `Space`) cancels Auto-Drive immediately.

**Independent Test**: Headless test places the player inside a `Vehicle`, locks a distant destination/radar target, presses `P` (`a11y_autowalk`), steps physics frames, and asserts the vehicle drives toward and approaches the target; then verifies manual throttle/steer input or `P` cancels Auto-Drive cleanly.

### User Story 2 - Resilient Pathfinding & Obstacle Recovery for Walk & Drive (Priority: P1)
When Auto-Walk or Auto-Drive encounters a building wall, parked car, street barrier, or dead end along the straight line to its target, it must **not** prematurely terminate with `"Path blocked"`. Instead, it computes a weighted A* route via accessible `RoadGraph` nodes, applies local multi-whisker obstacle avoidance to steer around corners and vehicles, and executes active recovery maneuvers (stepping sideways/back on foot, or reversing and counter-steering in a car) when stalled until it reaches the destination.

**Independent Test**: Headless test spawns a blocking wall/building between the player (both on foot and in a vehicle) and a destination across the block; activates Auto-Walk / Auto-Drive, advances simulation, and verifies the agent routes around the obstruction without aborting and reaches the target vicinity.

### User Story 3 - Universal Radar Target Facing (`O`) (Priority: P1)
Pressing `O` rotates the camera (and standing player facing direction) directly toward the currently selected `A11yRadar` target across all categories—whether an officer, civilian, vehicle, aircraft, pickup, landmark, or mission objective—both on foot and inside a vehicle. NVDA announces the target name, distance in meters, whether line of sight is clear or obstructed, and remaining durability percentage if the target is a vehicle. `A11yAimAssist.snap_to_visible_enemy()` remains intact for `Shift+O` quick combat lock and backward compatibility.

**Independent Test**: Headless test selects targets across categories (a parked vehicle, a landmark place, a pickup, and an officer) via `A11yRadar`, triggers `O` (`a11y_aim_assist`), and asserts camera `yaw`/`pitch` (and standing `player.rotation.y`) orient toward each target with accurate speech feedback for clear vs wall-obstructed targets.

### User Story 4 - Vehicle Destruction, Melee/Gunfire Damage & Explosions (Priority: P1)
Facing a vehicle (including via `O`) and punching it unarmed (`F` / `;`) or shooting it reduces its `hp`. At low durability (`<= 50%` smoking, `<= 25%` critical), feedback warns the player. At `0 hp`, the vehicle enters a short burning countdown (~`1.8s`) with an audible/NVDA `"Vehicle on fire, get out!"` alert before detonating in a 3D explosion that knocks down nearby pedestrians, damages nearby players/occupants, chain-damages nearby vehicles, marks the vehicle `wrecked`/`exploded`, and reports crime heat.

**Independent Test**: Headless test punches an unoccupied vehicle repeatedly with `Player` melee and shoots another vehicle with a gun until `hp` reaches `0`, verifies burning countdown triggers, then advances time to detonation and asserts `exploded == true`, `wrecked == true`, nearby NPC knockdown / chain vehicle damage, and explosion audio/VFX invocation without memory leaks.

## Functional Requirements

- **FR-001**: `A11yNavigation` and `A11yGameplayController` MUST support Auto-Drive when `player.in_vehicle` and `game.active_vehicle != null` using the `a11y_autowalk` (`P`) binding, while rejecting aircraft (`active_aircraft != null`) cleanly.
- **FR-002**: `Vehicle` MUST accept `a11y_drive_override` (`Vector2(steer, throttle)`) and `a11y_handbrake` while `occupied == true`, and clear them immediately upon manual input, exiting the vehicle, pause, burning/wrecking, or arrival.
- **FR-003**: `RoadGraph` MUST provide weighted A* pathfinding (`astar_path`) and unobstructed nearest-node selection; `A11yNavigation` MUST use corridor-width clearance checks, local whisker obstacle steering, and active stall recovery (sidestep/reroute on foot; reverse-and-turn reroute in vehicle) instead of aborting on temporary straight-line distance stalls.
- **FR-004**: Pressing `O` (`a11y_aim_assist`) MUST orient camera `yaw`/`pitch` (and standing `player.rotation.y` when not in cover or vehicle) toward the currently locked `A11yRadar` target (or objective / nearest radar target if none locked) across all categories, announcing target label, distance, LOS status, and vehicle HP% when applicable. `Shift+O` (`a11y_snap_enemy`) provides quick visible-enemy snap-aim.
- **FR-005**: `Player` melee (`_try_punch` / `try_punch_vehicle`) MUST detect and damage vehicles within forward melee reach (`~2.6m`) with metallic impact 3D audio and crime reporting.
- **FR-006**: When `Vehicle.hp <= 0.0`, the vehicle MUST enter a `burning` state (`~1.8s` countdown) with warning audio/speech, then detonate (`exploded = true`, `wrecked = true`), emitting pooled explosion VFX (`ShotEffects`), 3D explosion audio (`A11ySpatialAudio`), AoE damage to nearby pedestrians, vehicles (chain explosions), and players, plus `WantedSystem` reporting.
- **FR-007**: All new speech cues MUST route through `A11yUIHelper.say` (NVDA-only) and never bind `Insert` or `CapsLock`.
