# Feature Specification: Speed-Aware Auto-Drive Wall Braking (`P`) & Context-Sensitive `F` Fire/Melee + Vehicle Hitbox Alignment

**Feature Branch**: `006-autodrive-braking-and-f-fire`
**Created**: 2026-11-26
**Status**: Approved by User
**Input**:
1. Auto-Drive (`P`) must cruise at maximum speed when the road ahead (`> 20m` from front bumper + braking margin) and lateral surroundings (`>= 3.4m` clear per side) are wide open, progressively decelerate starting at `20m` when a wall or obstacle is detected ahead, brake to a safe turn/stop before impact, steer away toward the wider clear side (or reverse-and-reroute if boxed in), and resume top speed once back on a wide clear road.
2. Pressing `F` (`melee`) while holding any gun (`player.weapon != Arsenal.Id.NONE`) must fire the equipped gun (spending magazine ammo, playing gunfire/impact audio, spawning tracer, and damaging targets including vehicles), while pressing `F` unarmed (`Arsenal.Id.NONE`) continues to perform melee punch.
3. Shooting horizontally at a vehicle (including after leveling horizon with `U` or facing with `O`) must reliably hit the vehicle's collision body and reduce vehicle `hp` (rather than passing over a low `1.05m` hitbox).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Wide-Road Top Speed & 20m Wall Braking in Auto-Drive (Priority: P1)
When driving a vehicle with Auto-Drive (`P`) enabled, if the forward corridor and left/right surroundings are wide open, the vehicle accelerates to its maximum speed (`vehicle.max_speed`). As soon as a wall or obstacle enters the `20m` bumper detection zone ahead (or within speed-proportional stopping distance), Auto-Drive smoothly decelerates, applies active ABS braking/handbrake if needed to avoid high-speed impact, steers smoothly toward the clearer side (or executes reverse-and-reroute when blocked close), and accelerates back to top speed once on an open road—preventing repeated wall crashes and vehicle explosions.

**Why this priority**: Eliminates fatal Auto-Drive wall collisions that previously destroyed the player's car.

**Independent Test**: Headless test places the player in a `COUPE` on an open street with a blocking wall ahead, activates `P` Auto-Drive, verifies the vehicle accelerates cleanly on clear road, detects the wall at `<= 20m`, brakes/decelerates and turns away without taking repeated high-speed wall-impact damage (`hp == 100.0`, `exploded == false`), and resumes cruising once clear.

**Acceptance Scenarios**:
1. **Given** an open straight avenue with wide clearance ahead (`> 20m`) and on both sides (`>= 3.4m`), **When** Auto-Drive is active, **Then** the vehicle drives at full throttle toward its top speed.
2. **Given** Auto-Drive is moving at high speed toward a wall `<= 20m` ahead of the front bumper, **When** the forward bumper rays detect the wall, **Then** Auto-Drive progressively decelerates/brakes (engaging `a11y_handbrake` without sideways drift when urgent) and steers toward the wider clear side before slamming into the wall.
3. **Given** Auto-Drive encounters a narrow corridor or sharp intersection turn, **When** lateral clearance is tight or the next `RoadGraph` waypoint requires a turn, **Then** it caps speed appropriately for safe cornering and accelerates back to top speed after clearing the turn.

---

### User Story 2 - Context-Sensitive `F` Key (Fire When Armed, Punch When Unarmed) & Vehicle Hitbox Alignment (Priority: P1)
Pressing `F` (`melee`) while holding a firearm fires the equipped weapon (identical to `;` / Left Click: decrements magazine ammo, emits shot tracer/audio, and damages pedestrians, officers, and vehicles). Pressing `F` while unarmed (`Arsenal.Id.NONE`) punches nearby officers, pedestrians, or vehicles. Additionally, `Vehicle` collision height matches visual car height (`~1.48m`) so horizontal gunfire at standing muzzle height (`1.4m`) hits facing vehicles reliably without flying over the roof.

**Why this priority**: Directly resolves player confusion where pressing `F` while armed swung a silent fist without spending ammo or damaging targeted cars.

**Independent Test**: Headless test equips a weapon (`PISTOL` and automatic `RIFLE`), sends `KEY_F` (`melee`) while aiming into open air and verifies magazine ammo decrements by 1; then aims horizontally at a nearby parked `Vehicle` (`pitch = -0.04` horizon level), sends `KEY_F`, and verifies the car takes weapon damage (`hp < 100.0`) and ammo decrements; finally holsters to `NONE`, sends `KEY_F` near a vehicle/pedestrian, and verifies unarmed punch still works.

**Acceptance Scenarios**:
1. **Given** the player has a firearm equipped (`weapon != NONE`) with rounds in magazine, **When** the player presses `F`, **Then** the gun fires, magazine count decreases by 1, and automatic weapons continue firing while `F` is held until released.
2. **Given** the player is unarmed (`weapon == NONE`), **When** the player presses `F`, **Then** the player executes an unarmed punch (`_try_punch`).
3. **Given** the player faces a vehicle horizontally (`pitch = -0.04`, standing muzzle `1.4m`) and fires (`F`, `;`, or Left Click), **When** the shot ray crosses the vehicle, **Then** it hits the vehicle's `1.48m`-tall collision box and deals gunfire damage.

### Edge Cases
- What happens when `beacon_enabled` is on during `Auto-Drive`? Beacon pings MUST NOT overwrite `nav.current_waypoint` with narrow `0.45m` walk-corridor data.
- What happens if both `fire` (`;` / Mouse) and `melee` (`F`) are held and one is released? `_firing` only clears when neither `fire` nor `melee` remains pressed.
- What happens if Auto-Drive reaches a dead-end wall with both front corners blocked (`bumper_dist <= 3.6m`)? It stops cleanly (`a11y_handbrake`) and immediately triggers reverse-and-countersteer rerouting without waiting `1.35s` to ram the wall.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: `A11yNavigation._tick_autodrive()` MUST scan a 3-ray bumper-width forward corridor (`-0.92m`, `0.0`, `+0.92m` from front bumper) with speed-scaled reach (`>= 24m`), plus angled whiskers (`±24°`, `±52°`, `±82°`) and lateral side rays (`±90°`).
- **FR-002**: When forward corridor (`> 20m` + stopping margin), lateral clearance (`>= 3.4m` per side), and upcoming turn lookahead are clear, Auto-Drive MUST apply `throttle = 1.0` toward `vehicle.max_speed`.
- **FR-003**: When a wall or vehicle is detected within `20m` ahead of the front bumper (or within braking lookahead at high speed), Auto-Drive MUST progressively reduce target speed to `0` near `3.6m`, engage active ABS braking (`a11y_handbrake` without drift slip) when `vehicle.speed` exceeds safe target speed, steer toward the wider clear side (latched to avoid oscillation), and immediately reverse-and-reroute if trapped close to a wall.
- **FR-004**: `A11yNavigation.tick()` MUST NOT allow `_beacon_timer` to overwrite `current_waypoint` while `autowalk_active` is `true`.
- **FR-005**: `Game._unhandled_input()` MUST route `melee` (`F`) press/hold/release to `_try_fire()` when `player.weapon != Arsenal.Id.NONE`, and to `_try_punch()` when `player.weapon == Arsenal.Id.NONE`; HUD prompts, `GameHUD.ACTION_LABELS`, and `A11yGameplayController._speak_context_help()` MUST describe `F` accurately.
- **FR-006**: `Vehicle._build_collision()` MUST use `BoxShape3D(1.78, 1.48, 4.25)` at `position.y = 0.74` so horizontal standing gunfire reliably impacts vehicles.
- **FR-007**: `Vehicle._physics_process()` MUST separate manual `Space` handbrake drift slip (`0.18`) from Auto-Drive `a11y_handbrake` ABS stopping (`0.04` slip, high deceleration toward `0.0` without unintended reverse).

### Success Criteria
- **SC-001**: Auto-Drive cruises at high speed on open avenues and brakes/turns around a `20m` wall ahead without taking high-speed wall-impact damage (`hp == 100.0`, `exploded == false`).
- **SC-002**: Pressing `F` while armed consumes 1 round per shot in open air and damages facing vehicles at horizon pitch (`-0.04`); pressing `F` unarmed performs melee punch.
- **SC-003**: 100% of existing and new headless Godot test suites (`tests/test_*.gd`) pass with `0` failures.
