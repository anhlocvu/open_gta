# Tasks: Open-World-Only Streamline

- [x] **T001**: Audit competitive dependencies and create SpecKit docs (`002-open-world-only`).
- [x] **T002**: Relocate `TacticalConfig` to `scripts/tactical_config.gd` and remove competitive scenes/scripts/assets/tests.
- [x] **T003**: Point `project.godot` to `res://scenes/main.tscn`, clean `game.gd` and `radar.gd`, and add Open World Settings persistence + Pause Menu.
- [x] **T004**: Upgrade `GameHUD` (`scripts/hud.gd`) with full Accessibility Settings, Key Bindings, Pause Menu, and English NVDA narration.
- [x] **T005**: Clean competitive branches out of `scripts/accessibility/*` and update `tests/test_accessibility.gd` + `tests/test_game_integration.gd`.
- [x] **T006**: Re-export `export/windows/OperationChaos.exe`, run all tests + `.exe` smoke test, and log in `GEMINI.md`.
- [x] **T007**: Add failing regression tests for `NVDA` ClassDB resolution, real `Input.parse_input_event` gameplay key dispatch across device IDs, and Menu/City performance budgets.
- [x] **T008**: Fix `NvdaWrapper.gd` and `A11ySpeech` to call `NVDA` ClassDB static APIs (removing broken `Engine.has_singleton("NVDA")` check), disable conflicting AccessKit driver (`accessibility_support=2`), and ensure crisp menu speech interruption.
- [x] **T009**: Fix `CombatInput.install()` (`device = -1` All Devices), unify action matching in `A11yGameplayController` & `A11yNavigation`, and release lingering UI focus on `show_start(false)` / `show_pause(false)`.
- [x] **T010**: Optimize Menu & City rendering/simulation (suspend 3D world rendering & actor physics during `Phase.TITLE` / `paused`, batch `_dashes()` with `MultiMeshInstance3D`, cache shared `City` materials, set `Sky.PROCESS_MODE_QUALITY`, disable default `msaa_3d` on LOW), verify all suites + FPS benchmark, rebuild `.exe`, and log in `GEMINI.md`.
