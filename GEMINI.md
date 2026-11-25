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
  - Added `[dependencies]` (`nvdaControllerClient64.dll`) to `nvda.gdextension` and `[preset.1]` (`Windows Desktop`, `x86_64`) to `export_presets.cfg`.
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
