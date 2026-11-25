# Implementation Plan: End-to-End NVDA Accessibility & English Localization

**Branch**: `001-nvda-accessibility-system` | **Date**: 2026-11-25 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/001-nvda-accessibility-system/spec.md)

## Summary

Implement a complete, modular, NVDA-only accessibility architecture for **Operation Chaos** (`GTA-mini`) in Godot 4.7.2 covering both Competitive modes (`scenes/competitive_main.tscn`) and Open World mode (`scenes/main.tscn`), plus full English localization of all user-facing strings.

## Technical Context

**Language/Version**: GDScript 2.0 (Godot 4.7.2.stable, GL Compatibility)
**Primary Dependencies**: `addons/nvda_integration` (`NVDA` GDExtension + `NvdaWrapper.gd`), `addons/gato_screen_filters` (shader filters integrated safely into Settings without `F6` conflict), Godot built-in `AudioStreamPlayer3D`, `AStarGrid2D`, `PhysicsDirectSpaceState3D`.
**Storage**: `user://competitive_settings.cfg` (`ConfigFile`)
**Testing**: Godot headless `--script` test suites under `tests/` (`test_accessibility.gd` + existing test suite)
**Target Platform**: Windows Desktop (with NVDA running; safe no-op when NVDA absent in headless CI)
**Constraints**:
- Strictly NO SAPI (`DisplayServer.tts_speak`) or `gato_tts` fallback.
- Never bind `Insert` or `CapsLock` (reserved NVDA modifiers).
- Preserve `test_lightweight_menu.gd` constraints (competitive entry must not load archived `City` or `Game` scripts or HDRIs at startup).

## Architecture & Module Breakdown

```text
scripts/accessibility/
├── a11y_speech.gd         # Autoload: NVDA-only speech router, priority queue, dedup, 30-item history buffer
├── a11y_settings.gd       # Pure RefCounted/Resource config for accessibility prefs & persistence helpers
├── a11y_spatial_audio.gd  # Procedural WAV synthesis + AudioStreamPlayer3D pool (gunfire, steps, hits, beacons)
├── a11y_radar.gd          # Relative bearing/compass math + categorized target scanner (Competitive & Open World)
├── a11y_navigation.gd     # A* waypoint audio beacon, obstacle/cover proximity cues, safe Auto-Walk controller
├── a11y_aim_assist.gd     # Acoustic crosshair tone + LOS-validated visible enemy target lock
└── a11y_ui_helper.gd      # Reusable Control focus styling, NVDA focus/value/toggle/dropdown announcer hooks
```

### Key Integration Points

1. **`project.godot` & `addons/nvda_integration/NvdaWrapper.gd`**:
   - Strip SAPI fallback from `NvdaWrapper.gd` (`say()` routes exclusively to `say_nvda()`, `_init()` no longer initializes SAPI voices).
   - Register `NvdaWrapper` and `A11ySpeech` in `[autoload]` (with `A11ySpeech` initialized cleanly after `NvdaWrapper`).
2. **English Localization**:
   - Translate `MatchHUD`, `GameHUD`, `MatchManager`, `MatchRules`, `MatchArena`, `MatchBot`, `AnnouncerManager`, `Player`, `TouchControls`, `Progression`, `ArenaDefinition`, `resources/maps/*.tres`, `resources/weapons/shotgun.tres`, `project.godot` title.
3. **UI Focus & Screen Reader Narration**:
   - Enable `FOCUS_ALL` + visible high-contrast focus `StyleBoxFlat` on buttons/sliders/options.
   - Hook `A11yUIHelper` across `MatchHUD` and `GameHUD` for Main Menu, Settings (including Accessibility sub-section + optional Screen Filter selector), Match HUD readouts, and Results.
4. **In-Game Spatial Loop**:
   - `competitive_game.gd` and `game.gd` instantiate a lightweight `A11yGameplayController` (or wire `A11yRadar`, `A11yNavigation`, `A11ySpatialAudio`, `A11yAimAssist`) that hooks into `CombatInput`, `MatchManager.bus`, `WeaponSystem`, `Player`, and `CameraRig`.
   - Note: `A11yGameplayController` will NOT reference `City` or `Game` types directly (uses duck-typing / properties) so `test_lightweight_menu.gd` remains 100% clean!
