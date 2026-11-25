# Tasks: Reliable Save/Load, Weapon Switch Speech & Loot Drops

- [x] T001 Write failing TDD tests in `tests/test_save_and_audio.gd` and `tests/test_accessibility.gd` for explicit save-only behavior, multi-overwrite Windows save/load position+weapon restoration, weapon switch speech (`No weapons` + weapon names), and NPC cash/officer weapon drops (RED)
- [x] T002 Fix `SaveManager` (`has_save`, safe `.bak`/overwrite atomic write) and `Game`/`GameHUD` (remove silent auto-saves, clean `begin_saved()`/`load_saved_game()` position+weapon restore & speech)
- [x] T003 Add immediate NVDA weapon switch announcements (`announce_weapon_switch`) in `A11yGameplayController` and wire into `Game`
- [x] T004 Implement `WealthTier` cash drops (`$30`–`$100,000`) and officer/soldier weapon drops across `Pedestrian`, `WorldPickup`, `Game`, `A11ySpatialAudio`, and `A11yRadar`
- [x] T005 Run all headless test suites (`tests/*.gd`), review changes, rebuild `export/windows/OperationChaos.exe`, and record session log in `GEMINI.md`
