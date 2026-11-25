# Implementation Plan: Open-World-Only Streamline

**Branch**: `002-open-world-only` | **Date**: 2026-11-25 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/002-open-world-only/spec.md)

## Steps
1. Preserve `TacticalConfig` at `scripts/tactical_config.gd` and update `resources/tactical_default.tres`.
2. Delete competitive-only files (`competitive_main.tscn`, `scenes/maps/`, `scripts/modes/`, `scripts/ai/`, `scripts/network/`, `audio/announcer/`, competitive resources/tests).
3. Set `run/main_scene="res://scenes/main.tscn"` in `project.godot`.
4. Refactor `scripts/game.gd`, `scripts/hud.gd`, and `scripts/radar.gd` to be Open-World-only with Pause Menu, full Settings (including NVDA Accessibility & Key Bindings), and spoken shop/bar/crate/respray interactions.
5. Streamline `scripts/accessibility/*` (remove competitive `MatchManager`/`MatchRules` branches, refine Open World radar/aim-assist/audio) and update `tests/test_accessibility.gd` & `tests/test_game_integration.gd`.
6. Re-export `export/windows/OperationChaos.exe` + NVDA DLLs and smoke-test both headless tests and `.exe`.
