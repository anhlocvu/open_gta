# Implementation Plan: Keyboard Parity, 3D World Audio, Save/Load & Radar Polish

**Branch**: `003-keyboard-audio-save` | **Date**: 2026-11-25 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/003-keyboard-audio-save/spec.md)

## Technical Context
- **Engine**: Godot 4.7.2 (`GL Compatibility`), GDScript, NVDA-only ClassDB bridge (`NvdaWrapper`, `A11ySpeech`).
- **Storage**: Versioned JSON + rolling `.bak` in `user://open_world_save.json` (`SaveManager`); settings in `user://open_world_settings.cfg`.
- **Audio**: `AudioServer` bus hierarchy (`Master` + Limiter -> `SFX`, `Vehicles`, `Ambience`, `A11y`), pooled `AudioStreamPlayer3D` (`ATTENUATION_INVERSE_DISTANCE`, `DOPPLER_TRACKING_PHYSICS_STEP`) + procedural PCM `AudioStreamWAV`.
- **Testing**: Headless `godot_console --headless --path . --script tests/<suite>.gd`.

## Architecture & Module Layout
1. **Input & Combat Parity**:
   - `scripts/combat_input.gd`: Add dual mouse+keyboard defaults (`;`, `'`, `-`, `=`, `0`, `Shift+B`, `G`), update `project.godot` if needed (keep `CombatInput.install()` authoritative for missing bindings and verify existing bindings).
   - `scripts/accessibility/a11y_ui_helper.gd`: Upgrade `action_pressed()` to support `exact_match = true` for modifier-aware matching (both real and synthetic `InputEventKey` events).
   - `scripts/player.gd` & `scripts/game.gd`: Include `Arsenal.Id.NONE` in `cycle_weapon()`, add `weapon_holster` (`0`), make `fire` trigger `_try_punch()` when unarmed, unify primary attack handling.
2. **Radar & Aim Fixes + Visual Sync**:
   - `scripts/accessibility/a11y_radar.gd`: Add `Category.CIVILIANS`, support `cycle_category(step := 1)`, widen `Category.ENEMIES` police scan to city-wide nearest units (prioritizing active chasers), add `passes_filter()` / `locked_target_id` helpers.
   - `scripts/accessibility/a11y_aim_assist.gd`: Keep officer priority over civilians and announce `"Officer"` vs `"Civilian Pedestrian"` clearly.
   - `scripts/accessibility/a11y_gameplay_controller.gd`: Handle `a11y_radar_cycle_prev` before `a11y_radar_cycle`, handle `a11y_sonar_sweep`, announce `"Unarmed, fists"` when holstering, and notify district transitions.
   - `scripts/radar.gd`: Sync visual radar blips with active `A11yRadar.selected_category` and draw highlighted target reticle/heading line to `locked_target_id`.
3. **3D Spatial Audio, Doppler Vehicles, NPCs & Zone Ambience**:
   - `scripts/accessibility/a11y_spatial_audio.gd`: Setup AudioBuses (`SFX`, `Vehicles`, `Ambience`, `A11y`) + Master Limiter; add procedural WAV generators (`punch_swing`, `punch_hit`, `npc_scare`, `car_horn`, `car_crash`, `car_door`, `tire_screech`, `siren_loop`, `traffic_engine_loop`, `aircraft_engine_loop`, `ocean_loop`, `bar_loop`, `shop_chime`, `cash_register`, `sonar_ping`, `jump`, `land`, `slide`, `bullet_impact`); add distance-culled dynamic 3D emitters for nearest NPC footsteps, nearest vehicles (with Doppler & sirens), aircraft engine, and 4 Harbor District ambient emitters (Harbor Pier ocean, Bar, Gun Shop, Army Base).
   - Wire all gameplay triggers in `scripts/game.gd`, `scripts/player.gd`, `scripts/pedestrian.gd`, `scripts/vehicle.gd`, `scripts/aircraft.gd`.
4. **Save/Load & Menu Streamline**:
   - `scripts/save_manager.gd`: Static/RefCounted `SaveManager` with `save_game()`, `load_game()`, `has_save()`, `peek_summary()`, atomic temp+`.bak` write, version migration check, and deterministic pickup/crate keys.
   - `scripts/game.gd`: Add `serialize_state()`, `apply_saved_state()`, `new_game()`, `save_current_game()`, `load_saved_game()`, auto-save on mission milestones, and expose `district_name(pos)`.
   - `scripts/hud.gd`: Remove Day/Night buttons (`_day_btn`, `_night_btn`, `_time_chip`); add `CONTINUE GAME`, `NEW GAME`, `SAVE GAME`, `LOAD GAME`, district indicator label, and updated `ACTION_LABELS` + `_speak_context_help()`.
5. **Verification & Release**:
   - Update `tests/test_accessibility.gd`, `tests/test_combat.gd`, and add `tests/test_save_and_audio.gd`.
   - Run full headless test suite, code review pass, Windows release export (`export/windows/OperationChaos.exe`), and update `GEMINI.md`.
