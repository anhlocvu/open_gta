# Feature Specification: Full Vehicle Save/Load Persistence & Smooth Natural Engine Audio

**Feature Branch**: `007-vehicle-save-and-smooth-engine-audio`  
**Created**: 2026-11-26  
**Status**: Approved by User  
**Input**:
1. When the player drives any vehicle to another location, exits the vehicle, saves the game, exits/restarts the game, and clicks `CONTINUE GAME` (or `LOAD SAVED GAME`), the driven vehicle disappears and only freshly spawned AI traffic cars appear nearby. Audit and fix Save/Load persistence and post-exit vehicle behavior so driven/world vehicles remain where left.
2. Make the vehicle engine acceleration sound ramp gradually and smoothly without sudden pitch jumps ("auto-tune" robotic artifact), sounding natural on throttle, coasting, braking, and collisions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Persistent World Vehicles & Parked Stolen Cars Across Save/Load (Priority: P1)
When the player steals or enters any vehicle in Harbor District (`COUPE`, `PARKED`, `CIVILIAN`, `COP`, `MILITARY`, or `Aircraft`), drives it to any new location, exits (`E`), saves (`SAVE GAME`), exits/reloads the game, and loads the save (`CONTINUE GAME` or `LOAD SAVED GAME`), the exact vehicle they drove remains parked right at its saved location with its saved orientation, durability, and state—and does not vanish back to spawn or drive away driverless.

**Why this priority**: Losing your driven vehicle upon reloading a saved game breaks core open-world sandbox continuity.

**Independent Test**: Headless test steals both a `PARKED` car and a `CIVILIAN` traffic car, drives them to custom coordinates, exits (`_exit_vehicle()`), asserts the stolen driverless `CIVILIAN` car remains parked (`ai_enabled == false`), saves the game, instantiates a fresh `main.tscn` from `TITLE`, calls `begin_saved()`, and asserts the exact driven vehicles are restored at their saved coordinates, rotations, and HP right next to the player. Also tests saving while seated inside a non-coupe vehicle and inside an `Aircraft`.

**Acceptance Scenarios**:
1. **Given** the player steals a `CIVILIAN` or `COP` vehicle (`has_driver == false` after driver ejection), drives somewhere, and exits (`E`), **When** gameplay continues, **Then** the empty stolen vehicle stays parked where left (`ai_enabled == false`) instead of driving away by itself.
2. **Given** the player drives any world vehicle (`PARKED`, `CIVILIAN`, `COP`, `MILITARY`, `COUPE`, or `Aircraft`) to a new location, exits (or stays inside), saves the game, quits, relaunches, and loads the save, **When** the world restores, **Then** all world vehicles and aircraft restore their exact saved positions, rotations, damage/exploded states, and occupancy (`active_vehicle` / `active_aircraft`), with zero residual velocity drift.
3. **Given** an older v1 save file that only contains `"coupe"` without `"vehicles"` / `"aircraft"`, **When** loaded, **Then** it remains 100% backward-compatible and restores `coupe` and player state cleanly.

---

### User Story 2 - Gradual, Natural Engine Acceleration Sound Without Sudden Pitch Jumps (Priority: P1)
When accelerating, cruising, coasting, braking, or bumping obstacles in a vehicle, the engine audio ramps smoothly and gradually with mechanical inertia and warm combustion timbre instead of jumping pitch instantaneously like an "auto-tune" synthesizer. Nearby 3D traffic vehicles and aircraft also transition engine pitch smoothly across frames.

**Why this priority**: Eliminates jarring, artificial pitch leaps during normal driving and collisions.

**Independent Test**: Headless test places the player in `coupe`, transitions speed from `0.0` to `max_speed` instantly or across short frames, and verifies `CityAudio._engine.pitch_scale` ramps gradually within a bounded slew rate per second (`< 0.65 / sec`) without single-frame jumps; then drops speed abruptly (simulating a wall impact) and verifies pitch settles smoothly downward without snapping; also verifies `CityAudio.make_engine()` loop invariants (`LOOP_FORWARD`, audible peak, monotonic `engine_pitch`, `test_harbor_feel.gd` size constraint).

**Acceptance Scenarios**:
1. **Given** the player enters a vehicle and presses throttle, **When** vehicle speed climbs rapidly toward `max_speed`, **Then** the engine pitch rises smoothly and gradually over time with realistic inertial lag and warm multi-cylinder combustion texture.
2. **Given** the player releases gas, brakes, or collides with an obstacle causing an abrupt speed change, **When** speed drops suddenly, **Then** the engine pitch winds down smoothly without abrupt single-frame pitch snaps.
3. **Given** AI traffic vehicles or aircraft are audible in 3D/world audio, **When** their speeds change, **Then** their `pitch_scale` interpolates smoothly every frame rather than stepping in `0.08s` intervals.

### Edge Cases
- What happens if extra dynamic police vehicles (`cop_dyn:*`) were spawned during a chase before saving, or exist before loading an earlier save? Saved dynamic cops are recreated by `save_id`, and unsaved extra dynamic cops are cleaned up on load.
- What happens if a vehicle exploded before loading an earlier save where it was intact? `repair()` restores original uncharred mesh materials cleanly.
- What happens if the player switches from one vehicle to another? `CityAudio` resets/smoothly initializes engine state for the newly occupied vehicle without carrying over a stale high-speed pitch spike.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: Every world `Vehicle` (`coupe`, `parked:<i>`, `civ:<i>`, `cop:<i>`, `mil:<i>`, `cop_dyn:<i>`) and `Aircraft` (`air:<i>`) MUST have a deterministic `save_id` assigned at spawn.
- **FR-002**: `Game.serialize_state()` MUST persist all world vehicles (`"vehicles"`), aircraft (`"aircraft"`), `"active_vehicle_id"`, and `"active_aircraft_id"` alongside existing `"player"`, `"coupe"`, and `"in_coupe"` fields.
- **FR-003**: `Game.apply_saved_state()` MUST restore all saved vehicles and aircraft (matching by `save_id`, spawning/removing dynamic `cop_dyn:*` units as needed), reset residual `velocity`/`speed`/autopilot overrides, restore uncharred visuals when loading non-exploded states, and re-seat the player in `active_vehicle` or `active_aircraft` if saved while occupied—while keeping full backward compatibility with legacy v1 saves.
- **FR-004**: `Game._exit_vehicle()` MUST NOT re-enable `ai_enabled` on a vehicle whose driver was ejected (`has_driver == false`).
- **FR-005**: `CityAudio.make_engine()` MUST synthesize a seamless multi-cycle 4-stroke combustion loop (`LOOP_FORWARD`) with sub-harmonic warmth and soft saturation while preserving `test_harbor_feel.gd` invariants.
- **FR-006**: `CityAudio._tick_engine(delta, vehicle)` MUST drive `_engine.pitch_scale` through an inertial, slew-rate-limited RPM/pitch filter over a natural pitch range (`~0.74..1.48`, monotonically increasing in `engine_pitch()`), blended gently with `Vehicle.throttle_input`, and smooth gain fade-in.
- **FR-007**: `A11ySpatialAudio` MUST smoothly interpolate 3D traffic slot `pitch_scale` and `_aircraft_player.pitch_scale` every frame rather than stepping every `0.08s`.

### Success Criteria
- **SC-001**: Exiting any stolen vehicle keeps it parked (`ai_enabled == false`), and saving + reloading from a fresh `main.tscn` instance restores driven `PARKED`, `CIVILIAN`, `COP`, `MILITARY`, `COUPE`, and `Aircraft` entities at their exact saved coordinates (`< 0.35m` error).
- **SC-002**: Under rapid acceleration (`0 -> max_speed`) or sudden collision deceleration, `CityAudio._engine.pitch_scale` changes smoothly (`<= 0.65 / sec` slew, zero single-frame jumps `> 0.06` at 60Hz) and passes all `test_harbor_feel.gd` audio invariants.
- **SC-003**: 100% of headless test suites (`tests/test_*.gd`) pass with `0` failures.
