# Tasks: End-to-End NVDA Accessibility & English Localization

- [x] **T001**: Remove SAPI fallback from `addons/nvda_integration/NvdaWrapper.gd`, register `NvdaWrapper` & `A11ySpeech` autoloads in `project.godot`, implement `scripts/accessibility/a11y_speech.gd` & `scripts/accessibility/a11y_settings.gd`.
- [x] **T002**: Write `tests/test_accessibility_speech.gd` (TDD) verifying NVDA-only routing (no SAPI calls), queue/interrupt priority, dedup, and speech history navigation.
- [x] **T003**: Localize all Portuguese strings across `scripts/`, `resources/`, and `project.godot` to English.
- [x] **T004**: Implement `scripts/accessibility/a11y_ui_helper.gd` and wire full keyboard focus + NVDA narration + Accessibility Settings into `MatchHUD` and `GameHUD`.
- [x] **T005**: Register non-conflicting accessibility `InputMap` actions in `scripts/combat_input.gd` (avoiding `Insert`, `CapsLock`, `F1-F12`).
- [x] **T006**: Implement `scripts/accessibility/a11y_radar.gd` and `scripts/accessibility/a11y_navigation.gd` (keyboard turn/snap-turn, compass, relative radar scanner, A* audio beacon, obstacle/cover cues, Auto-Walk).
- [x] **T007**: Implement `scripts/accessibility/a11y_spatial_audio.gd` and `scripts/accessibility/a11y_aim_assist.gd` (3D gunfire/footsteps/hit/armor/zone cues, acoustic crosshair, LOS aim assist).
- [x] **T008**: Wire `A11yGameplayController` into both `competitive_game.gd` and `game.gd` + `MatchManager` + `WeaponSystem` + `AnnouncerManager`.
- [x] **T009**: Add integration tests (`tests/test_accessibility.gd`), run all existing & new tests, perform ECC code review, and log work in `GEMINI.md`.
