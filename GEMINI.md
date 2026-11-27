##rules

bắt buộc luôn luôn kích hoạt các skill godot master và các skill về godot, các skill về trợ năng và audio game, để người dùng ra ý tưởng không cần phải yêu cầu kích hoạt
# Project Development Log (`GEMINI.md`)

## Session: 2026-11-25 — End-to-End NVDA Accessibility System & English Localization

### Summary
Implemented a complete NVDA-only accessibility architecture and translated all user-facing text in **Operation Chaos** (`GTA-mini`, Godot 4.7.2) to English across both Competitive modes (`scenes/competitive_main.tscn`) and Open World mode (`scenes/main.tscn`), governed by SpecKit (`specs/001-nvda-accessibility-system/`) and ECC workflows.

### Key Architectural Decisions
- **NVDA-Only Speech (Zero SAPI)**:
  - Updated `addons/nvda_integration/NvdaWrapper.gd` to remove SAPI (`DisplayServer.tts_speak` / `tts_get_voices_for_language`) fallback and talk strictly to the `NVDA` GDExtension singleton (`Engine.get_singleton("NVDA")`).
  - Registered `NvdaWrapper` and `A11ySpeech` (`scripts/accessibility/a11y_speech.gd`) as Autoloads in `project.godot`. `addons/gato_tts` is intentionally NOT enabled or referenced.
  - `A11ySpeech` provides priority levels (`LOW`, `NORMAL`, `HIGH`, `CRITICAL`), FIFO tie-broken queuing, deduplication, and a 30-entry speech history buffer (`[` / `]` / `\`).
  - `A11ySpeech` also hosts the `addons/gato_screen_filters` visual filters (`Off`, `Grayscale`, `Protanopia`, `Deuteranopia`, `Tritanopia`) controllable in Settings without conflicting with `F6` (`graphics_profile`).
- **Reserved NVDA Modifiers Protected**:
  - `Insert` and `CapsLock` are never bound by any game or accessibility action and are explicitly rejected during Settings key rebinding.
- **UI & Menu Accessibility (`MatchHUD` & `GameHUD`)**:
  - Created `scripts/accessibility/a11y_ui_helper.gd` enabling `Control.FOCUS_ALL`, high-contrast focus borders, queued screen-transition focus callouts, and live NVDA narration for buttons, checkboxes, sliders, dropdowns (including popup focus), and keybind capture/cancel.
  - Added an **Accessibility (NVDA & Audio)** section inside `MatchHUD` Settings persisted via `A11ySettings` (`scripts/accessibility/a11y_settings.gd`) into `user://competitive_settings.cfg`.
- **3D Navigation, Spatial Audio & Fair-Play Aim Assist**:
  - `scripts/accessibility/a11y_radar.gd`: Compass headings (`North`..`Northwest`), player-relative bearings (`ahead`, `ahead left`, `to your right`, `behind you`, `above`/`below`), and categorized target scanning (`All`, `Enemies`, `Objectives`, `Loot and Pickups`, `Allies`, `Places and Vehicles`) across both Competitive and live Open World nodes (`world_pickups` group).
  - `scripts/accessibility/a11y_navigation.gd`: Keyboard camera turning (`J`/`L` snap 15°/30°/45°/90° or smooth, `I`/`K` pitch, `U` horizon level), A* waypoint 3D audio beacons (`MatchArena.route()`), obstacle/cover proximity ticks, and safely cancellable Auto-Walk (`Player.a11y_move_override`).
  - `scripts/accessibility/a11y_spatial_audio.gd`: Procedural WAV synthesis + pooled `AudioStreamPlayer3D` (`ATTENUATION_INVERSE_DISTANCE`, 16 3D voices + 6 UI voices) for gunfire, footsteps, hit/armor-break/headshot/damage-taken cues, reloads, empty magazine clicks, pickups, beacons, and acoustic crosshair pings.
  - `scripts/accessibility/a11y_aim_assist.gd`: Acoustic crosshair cone pings and LOS-validated `Snap Aim` (`O`) that checks unobstructed physics raycasts and never tracks through walls.
  - `scripts/accessibility/a11y_gameplay_controller.gd`: Wired into `scripts/modes/competitive_game.gd`, `scripts/modes/match_manager.gd`, `scripts/combat/weapon_system.gd`, `scripts/game.gd`, `scripts/pickup.gd`, and `scripts/player.gd`.

### Default Accessibility Keybindings
- `J` / `L`: Turn Left / Right (Snap Turn or Smooth)
- `I` / `K`: Look Up / Down
- `U`: Center Pitch / Level Horizon
- `O`: Snap Aim to Nearest Visible Enemy (LOS-checked)
- `Z`: Read Player & Match/World Status
- `X`: Read Objective & Safe Zone / Distance
- `H`: Read Compass Heading & Stance
- `B`: Cycle Radar Category
- `,` / `.`: Previous / Next Radar Target
- `M`: Toggle 3D Audio Navigation Beacon
- `P`: Toggle Auto-Walk Toward Tracked Target
- `[` / `]`: Speech History Previous / Next
- `\`: Repeat Last Speech
- `/`: Speak Context Accessibility Help

### Verified Checks (Post-Final-Edit, Headless)
- `godot_console --headless --path . --quit-after 5`: exit 0
- `tests/test_accessibility_speech.gd`: 17 checks, 0 failures
- `tests/test_accessibility.gd`: 26 checks, 0 failures
- `tests/test_lightweight_menu.gd`: 11 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- `tests/test_combat.gd`: 40 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_map_navigation.gd`: 7 checks, 0 failures
- `tests/test_game_integration.gd`: 14 checks, 0 failures
- Total verified post-edit: **149 checks, 0 failures**.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes), `export/windows/OperationChaos.pck` (`115,540,036` bytes), `export/windows/libgdnvda.windows.template_release.x86_64.dll` (`559,104` bytes), and `export/windows/nvdaControllerClient64.dll` (`265,632` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`) with zero errors.
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output and real audio hardware listening remains to be manually verified by the user.


## Session: 2026-11-25 — Open-World-Only Streamline (Option 1) & `.exe` Rebuild

### Summary
Converted **Operation Chaos** (`GTA-mini`) to an Open-World-only experience (`res://scenes/main.tscn`), completely removing competitive modes (`Protege o Corre!`, `Favela Royale`, AI bots, LAN networking, and announcer assets), governed by `specs/002-open-world-only/`. Preserved and refined the NVDA-only English accessibility architecture across gameplay, pause menu, settings persistence (`user://open_world_settings.cfg`), and key rebinding.

### Key Changes
- **Competitive Removal**:
  - Deleted `scenes/competitive_main.tscn`, `scenes/announcer_test.tscn`, `scenes/maps/`, `scripts/modes/`, `scripts/ai/`, `scripts/network/`, `scripts/combat/weapon_system.gd`, `scripts/announcer_manager.gd`, `scripts/announcer_test.gd`, `audio/announcer/`, `resources/maps/`, `resources/ai/`, competitive `.tres` configs (`loot_default.tres`, `match_default.tres`, `safe_zone_default.tres`), and competitive/benchmark tests.
  - Relocated `TacticalConfig` to `scripts/tactical_config.gd` and updated `resources/tactical_default.tres` and `project.godot` (`run/main_scene="res://scenes/main.tscn"`).
- **Open World Menu, Pause, Settings & Input Fixes**:
  - Updated `scripts/game.gd` and `scripts/hud.gd` (`GameHUD`) with Open World Main Menu, Pause Menu (`Tab`/`Esc`), Graphics/Camera/FOV/Audio/NVDA Accessibility Settings, Screen Filters, and Key Rebinding (rejecting `Insert` and `CapsLock` both on rebind capture and config load).
  - Resolved `gdscript-reviewer` findings: added `_banner_seq` + `is_instance_valid(hud)` guards via `_flash_banner()` across all temporary HUD banner timers; added `_action_pressed()` so rebound actions and synthetic test `InputEventKey` events both honor `InputMap`; guarded mouse capture and weapon/gameplay inputs during `TITLE`/`BUSTED`/`WASTED`; updated `radar_objective()` in `Phase.FREE` to track nearest uncollected package; updated `scripts/radar.gd` null-checks and visibility-gated redraws.
- **Accessibility Streamline**:
  - Simplified `scripts/accessibility/a11y_speech.gd`, `a11y_radar.gd`, `a11y_aim_assist.gd`, `a11y_navigation.gd`, and `a11y_gameplay_controller.gd` for Open World Harbor District landmarks, vehicles, aircraft, `world_pickups`, `foot_cops`, wanted level callouts, and proper target clearing during `Phase.HEAT`.

### Verified Checks (Post-Final-Edit, Headless)
- `godot_console --headless --path . --import`: exit `0`
- `godot_console --headless --path . --quit-after 5`: exit `0`
- `tests/test_accessibility_speech.gd`: 17 checks, 0 failures
- `tests/test_accessibility.gd`: 29 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- `tests/test_combat.gd`: 40 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 14 checks, 0 failures (verified twice consecutively)
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- Total verified post-edit: **147 checks, 0 failures**.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes), `export/windows/OperationChaos.pck` (`114,785,492` bytes), `export/windows/libgdnvda.windows.template_release.x86_64.dll` (`559,104` bytes), and `export/windows/nvdaControllerClient64.dll` (`265,632` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output and real audio hardware listening remains to be manually verified by the user.


## Session: 2026-11-25 — NVDA ClassDB Speech Bridge, Input Device Matching & Menu/City Performance Fix

### Root Causes Diagnosed
1. **In-game NVDA silence (`NVDA` ClassDB vs `Engine.has_singleton`)**:
   - `libgdnvda` (`nvda.gdextension`) registers `NVDA` as a `ClassDB` class with static methods (`NVDA.is_running()`, `NVDA.speak_text()`, `NVDA.cancel()`, `NVDA.braille_message()`), NOT an `Engine` singleton.
   - `addons/nvda_integration/NvdaWrapper.gd` and `scripts/accessibility/a11y_speech.gd` previously checked `Engine.has_singleton("NVDA")`, which always returned `false`, silently dropping every `A11ySpeech` callout (while Main Menu buttons were only being read slowly via Godot 4.7's default AccessKit UIA driver).
   - `scripts/combat_input.gd` also bound actions with `event.device = 0`, whereas Godot 4.7 keyboard events use `device = 16` (`-1` All Devices is required for hardware compatibility).
2. **Menu Arrow Lag & Slow NVDA Response (~2–5 FPS on Intel HD 4600 ANGLE)**:
   - On `Phase.TITLE`, `scenes/main.tscn` kept the entire 3D Harbor District visible and running physics/AI raycasts behind `_start_panel`, with `5,633` `City` child nodes (~2,700+ individual road dash `MeshInstance3D`s), ~1,500 duplicate `StandardMaterial3D` instances, `Sky.PROCESS_MODE_REALTIME` (2K HDRI), `msaa_3d = 2`, and AccessKit UIA running concurrently.

### Key Changes
- **NVDA ClassDB Bridge & Single-Channel Speech**:
  - Rewrote `addons/nvda_integration/NvdaWrapper.gd` with a leak-free cached GDScript static bridge resolving `ClassDB.class_exists(&"NVDA")` (`NVDA.is_running()`, `NVDA.speak_text()`, `NVDA.cancel()`) and a `350 ms` `is_running` cache to cut redundant IPC calls.
  - Updated `scripts/accessibility/a11y_speech.gd` to route directly through `NvdaBridge` (removing `Engine.has_singleton("NVDA")`).
  - Updated `scripts/accessibility/a11y_ui_helper.gd` (`_focus_interrupt(ctrl)` keyed by target instance ID, `release_focus_safe()`, shared `action_pressed()`) and `scripts/hud.gd` (release lingering UI focus on `show_start(false)` / `show_pause(false)`, shorter main menu intro).
  - Disabled Godot's competing AccessKit UIA driver (`accessibility/general/accessibility_support=2`) and default `msaa_3d=0` in `project.godot`.
- **Input & World Optimization**:
  - Updated `scripts/combat_input.gd` and `project.godot` bindings to `device = -1` (All Devices), and routed `a11y_gameplay_controller.gd`, `a11y_navigation.gd`, and `game.gd` through `A11yUIHelper.action_pressed()`.
  - Added `Game._set_world_active(active)` in `scripts/game.gd` to hide and disable 3D city/actor processing during `Phase.TITLE` (and pause actors during Pause Menu), restoring everything on `begin()`.
  - Batched `City._mesh_box()` geometry into per-material `MultiMeshInstance3D`s (`_flush_box_batches()`) and added `_mat_cache` (`_surfaced_mat`, `_simple_mat`, `_glass_mat`) in `scripts/city.gd`, plus `Sky.PROCESS_MODE_QUALITY` in `scripts/day_night.gd`.

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_accessibility.gd`: 39 checks, 0 failures (includes real `Input.parse_input_event()` across devices `0`, `1`, `16` and `City` batching/Title visibility checks)
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- `tests/test_combat.gd`: 40 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 14 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- Total headless verified: **160 checks, 0 failures**.
- Real Windows renderer benchmark (`Intel(R) HD Graphics 4600` ANGLE): Title steady-state improved from **170–212 ms/frame (1,922 draw calls, 5,633 City children)** down to **8.70 ms/frame (~115 FPS, 22 draw calls, 1,132 City children)**; Play draw calls reduced from **2,086 -> 738**.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes), `export/windows/OperationChaos.pck` (`114,789,652` bytes), `export/windows/libgdnvda.windows.template_release.x86_64.dll` (`559,104` bytes), and `export/windows/nvdaControllerClient64.dll` (`265,632` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output remains to be manually confirmed by the user.


## Session: 2026-11-25 — Keyboard Parity, 3D World Audio, Save/Load & Radar Polish

### Summary
Implemented full keyboard parity for mouse actions (with GTA-style unarmed punch on Fire and weapon cycling through Unarmed), rich 3D world audio (punch, NPC footsteps/reactions, Doppler traffic/cop engines, sirens, horns, crashes, aircraft engine, and Harbor District zone ambience + 360° audio sonar sweep), atomic versioned Save/Load persistence (`user://open_world_save.json` + `.bak`), streamlined menus without Day/Night buttons, Radar `Civilians` + city-wide `Enemies and Police` fixes, `B`/`Shift+B` bidirectional category cycling, visual-audio Radar sync, and District GPS callouts, governed by `specs/003-keyboard-audio-save/` and ECC (`gdscript-reviewer` + TDD).

### Key Changes
- **Keyboard Parity & GTA Combat (`scripts/combat_input.gd`, `project.godot`, `scripts/player.gd`, `scripts/game.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/accessibility/a11y_ui_helper.gd`)**:
  - Added keyboard bindings alongside mouse for `fire` (`;`), `aim` (`'`), `cycle_weapon_up` (`=`), `cycle_weapon_down` (`-`), `weapon_holster` (`0`), `a11y_radar_cycle_prev` (`Shift+B`), and `a11y_sonar_sweep` (`G`).
  - Pressing `fire` while unarmed (`Arsenal.Id.NONE`) triggers `_try_punch()`; `Player.cycle_weapon()` now cycles through `[NONE, ...owned_weapons]`; `Vehicle` and `Aircraft` now consume `InputMap` movement/handbrake actions.
  - Upgraded `A11yUIHelper.action_pressed()` with modifier-aware matching (`exact_modifiers`), fixed `Tab` focus navigation in Pause/Settings, and hardened `capture_binding()` to ignore bare modifier keys and store `device = -1`.
- **Radar & Navigation Fixes (`scripts/accessibility/a11y_radar.gd`, `scripts/accessibility/a11y_aim_assist.gd`, `scripts/accessibility/a11y_navigation.gd`, `scripts/road_graph.gd`, `scripts/radar.gd`)**:
  - Added `Category.CIVILIANS` (`peds` within 120m) so Radar matches `O` Snap Aim civilian targets; widened `Category.ENEMIES` to scan nearest police units city-wide; added direct ID lookup in `resolve_locked_target()`.
  - Added `B` / `Shift+B` bidirectional cycling, visual `Radar` highlighting/dimming synced to active filter & locked target, and `RoadGraph` BFS routing in `A11yNavigation.compute_route_waypoint()`.
- **3D Spatial Audio & World Soundscape (`scripts/accessibility/a11y_spatial_audio.gd`, `scripts/city_audio.gd`, `scripts/pedestrian.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`)**:
  - Configured `AudioServer` buses (`Master` + Limiter -> `SFX`, `Vehicles`, `Ambience`, `A11y`) and cached synthesized PCM WAV streams statically.
  - Added punch swing/hit, jump/land/slide, bullet impact, pickup/shop/respray chimes, NPC 3D footsteps & scared/downed reactions, persistent-slot Doppler 3D vehicle engines, police sirens, horns, tire screeches, crashes, car doors, AN-2 aircraft engine, Harbor Pier ocean/Bar ambience, and `G` 360° stereo sonar sweep.
- **Save/Load & Menu Streamline (`scripts/save_manager.gd`, `scripts/game.gd`, `scripts/hud.gd`, `scripts/pickup.gd`)**:
  - Built `SaveManager` with `user://` sandboxing, strict schema/finite-number validation, atomic `.tmp` write, and `.bak` fallback recovery.
  - Removed `_day_btn`, `_night_btn`, and `_time_chip` from `GameHUD`; added `CONTINUE GAME`, `NEW GAME · OPEN WORLD`, `SAVE GAME`, `LOAD SAVED GAME`, `MAIN MENU`, and GPS district display.

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_accessibility.gd`: 58 checks, 0 failures
- `tests/test_save_and_audio.gd`: 23 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- `tests/test_combat.gd`: 40 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 14 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- Total headless verified: **202 checks, 0 failures**.


## Session: 2026-11-26 — Save/Load Reliability, Weapon Switch NVDA Speech & Universal NPC Loot Drops

### Summary
Fixed explicit Save/Load persistence and `CONTINUE GAME` visibility, added immediate NVDA announcements when switching or checking weapons (including `"No weapons."`), and implemented tiered cash drops (`$30`–`$100,000`) for all NPCs plus weapon drops when knocking down police officers and soldiers, governed by SpecKit (`specs/004-save-weapon-speech-loot/`) and ECC TDD.

### Key Changes
- **Explicit Save/Load & Windows Overwrite Fix (`scripts/save_manager.gd`, `scripts/game.gd`, `scripts/hud.gd`)**:
  - Removed silent milestone auto-saves from `return_to_main_menu()`, `_enter_vehicle()`, `_buy_weapon()`, `_update_mission()`, and `collect_pickup()`, so `user://open_world_save.json` is written only when the player explicitly chooses `SAVE GAME`.
  - Updated `SaveManager.has_save()` to validate via `not peek_summary(path).is_empty()` and hardened `SaveManager.save_data()` on Windows (verify `.tmp` parse before swapping, remove stale `.bak`/primary cleanly before backup/rename with copy fallback, and surface `"SAVE FAILED"` via HUD/NVDA if saving ever fails).
  - Extracted `Game._enter_gameplay_from_title()` and added `set_paused(on, silent := false)` so `begin_saved()` / `load_saved_game()` restore exact `player.global_position` (clearing velocity and calling `force_update_transform()`), `owned_weapons`, `weapon`, `ammo`, and `magazines` without `"Free Chaos started..."` or `"Resumed."` interrupting `"Saved game loaded..."`.
- **Weapon Switch NVDA Speech (`scripts/accessibility/a11y_gameplay_controller.gd`, `scripts/player.gd`, `scripts/game.gd`)**:
  - Added `Player.weapon_spoken_name()` and `A11yGameplayController.announce_weapon_switch()` (`force = true`, `interrupt = true`, syncing `_prev_weapon`) wired directly into `cycle_weapon_up`, `cycle_weapon_down`, `weapon_holster`, and non-shop `weapon_1`..`weapon_4`.
  - Speaks `"No weapons."` when `owned_weapons` is empty, `"No <Weapon>."` when selecting an unowned slot, `"Unarmed, fists."` when holstered, or `"<Weapon>, <mag> in mag, <reserve> reserve."` when armed.
- **Universal Cash & Officer Weapon Drops (`scripts/pedestrian.gd`, `scripts/pickup.gd`, `scripts/game.gd`, `scripts/accessibility/a11y_spatial_audio.gd`, `scripts/accessibility/a11y_radar.gd`)**:
  - Added `Pedestrian.WealthTier` (`POOR`: `$30–$350`, `MIDDLE`: `$400–$3,500`, `WEALTHY`: `$4,000–$25,000`, `RICH`: `$30,000–$100,000`), one-time `cash_dropped` guard, and `loot_weapon_id` for `is_officer` units.
  - Added `WorldPickup.Kind.WEAPON`, `despawn_seconds` (60s for temporary combat drops), `Player.add_ammo_for()`, 3D `A11ySpatialAudio.play_loot_drop()`, and `A11yRadar` labels (`Cash Pickup, $N` and `Weapon Pickup, <Name>`).
  - Knocking down any pedestrian spawns a `CASH` pickup; knocking down an officer/soldier additionally spawns a `WEAPON` pickup (granting new weapons or reserve ammo if already owned) with NVDA drop announcements.

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_accessibility.gd`: 62 checks, 0 failures
- `tests/test_save_and_audio.gd`: 41 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- `tests/test_combat.gd`: 40 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 14 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- Total headless verified: **224 checks, 0 failures**.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes), `export/windows/OperationChaos.pck` (`114,835,916` bytes), `export/windows/libgdnvda.windows.template_release.x86_64.dll` (`559,104` bytes), and `export/windows/nvdaControllerClient64.dll` (`265,632` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output and real audio hardware listening remains to be manually verified by the user.


## Session: 2026-11-26 — Unified Auto-Drive (`P`), Resilient A* Rerouting, Universal Radar Face (`O`) & Vehicle Destruction

### Summary
Implemented unified Auto-Walk / Auto-Drive (`P`), upgraded obstacle-aware A* pathfinding and active stall recovery for both walking and driving, repurposed `O` to face any locked `A11yRadar` target across all categories (preserving `Shift+O` for quick visible enemy snap), and added melee/gunfire vehicle destruction with burning countdowns and AoE explosions, governed by SpecKit (`specs/005-autopilot-radar-vehicle-destruction/`) and ECC (`tdd-guide` + `gdscript-reviewer`).

### Key Changes
- **Weighted A* & Unobstructed Node Selection (`scripts/road_graph.gd`)**:
  - Added `edge_key()`, `nearest_clear()` (prefers closest intersection node with unobstructed static-wall LOS), and `astar_path()` (weighted XZ `g + h` A* supporting blocked-edge penalties for detour routing).
- **Resilient Auto-Walk & Auto-Drive (`scripts/accessibility/a11y_navigation.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`, `scripts/vehicle.gd`)**:
  - Extended `P` (`a11y_autowalk`) to start `Auto-Drive` when driving a `Vehicle` (excluding `Aircraft`), steering and throttling along `RoadGraph` A* waypoints via `Vehicle.a11y_drive_override` / `Vehicle.a11y_handbrake`, slowing for sharp corners, braking on arrival, and cancelling immediately on manual driving input or `P`.
  - Replaced single-ray shortcuts and premature straight-line `dist_total` stall aborts with 3-ray `_corridor_clear()` checks, 7-ray `_scan_whiskers()` wall/vehicle tangent steering, `track_objective` state separation (preventing `_refresh_nav_target()` from wiping custom destinations during `Phase.HEAT`), and active recovery maneuvers (lateral sidestep/reroute on foot; reverse-and-countersteer reroute in vehicles).
- **Universal Radar Target Facing `O` & Quick Snap `Shift+O` (`scripts/accessibility/a11y_aim_assist.gd`, `scripts/accessibility/a11y_radar.gd`, `scripts/combat_input.gd`, `scripts/hud.gd`)**:
  - Extended `A11yRadar.resolve_locked_target()` with per-target `aim_height` and vehicle `hp`.
  - Added `A11yAimAssist.face_radar_target()` on `O` (`a11y_aim_assist`, exact modifiers) to orient `camera.yaw`/`camera.pitch` (and standing `player.rotation.y` when not in cover or vehicle) toward any locked Radar target (officers, civilians, vehicles, aircraft, pickups, places, objective), announcing distance, clear/blocked LOS, and vehicle durability %.
  - Bound `Shift+O` to `a11y_snap_enemy` (`snap_to_visible_enemy()`).
- **Vehicle Melee Damage, Burning Countdown & Explosions (`scripts/player.gd`, `scripts/vehicle.gd`, `scripts/game.gd`, `scripts/wanted_system.gd`, `scripts/shot_effects.gd`, `scripts/accessibility/a11y_spatial_audio.gd`)**:
  - Added `Player.try_punch_vehicle()` (`~2.8m` forward ray + proximity reach, `14.0` damage per punch) wired into `Game._try_punch()` and `Game._try_fire()`.
  - Added `Vehicle` durability stage callouts (`50%` smoking, `25%` critical), `burning` state (`1.8s` countdown with `"Vehicle on fire, press E to get out!"` and unrestricted burning exit), and `_explode()` / `Game.on_vehicle_exploded()` (charred visuals, pooled `ShotEffects.emit_explosion()`, 3D `A11ySpatialAudio.play_explosion()`, camera shake, AoE NPC knockdowns, occupant/nearby player damage, chain-reaction vehicle damage, and `WantedSystem` crimes `vandalism`, `vehicle_explosion`, `destroy_cop`).

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility.gd`: 69 checks, 0 failures (`EXIT=0`)
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures (`EXIT=0`)
- `tests/test_combat.gd`: 44 checks, 0 failures (`EXIT=0`)
- `tests/test_cover.gd`: 10 checks, 0 failures (`EXIT=0`)
- `tests/test_game_integration.gd`: 14 checks, 0 failures (`EXIT=0`)
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures (`EXIT=0`)
- `tests/test_save_and_audio.gd`: 41 checks, 0 failures (`EXIT=0`)
- `tests/test_stage_one.gd`: 24 checks, 0 failures (`EXIT=0`)
- Total headless verified: **235 checks, 0 failures**.
- `godot_console.exe --headless --path . --quit-after 5`: exit `0`.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes), `export/windows/OperationChaos.pck` (`114,859,772` bytes), `export/windows/libgdnvda.windows.template_release.x86_64.dll` (`559,104` bytes), and `export/windows/nvdaControllerClient64.dll` (`265,632` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output and real audio hardware listening remains to be manually verified by the user.


## Session: 2026-11-26 — Speed-Aware Auto-Drive 20m Wall Braking, Context-Sensitive `F` Fire/Melee & Vehicle Hitbox Alignment

### Summary
Upgraded Auto-Drive (`P`) to cruise at `vehicle.max_speed` when the forward corridor (`> 20m` + braking horizon) and lateral surroundings (`>= 3.2m` clear per side) are wide open while smoothly decelerating/braking from `20m` ahead of walls and turning cleanly without high-speed crash explosions; updated `F` (`melee`) to fire the equipped gun when armed (semi-auto and held full-auto) and punch when unarmed; fixed `Player.try_punch()` cooldown lockout blocking vehicle punches; and raised `Vehicle` collision box height to `1.48m` so horizontal shots hit vehicles reliably, governed by SpecKit (`specs/006-autodrive-braking-and-f-fire/`) and ECC (`tdd-guide` + `code-reviewer`).

### Key Changes
- **Wide-Road Cruise & 20m Wall ABS Braking (`scripts/accessibility/a11y_navigation.gd`, `scripts/vehicle.gd`, `scripts/accessibility/a11y_gameplay_controller.gd`)**:
  - Added `_scan_drive_corridor()` (3 forward bumper-width rays starting at vehicle origin with zero hood blind spot, angled escape whiskers `±24°`/`±52°`/`±82°`, and `±90°` lateral clearance rays), `_upcoming_turn_angle()`, `_autodrive_target_speed()`, `_has_rear_clearance()`, and `_handle_autodrive_recovery()`.
  - Auto-Drive targets `vehicle.max_speed` when open ahead and wide on both sides, begins progressive deceleration at `<= 20.0m` from the front bumper (plus early speed-scaled horizon at top speed and upcoming-turn slowdowns), engages zero-drift `a11y_handbrake` ABS braking (`slip = 0.03`, high deceleration toward `0.0`) before impact, retains ABS braking on arrival until stopped, avoids reverse-slam loops when boxed in front and back, prevents `_beacon_timer` from overwriting `current_waypoint` during Auto-Pilot, and avoids interrupting critical `"Vehicle on fire, press E to get out!"` speech.
- **Context-Sensitive `F` Fire/Melee, Punch Cooldown Fix & Vehicle Hitbox (`scripts/game.gd`, `scripts/player.gd`, `scripts/vehicle.gd`, `scripts/hud.gd`, `scripts/pedestrian.gd`)**:
  - Updated `Game._unhandled_input()` so `melee` (`F`) triggers `_try_fire()` and held `_firing` when `player.weapon != Arsenal.Id.NONE`, and `_try_punch()` when unarmed; updated `Player._physics_process()` `fire_held` check, `GameHUD` keybind/menu labels, HUD prompts, and `A11yGameplayController._speak_context_help()`.
  - Fixed `Player.try_punch()` setting `_punch_cd = 0.45` on a pedestrian miss before `Game._try_punch()` could fall through to `try_punch_vehicle()`.
  - Raised `Vehicle._build_collision()` height to `1.48m` (`position.y = 0.74`) so horizontal standing shots (`pitch = -0.04`) hit vehicles instead of flying over the roof; reset `coupe.repair()` on `apply_saved_state()`, reset `a11y_drive_override`/`a11y_handbrake` on enter/set_down, and guarded empty `path` in `Pedestrian._physics_process()`.

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility.gd`: 74 checks, 0 failures
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_combat.gd`: 44 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 18 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- `tests/test_save_and_audio.gd`: 41 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- Total headless verified: **244 checks, 0 failures**.
- `godot_console --headless --path . --quit-after 5`: exit `0`.
- Re-exported `export/windows/OperationChaos.exe` and verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live driving feel, NVDA speech, and audio hardware remains to be manually verified by the user.


## Session: 2026-11-26 — Full World Vehicle Save/Load Persistence & Smooth Engine Audio

### Summary
Fixed driven/stolen vehicles vanishing across Save/Load (`CONTINUE GAME` / `LOAD SAVED GAME`) and driverless stolen cars driving away on exit, and replaced the abrupt "auto-tune" engine pitch response with a warm 4-stroke combustion loop and inertial slew-rate-limited RPM/pitch smoothing, governed by SpecKit (`specs/007-vehicle-save-and-smooth-engine-audio/`) and ECC (`tdd-guide` + `gdscript-reviewer`).

### Key Changes
- **Full World Vehicle & Aircraft Persistence (`scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/models.gd`, `scripts/save_manager.gd`, `scripts/game.gd`)**:
  - Assigned deterministic `save_id`s to every spawned `Vehicle` (`coupe`, `parked:<i>`, `civ:<i>`, `cop:<i>`, `mil:<i>`, `cop_dyn:<i>`) and `Aircraft` (`air:<i>`), and made `GameModels.car_for()` deterministic from `save_id` so parked/civilian cars keep their exact model and `display_name` across relaunches.
  - Added `SaveManager.safe_float()`, `safe_int()`, `safe_str()`, and `safe_angle()`, plus `Vehicle.to_save_dict()`/`apply_save_dict()` (with `_orig_mesh_mats` material restore in `repair()`, `wrapf` angle wrapping, and `ai_enabled` gating) and `Aircraft.to_save_dict()`/`apply_save_dict()`.
  - Extended `Game.serialize_state()` and `apply_saved_state()` to persist and restore all `"vehicles"`, `"aircraft"`, `"active_vehicle_id"`, and `"active_aircraft_id"` (including dynamic `cop_dyn:*` recreation/cleanup and burning-vehicle seating) while preserving full backward compatibility with legacy v1 `"coupe"` saves.
  - Fixed `Game._exit_vehicle()`, `_update_cops()`, and `_update_civilians()` so driverless stolen vehicles (`has_driver == false`) stay parked where left instead of re-enabling AI and driving away.
- **Natural Smooth Engine Audio (`scripts/city_audio.gd`, `scripts/accessibility/a11y_spatial_audio.gd`, `scripts/vehicle.gd`, `scripts/game.gd`)**:
  - Upgraded `CityAudio.make_engine()` to a seamless 6,300-sample (`12 x 525`, `42 Hz` fundamental) 4-stroke combustion loop with `0.5x`/`1.5x`/`2.5x` sub-harmonic firing cadence, low-level mechanical texture, and soft `tanh` saturation.
  - Added `Vehicle.throttle_input` tracking and inertial slew-rate-limited RPM/pitch smoothing in `CityAudio._tick_engine(delta, vehicle)` over a natural `0.74..1.48` monotonic pitch curve (stopping cleanly on `Game.set_paused(true)` and preventing RPM surges while braking forward).
  - Smoothed 3D traffic slot and aircraft engine `pitch_scale` per frame in `A11ySpatialAudio` instead of stepping every `0.08s`.

### Verified Checks (Post-Final-Edit, Headless)
- `tests/test_accessibility.gd`: 74 checks, 0 failures
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_combat.gd`: 44 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 18 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- `tests/test_save_and_audio.gd`: 60 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- Total headless verified: **263 checks, 0 failures**.
- `godot_console --headless --path . --quit-after 5`: exit `0`.
- Re-exported `export/windows/OperationChaos.exe` (`109,149,184` bytes) and `export/windows/OperationChaos.pck` (`114,874,684` bytes); verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive listening QA of the updated engine audio and live Windows gameplay remains to be manually confirmed by the user.


## Session: 2026-11-26 — Radar Split (`Vehicles` / `Places` / `My Assets`), `anhloc.env` Dev Panel, Vehicle Dealership & Hospital Navigation Fix

### Summary
Split the Open World Radar's combined `Places and Vehicles` category into separate `Vehicles`, `Places` (all 8 Harbor District landmarks city-wide), and `My Assets` (all purchased and hijacked/boarded vehicles and aircraft city-wide); fixed the Hospital and Police Station building collision overlap that trapped Auto-Walk in a loop; implemented `DevMode` gated by `anhloc.env` (`lll20042004`) with an NVDA-accessible `F1` Dev Panel; and added the `Vehicle Dealership` (`AUTO`) with an accessible purchase menu (`Enter`), external spawn + immediate seating, and full Save/Load support, governed by SpecKit (`specs/008-radar-split-dev-dealership-hospital-fix/`) and ECC (`tdd-guide` + `code-reviewer`).

### Key Changes
- **Radar Split & `My Assets` Tracking (`scripts/accessibility/a11y_radar.gd`, `scripts/radar.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/game.gd`)**:
  - Updated `A11yRadar.Category` to `ALL`, `ENEMIES`, `CIVILIANS`, `OBJECTIVES`, `LOOT`, `VEHICLES`, `PLACES`, and `ASSETS` (`My Assets`).
  - `Category.PLACES` returns all 8 map landmarks (`Gun Shop`, `Bar`, `Pay and Spray`, `Drop Warehouse`, `Hospital`, `Police Station`, `Army Base`, `Vehicle Dealership`) across the entire map with zero vehicles; `Category.VEHICLES` returns unoccupied vehicles and aircraft; `Category.ASSETS` tracks all intact unoccupied vehicles and aircraft with `player_owned == true` (purchased at Dealership or entered/stolen via `_enter_vehicle()` / `_enter_aircraft()`) city-wide without a 120m limit.
  - Synchronized `Radar._draw()` highlighting/dimming across `VEHICLES`, `PLACES`, and `ASSETS` (cyan blips for owned assets).
- **Hospital & Police Station Entrance Clearance (`scripts/city.gd`, `scripts/game.gd`)**:
  - Shifted `hospital_pos` and `station_pos` forward onto each block's open front apron (`+7.2m`) and set the Hospital (`Vector3(20, 28, 12)`) and Police Station (`Vector3(18, 24, 12)`) buildings back at `-9.2m` so `hospital_pos`, `station_pos`, `health_spawns[0]`, and `_respawn()` points sit completely outside static building colliders for clean Auto-Walk / Auto-Drive arrival.
- **Dev Mode (`anhloc.env`) & `F1` Dev Panel (`scripts/dev_mode.gd`, `scripts/combat_input.gd`, `scripts/player.gd`, `scripts/hud.gd`, `scripts/game.gd`, `export_presets.cfg`)**:
  - Added `DevMode` reading `anhloc.env` beside the executable (with `res://anhloc.env` editor fallback) and verifying the `lll20042004` code via salted SHA-256 comparison (`*.env` excluded on both Android and Windows export presets).
  - Bound `F1` (`dev_panel`) to toggle an NVDA-accessible Dev Panel (`GameHUD._dev_panel`) with Add Infinite Money (`$999,999,999` + spend bypass), Infinite Ammo + All Weapons (`Player.infinite_ammo`), Clear Wanted Level, Full Health & Armor, God Mode (`Player.god_mode`), and Repair Current Vehicle.
- **Vehicle Dealership (`scripts/models.gd`, `scripts/city.gd`, `scripts/hud.gd`, `scripts/game.gd`)**:
  - Added `GameModels.dealership_catalog()` with unique IDs covering every vehicle (`AMBER COUPE`, `POLICE UNIT`, `PATROL JEEP`, and every unique car in `CIV_CARS` & `PARKED_CARS`) plus `AN-2 CIVILIAN` and `AN-2 MILITARY` aircraft.
  - Placed `Vehicle Dealership` (`AUTO`) in block `(6, 4)` with open exterior spawn lane `dealership_spawn_pos` on `st_zs[5]`. Pressing `Enter` near `dealership_pos` opens `GameHUD._dealer_panel`; purchasing deducts cash, spawns the vehicle/aircraft outside without overlapping existing vehicles, marks `player_owned = true`, and seats the player immediately.
  - Added Save/Load reconstruction and cleanup for dynamic `bought_veh:*` and `bought_air:*` assets with `GameModels.is_valid_car_model_path()` and `Color.html_is_valid()` sanitization; routed `[`/`]`/`\`/`/` NVDA speech review keys before modal early returns.

### Verified Checks (Post-Final-Edit, Headless)
- `tests/test_dealership_and_dev.gd`: 21 checks, 0 failures
- `tests/test_accessibility.gd`: 81 checks, 0 failures
- `tests/test_save_and_audio.gd`: 63 checks, 0 failures
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_combat.gd`: 44 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 18 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- Total headless verified: **294 checks, 0 failures**.
- `godot_console.exe --headless --path . --quit-after 5`: exit `0`.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes) and `export/windows/OperationChaos.pck` (`114,896,060` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive gameplay with live Windows `NVDA.exe` speech output remains to be manually confirmed by the user.


## Session: 2026-11-26 — Smart Entrance-Aware Auto-Walk, Auto-Drive & Landmark Clearance

### Summary
Fixed Auto-Walk trapping inside `Vehicle Dealership` (and enclosed storefronts `Gun Shop` / `Bar`), fixed `Pay and Spray` / `Drop Warehouse` building collider overlaps that caused Auto-Drive to reverse and circle endlessly, fixed long-distance Auto-Walk (`Hospital` -> `Vehicle Dealership`) backward-snapping loops, and upgraded `RoadGraph` + `A11yNavigation` into an entrance/exit-aware, multi-layer navigation system governed by SpecKit (`specs/009-smart-navigation-entrances/`) and ECC (`tdd-guide` + `code-reviewer`).

### Key Changes
- **Service Pad Clearance & Navigation Zone Registry (`scripts/city.gd`, `scripts/city_nav_builder.gd`)**:
  - Shifted `spray_pos` (`Pay and Spray`, `mid_z + 6.5`) and `garage_pos` (`Drop Warehouse`, `mid_z + 6.0`) onto open front aprons with their buildings set back (`-11.5m` / `-12.0m`), south-facing `SPRAY` / `DROP` signs, and relocated warehouse crates so `_spray` and `_garage` pads are 100% clear of static wall colliders.
  - Added `CityNavBuilder` (`scripts/city_nav_builder.gd`) defining `nav_zones` (`bounds`, `interior_pos`, `door_pos`, `apron_pos`, `drive_pos`, `enclosed`, `walk_only_entry`, `parent_zone`) for `army_hangar`, `army_base`, `dealership`, `gun_shop`, `bar`, `spray`, `garage`, `hospital`, and `station`, plus `City.resolve_drive_target()` and `City.find_containing_zone()`.
- **Multi-Layer Portal & Corridor-Width `RoadGraph` (`scripts/road_graph.gd`, `scripts/city_nav_builder.gd`)**:
  - Extended `RoadGraph` with `node_kinds` (`"road"`, `"sidewalk"`, `"park"`, `"apron"`, `"door"`, `"interior"`), `edge_modes` (`"both"` vs `"walk"`), and `grid_count` isolation (keeping traffic/cop AI on the street grid).
  - Added shared `RoadGraph.corridor_clear()` (3-ray width check), `"walk"`/`"drive"` edge filtering in `astar_path()`, park shortcuts, front-sidewalk links, and automatic portal anchoring (`_zone_anchor()`) so enclosed interiors route cleanly through their open doorway/gate while nested `army_base <-> army_hangar` routes stay internal.
- **Monotonic Anti-Loop `A11yNavigation` (`scripts/accessibility/a11y_navigation.gd`)**:
  - Separated static macro A* (`mask = 1`) from dynamic local avoidance (`mask = 1 | 4 | 8`) and enforced monotonic forward `_path_idx` progression in `_refresh_route()`, eliminating 0.5s backward intersection snapping when vehicles pass on the street.
  - Upgraded `_tick_autowalk()` with a 7-ray forward steering fan (`_scan_walk_fan()`), `_avoid_side` hysteresis, sharp-turn stride throttling (`> 45°` / `> 95°`), and wall-clear arrival gating (`_corridor_clear` on `dist_total <= 2.2`).
  - Upgraded `_tick_autodrive()` with `resolve_drive_target()` (stopping cleanly at exterior aprons outside walk-in storefronts `"Arrived outside ..."`), pad-back-wall steer suppression (`obstacle_before_pad`), and `_update_progress_tracker()` net-progress anti-circle loop detection (`_best_wp_dist` / `_no_progress_timer`) for both walking and driving.

### Verified Checks (Post-Final-Edit)
- `tests/test_accessibility.gd`: 94 checks, 0 failures
- `tests/test_dealership_and_dev.gd`: 21 checks, 0 failures
- `tests/test_accessibility_speech.gd`: 20 checks, 0 failures
- `tests/test_save_and_audio.gd`: 63 checks, 0 failures
- `tests/test_combat.gd`: 44 checks, 0 failures
- `tests/test_cover.gd`: 10 checks, 0 failures
- `tests/test_game_integration.gd`: 18 checks, 0 failures
- `tests/test_harbor_feel.gd`: 13 checks, 0 failures
- `tests/test_stage_one.gd`: 24 checks, 0 failures
- Total headless verified: **307 checks, 0 failures**.
- `godot_console.exe --headless --path . --quit-after 5`: exit `0`.
- **Windows Release Export**:
  - Exported `export/windows/OperationChaos.exe` (`109,149,184` bytes) and `export/windows/OperationChaos.pck` (`114,910,572` bytes).
  - Verified `OperationChaos.exe --headless --quit-after 5` exits cleanly (`exit code 0`).
- Note: Interactive driving/walking feel and live Windows `NVDA.exe` speech output remain to be manually verified by the user.

<!-- graft:start -->
## Graft — repo context graph

This repo is indexed in `graft/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `graft map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `graft ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `graft grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `graft skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `graft callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `graft/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `graft ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `graft build` (deterministic,
no API key, $0).
<!-- graft:end -->
