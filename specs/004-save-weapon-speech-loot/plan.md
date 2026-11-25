# Implementation Plan: Reliable Save/Load, Weapon Switch Speech & Loot Drops

**Branch**: `004-save-weapon-speech-loot` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/004-save-weapon-speech-loot/spec.md)

## Technical Context
- **Engine**: Godot 4.7.2 (`GL Compatibility`), GDScript, NVDA ClassDB bridge (`A11ySpeech`, `A11yUIHelper`).
- **Persistence**: `SaveManager` (`user://open_world_save.json` + `.bak`) in `scripts/save_manager.gd`, `scripts/game.gd`, `scripts/hud.gd`.
- **Audio & A11y**: `A11yGameplayController`, `A11ySpatialAudio`, `A11yRadar`.
- **Testing**: Headless `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/<suite>.gd`.

## Architecture & Changes
1. **Save/Load Reliability & Explicit Save Discipline**:
   - `scripts/save_manager.gd`:
     - Update `has_save()` to validate via `not peek_summary(path).is_empty()`.
     - Harden `save_data()` on Windows: write `.tmp`, validate `_read_json_dict(tmp_path)`, remove old `.bak` before copying current `.json` to `.bak`, remove old `.json` before renaming `.tmp` to `.json` (with copy fallback if `rename_absolute` fails).
   - `scripts/game.gd`:
     - Remove automatic `save_current_game()` calls from `return_to_main_menu()`, `_enter_vehicle()`, `_buy_weapon()`, `_update_mission()`, and `collect_pickup()`.
     - Extract `_enter_gameplay_from_title()` shared by `begin()` and `begin_saved()`.
     - Add `set_paused(on, silent := false)` so `load_saved_game()` unpauses cleanly without `"Resumed."` interrupting `"Saved game loaded..."`.
     - Zero `player.velocity` and call `player.force_update_transform()` on load; speak district + equipped weapon on load; announce `"Save failed."` + banner if `save_current_game()` fails.
   - `scripts/hud.gd`:
     - Use `SaveManager.peek_summary()` directly in `show_start()` so `CONTINUE GAME` only shows for valid saves and never uses stale fallback values.
2. **Weapon Switch NVDA Announcements**:
   - `scripts/accessibility/a11y_gameplay_controller.gd`:
     - Add `announce_weapon_switch(player: Player, requested_id := -1)` using readable weapon names (`Pistol`, `SMG`, `Rifle`, `Shotgun`), `force = true`, `interrupt = true`, and sync `_prev_weapon = player.weapon` to avoid double speech in `_tick_player_cues()`.
     - Speak `"No weapons."` when `player.owned_weapons.is_empty()` or `"No <Weapon>."` when pressing a slot key for an unowned weapon.
   - `scripts/game.gd`:
     - Call `a11y.announce_weapon_switch(player, ...)` immediately on `cycle_weapon_up`, `cycle_weapon_down`, `weapon_holster`, and `_weapon_or_buy()` (non-shop branch).
3. **NPC Cash & Officer Weapon Drops**:
   - `scripts/pedestrian.gd`:
     - Add `enum WealthTier { POOR, MIDDLE, WEALTHY, RICH }`, `wealth_tier`, `cash_dropped`, `loot_weapon_id`, `roll_cash_drop()`, `wealth_label()`.
     - Assign wealth tier on `_ready()` (civilians weighted 45%/35%/15%/5%; officers weighted toward `MIDDLE`/`WEALTHY`/`RICH` and assigned an officer/soldier `loot_weapon_id`).
     - In `knock_down()`, trigger `game.on_pedestrian_knocked_down(self)` once (`not cash_dropped`).
   - `scripts/pickup.gd`:
     - Add `Kind.WEAPON`, `weapon_id`, `despawn_seconds` (auto-free temporary drops after 60s), slightly wider pickup radius (`1.25m`), and distinct weapon visual glow/color.
   - `scripts/game.gd`:
     - Implement `on_pedestrian_knocked_down(ped: Pedestrian)` to spawn `WorldPickup.Kind.CASH` (and `WorldPickup.Kind.WEAPON` when `ped.is_officer`), play 3D drop audio, and speak clear NVDA drop callout.
     - Extend `collect_pickup()` to accept `weapon_id` and handle `Kind.WEAPON` (grant new weapon or add ammo if already owned) and speak exact picked-up amounts.
   - `scripts/accessibility/a11y_spatial_audio.gd` & `scripts/accessibility/a11y_radar.gd`:
     - Add `play_cash_drop(pos)` / `play_weapon_drop(pos)` 3D cues and expose detailed `Cash Pickup, $N` and `Weapon Pickup, <Name>` labels in `A11yRadar`.
4. **TDD, Review, Export & Documentation**:
   - Extend `tests/test_save_and_audio.gd` and `tests/test_accessibility.gd` (RED first, then GREEN).
   - Run full headless test suite, review diffs, export `export/windows/OperationChaos.exe`, and log to `GEMINI.md`.
