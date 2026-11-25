# Tasks: Keyboard Parity, 3D World Audio, Save/Load & Radar Polish

- [x] T001 Write/extend failing tests first in `tests/test_accessibility.gd`, `tests/test_combat.gd`, and `tests/test_save_and_audio.gd` (TDD RED)
- [x] T002 Update `CombatInput`, `project.godot`, and `A11yUIHelper.action_pressed()` for keyboard parity (`;`, `'`, `-`, `=`, `0`, `Shift+B`, `G`) and exact modifier matching
- [x] T003 Update `Player` and `Game` for GTA-style Fire-to-Punch when unarmed, weapon cycling including `NONE`, and `0` holster
- [x] T004 Update `A11yRadar`, `A11yAimAssist`, `A11yGameplayController`, and `Radar` for `Civilians` filter, city-wide nearest `Enemies and Police`, `B`/`Shift+B` cycling, and visual radar target sync
- [x] T005 Upgrade `A11ySpatialAudio` and `CityAudio` with AudioBuses + Limiter, punch/impact/movement/UI cues, 3D NPC footsteps/reactions, 3D Doppler vehicle engines/sirens/horns/crashes/doors, aircraft engine, and 3D Harbor zone ambience + Sonar sweep
- [x] T006 Wire audio events into `Game`, `Player`, `Pedestrian`, `Vehicle`, `Aircraft`
- [x] T007 Implement `SaveManager` (`user://open_world_save.json` + `.bak`), `Game` serialize/deserialize + milestone autosaves, and `GameHUD` menu updates (remove Day/Night buttons, add Continue/New/Save/Load + district GPS label)
- [x] T008 Run full headless test suite (0 failures), perform code review pass, export Windows release `.exe`, and log to `GEMINI.md`
