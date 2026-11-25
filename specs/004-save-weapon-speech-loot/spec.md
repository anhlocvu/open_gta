# Feature Specification: Reliable Save/Load, Weapon Switch Speech & Loot Drops

**Feature Branch**: `004-save-weapon-speech-loot`
**Created**: 2026-11-26
**Status**: Approved by User
**Input**: Remove unexpected silent auto-saves so `CONTINUE GAME` only appears after an explicit save; fix Windows save overwrite & state restoration (player position, owned weapons, active weapon, ammo/magazines); speak weapon name or `"No weapons"` immediately on weapon cycling/selection; drop randomized cash ($30–$100,000 across wealth tiers) when knocking down any NPC (civilians, police, base soldiers), plus drop weapons when knocking down police or soldiers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Explicit Save/Load & Reliable Position/Weapon Restoration (Priority: P1)
Starting a new game and ending the session without pressing `SAVE GAME` must not silently create a save file or show `CONTINUE GAME` on the next launch. When the player explicitly saves (`Pause -> SAVE GAME`), exits, re-opens the game, and presses `CONTINUE GAME` (or `LOAD SAVED GAME`), the game restores their exact saved world position, cash, mission state, owned weapons, active equipped weapon, and magazine/reserve ammo reliably across repeated overwrites on Windows.

**Independent Test**: Headless test plays without saving, verifies `SaveManager.has_save()` remains false; then equips weapons, moves to a custom location, saves 3+ consecutive times (verifying Windows `.json` + `.bak` overwrite succeeds every time), resets/reinstantiates the scene, calls `begin_saved()`, and asserts exact player position, `owned_weapons`, active `weapon`, `ammo`, and `magazines` are restored.

### User Story 2 - Immediate NVDA Speech on Weapon Switching (Priority: P1)
Pressing weapon cycling (`-`, `=`, Mouse Wheel), holster (`0`), or weapon slot keys (`1`, `2`, `3`, `5` outside the gun shop) immediately announces the newly equipped weapon name and ammo count via NVDA (`force = true`, `interrupt = true`). If the player has no weapons at all, pressing weapon cycle/holster/slot keys announces `"No weapons."` instead of remaining silent.

**Independent Test**: Headless test spies on `A11ySpeech.spoken`, presses `cycle_weapon_up` / `cycle_weapon_down` / `weapon_holster` with zero owned weapons and verifies `"No weapons"` is spoken every press; then gives weapons and verifies cycling/selecting announces each weapon name and `"Unarmed, fists"` cleanly without duplicate callouts.

### User Story 3 - Universal Loot Drops ($30–$100,000) & Police/Soldier Weapon Drops (Priority: P1)
Knocking down any NPC—whether a civilian pedestrian, patrol officer, or Army Base soldier—drops a cash pickup (`WorldPickup.Kind.CASH`) valued between `$30` and `$100,000` using weighted wealth tiers (`Poor`, `Middle`, `Wealthy`, `Rich`), once per NPC (`cash_dropped` guard). Knocking down a police officer or Army Base soldier (`is_officer == true`) additionally drops a weapon pickup (`WorldPickup.Kind.WEAPON`) so the player gains weapons and ammo from defeating armed personnel. Dropped pickups emit 3D audio cues, NVDA announcements, and appear in `A11yRadar` (`Pickups` category) with cash/weapon details.

**Independent Test**: Headless test verifies civilian knockdowns spawn `WorldPickup.Kind.CASH` within `[30, 100000]` across wealth tiers and do not double-drop when knocked down again; officer knockdowns spawn both `Kind.CASH` and `Kind.WEAPON`; collecting `Kind.WEAPON` grants new weapons or adds ammo without overriding an unrelated active gun when already owned.

## Functional Requirements

- **FR-001**: Remove silent auto-saves from `Game` (`return_to_main_menu`, `_enter_vehicle`, `_buy_weapon`, `_update_mission`, `collect_pickup`) so `user://open_world_save.json` is written only when `save_current_game()` is explicitly invoked.
- **FR-002**: `SaveManager.has_save()` MUST verify a valid readable save (`not peek_summary().is_empty()`), and `SaveManager.save_data()` MUST reliably overwrite existing `.json` and `.bak` files on Windows with temp-file validation and error feedback if saving fails.
- **FR-003**: `Game.begin_saved()` and `Game.load_saved_game()` MUST restore `player.global_position`, `owned_weapons`, `weapon`, `ammo`, `magazines`, and vehicle/mission state without overwriting the load announcement with `"Free Chaos started..."` or `"Resumed."`.
- **FR-004**: `A11yGameplayController.announce_weapon_switch()` MUST speak `"No weapons."` when `owned_weapons` is empty, `"Unarmed, fists."` when holstered with owned weapons, or `"<Weapon>, <mag> in mag, <reserve> reserve."` on every weapon switch key press (`force = true`).
- **FR-005**: `Pedestrian` MUST assign a wealth tier (`POOR`: `$30–$350`, `MIDDLE`: `$400–$3,500`, `WEALTHY`: `$4,000–$25,000`, `RICH`: `$30,000–$100,000`) and trigger a one-time cash drop (`WorldPickup.Kind.CASH`) when knocked down, for both civilians and officers/soldiers.
- **FR-006**: When `Pedestrian.is_officer == true` is knocked down, `Game` MUST also spawn a `WorldPickup.Kind.WEAPON` pickup (`PISTOL`, `SMG`, `RIFLE`, or `SHOTGUN`) alongside the cash drop.
