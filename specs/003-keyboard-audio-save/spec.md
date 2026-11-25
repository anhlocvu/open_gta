# Feature Specification: Keyboard Parity, 3D World Audio, Save/Load & Radar Polish

**Feature Branch**: `003-keyboard-audio-save`
**Created**: 2026-11-25
**Status**: Approved by User
**Input**: Keyboard parity for all mouse actions (GTA-style unarmed punch on Fire, `;` Fire, `'` Aim, `-`/`=`/`0` weapon cycling with Unarmed), full 3D world audio (punch, NPC footsteps/reactions, traffic/cop Doppler engines + sirens + horns + crashes, aircraft engine, pickups/zones/ocean/bar/shop/base ambience), Save/Load persistence (`user://open_world_save.json` + `.bak`), remove Day/Night menu buttons, fix Radar NPC/Police filtering, `B`/`Shift+B` bidirectional category cycling, visual-audio Radar sync, district callouts, and 360° Audio Sonar sweep.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Keyboard Parity & GTA-Style Combat (Priority: P1)
Every action executable by mouse (firing, aiming ADS, cycling weapons, menu navigation) can be executed by keyboard, with GTA-style behavior where pressing Fire (`;` or Left Click) fires when armed and punches when unarmed (`NONE`), and cycling weapons (`-`/`=` or Mouse Wheel, plus `0` to holster) includes Unarmed (Fists).

**Independent Test**: Headless test verifies `CombatInput` binds keyboard events for `fire`, `aim`, `cycle_weapon_up`, `cycle_weapon_down`, `weapon_holster`, `a11y_radar_cycle_prev`, `a11y_sonar_sweep`; unarmed Fire triggers punch; armed Fire shoots; `cycle_weapon` cycles through `NONE` and owned weapons.

### User Story 2 - Radar Category Fixes & Bidirectional `B` / `Shift+B` Cycling (Priority: P1)
Pressing `B` advances to the next radar category and `Shift+B` returns to the previous category cleanly. A `Civilians` category exposes nearby walking pedestrians (matching `O` Snap Aim targets), while `Enemies and Police` scans city-wide police units sorted by nearest distance so `,`/`.` never falsely report empty when police units exist. Visual `Radar` highlights the active category and locked target.

**Independent Test**: Headless test verifies `B` and `Shift+B` cycle forward/backward without `Shift+B` triggering `B`, `Category.CIVILIANS` lists nearby `peds`, and `Category.ENEMIES` finds police units from player spawn.

### User Story 3 - Rich 3D Spatial Audio & Harbor Soundscape (Priority: P1)
World entities emit spatial 3D audio with distance attenuation and Doppler tracking: punch swing/hit, nearby NPC footsteps & scared/downed reactions, nearby civilian/cop vehicle engines + police sirens (when Wanted) + horns + tire screeches + crashes + car doors, aircraft propeller audio, bullet impacts, jump/land/slide/plate/pickup/shop/bar/respray cues, and 3D zone ambience (south Harbor ocean waves, Bar groove, Gun Shop chime, Army Base wind/airfield).

**Independent Test**: Headless test verifies AudioServer sub-buses (`SFX`, `Vehicles`, `Ambience`, `A11y`), 3D vehicle/pedestrian pools with `ATTENUATION_INVERSE_DISTANCE` and `DOPPLER_TRACKING_PHYSICS_STEP`, punch/pickup/siren/zone audio triggers, and non-zero peak synthesized streams.

### User Story 4 - Save/Load System & Streamlined Menu (Priority: P1)
Day/Night toggle buttons are removed from Main/Pause menus and HUD. Players can Save (`Pause -> Save Game`), Load (`Pause -> Load Game` or `Main Menu -> Continue Game`), and rely on milestone Auto-saves stored as versioned JSON with rolling `.bak` backup in `user://open_world_save.json`.

**Independent Test**: Headless test mutates money, phase, packages, pickups, player position/health/weapons/ammo, and coupe position, saves to a test path, resets/modifies state, loads back, and verifies full state restoration plus `.bak` fallback safety.

### User Story 5 - District GPS Callouts & 360° Audio Sonar Sweep (Priority: P2)
Moving between Harbor District zones updates a clean GPS district label and optional NVDA callout. Pressing the Sonar Sweep key (`G`) plays a quick directional left-to-right stereo audio sweep of nearest entities and summarizes nearby threats/vehicles/places.

**Independent Test**: Headless test verifies district resolution across coordinates (`Harbor Pier`, `Downtown`, `Warehouse District`, `Civic Center`, `Army Base`) and sonar sweep execution without errors.

## Functional Requirements

- **FR-001**: `CombatInput` MUST bind keyboard defaults for `fire` (`KEY_SEMICOLON` + `MOUSE_BUTTON_LEFT`), `aim` (`KEY_APOSTROPHE` + `MOUSE_BUTTON_RIGHT`), `cycle_weapon_up` (`KEY_EQUAL` + `MOUSE_BUTTON_WHEEL_UP`), `cycle_weapon_down` (`KEY_MINUS` + `MOUSE_BUTTON_WHEEL_DOWN`), `weapon_holster` (`KEY_0`), `a11y_radar_cycle_prev` (`Shift+B`), and `a11y_sonar_sweep` (`KEY_G`), with zero `Insert` or `CapsLock` conflicts.
- **FR-002**: Pressing `fire` while `player.weapon == Arsenal.Id.NONE` MUST execute punch/melee (`_try_punch()`).
- **FR-003**: `A11yUIHelper.action_pressed()` MUST distinguish modifier-qualified actions (`Shift+B`) from unmodified actions (`B`).
- **FR-004**: `A11yRadar` MUST expose `Category.CIVILIANS` for `peds` and extend `Category.ENEMIES` to find nearest police vehicles/officers across the district.
- **FR-005**: `GameHUD` MUST omit Day/Night menu buttons and HUD time chip, and include `CONTINUE GAME`, `NEW GAME`, `SAVE GAME`, and `LOAD GAME` controls with full NVDA narration.
- **FR-006**: `SaveManager` MUST persist versioned JSON (`version: 1`) with `.bak` backup and safe `.get()` deserialization.
- **FR-007**: `A11ySpatialAudio` & `CityAudio` MUST provide pooled 3D audio for punches, NPCs, vehicles (with Doppler + police sirens), aircraft, zone ambience, and sonar sweeps routed through dedicated AudioBuses with a Master Limiter.
