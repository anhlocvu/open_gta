# Feature Specification: End-to-End NVDA Accessibility & English Localization

**Feature Branch**: `001-nvda-accessibility-system`
**Created**: 2026-11-25
**Status**: Approved by User
**Input**: End-to-end NVDA-only accessibility, English localization, 3D spatial audio, compass/A* navigation, and aim assist across competitive and open-world modes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - NVDA-Only Speech Engine & Complete English Localization (Priority: P1)

A blind player launches the game on Windows with NVDA running. Every menu, setting, HUD element, announcer subtitle, and gameplay prompt is displayed in English and spoken exclusively through NVDA (never falling back to Windows SAPI / `DisplayServer.tts_speak`).

**Independent Test**: Run `A11ySpeech` in headless tests with simulated NVDA availability/unavailability and verify zero calls to `DisplayServer.tts_speak`, working priority/interrupt/queue semantics, deduplication, and 30-entry speech history navigation.

**Acceptance Scenarios**:

1. **Given** NVDA is running (or mocked via speech backend interface), **When** the game starts or announces text, **Then** speech is sent exclusively to NVDA without invoking SAPI TTS.
2. **Given** NVDA is NOT running, **When** `A11ySpeech.speak()` is called, **Then** it records to speech history and skips SAPI fallback cleanly without errors.
3. **Given** any screen (Main Menu, Settings, Match HUD, Results, Open World HUD), **When** text is rendered or spoken, **Then** all user-facing strings are in English.

---

### User Story 2 - Full Keyboard & NVDA Menu, Settings, and HUD Accessibility (Priority: P1)

A blind player navigates the Main Menu, team/weapon selectors, Settings (including Accessibility Settings and Key Rebinding), Match HUD, and Results screen using only the keyboard, hearing Name, Role, State, and Value via NVDA.

**Independent Test**: Instantiate `competitive_main.tscn` and `main.tscn` in headless tests, verify every interactive control has `focus_mode != FOCUS_NONE`, initial focus is grabbed on screen transitions, and focus/value changes trigger English NVDA announcements.

**Acceptance Scenarios**:

1. **Given** the Main Menu opens, **When** the scene initializes or returns from a match, **Then** the first primary control receives focus and NVDA announces the screen title and focused item.
2. **Given** the player navigates Settings sliders, toggles, dropdowns, and keybind buttons with Tab/Arrows/Enter, **When** focus or values change, **Then** NVDA announces the label, control role, and exact updated value/state.
3. **Given** the player is in-game (Competitive or Open World), **When** pressing Status (`Z`), Objective (`X`), History (`[` / `]` / `\`), or Help (`/`), **Then** NVDA speaks up-to-date English gameplay state without altering game rules.

---

### User Story 3 - 3D Orientation, Compass, Relative Radar, A* Beacon & Auto-Walk (Priority: P2)

A blind player orients, explores, navigates obstacles, and completes objectives in both Competitive (`Protege o Corre!`, `Favela Royale`) and Open World (`main.tscn`) modes using keyboard turning, compass headings, relative radar scanning, A* audio beacons, and safe Auto-Walk.

**Independent Test**: Verify compass heading strings, relative clock/left-right bearing math, A* route waypoint progression, obstacle proximity queries, and Auto-Walk engagement/cancellation in headless tests.

**Acceptance Scenarios**:

1. **Given** the player presses keyboard turn keys (`J`/`L`) or `K` to level horizon, **When** Snap Turn or Smooth Turn is active, **Then** camera yaw updates and NVDA announces the new compass heading.
2. **Given** the player cycles radar categories (`B`) and targets (`,` / `.`), **When** targets exist in the arena or open world, **Then** NVDA speaks target name, distance in meters, and player-relative direction (e.g., "ahead left", "behind right").
3. **Given** the player activates the Audio Beacon (`M`) or Auto-Walk (`P`), **When** a valid target exists, **Then** 3D waypoint pings follow `MatchArena.route()` (or open-world road/target vector) and Auto-Walk cancels immediately on manual movement, menu entry, death, or arrival.

---

### User Story 4 - 3D Spatial Audio & Accessible Combat (Priority: P2)

A blind player perceives gunfire, enemy footsteps, hits, armor breaks, reloads, safe-zone warnings, and can acquire visible targets using an acoustic crosshair and LOS-validated Aim Assist.

**Independent Test**: Verify `A11ySpatialAudio` pools `AudioStreamPlayer3D` nodes with `ATTENUATION_INVERSE_DISTANCE`, plays combat/weapon/zone cues without node leaks, and LOS Aim Assist only locks enemies with unobstructed line-of-sight.

**Acceptance Scenarios**:

1. **Given** bots or players fire weapons or walk nearby, **When** events occur in 3D space, **Then** `A11ySpatialAudio` emits 3D attenuated gunfire and footstep cues at the actor's position.
2. **Given** the player sweeps their aim or presses Snap Aim (`U`), **When** an enemy is within unobstructed line-of-sight, **Then** the acoustic crosshair pings and Snap Aim aligns yaw/pitch to the visible enemy without shooting through walls.
3. **Given** the player hits, breaks armor, gets a headshot, takes damage, reloads, or runs dry, **When** the event fires, **Then** distinct audio cues and high-priority NVDA announcements (including attacker relative direction) inform the player.

---

### Edge Cases

- NVDA is not running or `NVDA` GDExtension singleton is absent in headless CI: speech must not crash or fall back to SAPI.
- `Insert` and `CapsLock` are reserved as NVDA modifier keys: zero game or accessibility actions may bind to them.
- `gato_screen_filters` defaults to `F6`, conflicting with `graphics_profile`: screen filter hotkey must not steal `F6` (only controllable from Settings or a non-conflicting key if enabled).
- Returning to menu or restarting a match mid-Auto-Walk or mid-speech: Auto-Walk clears immediately, spatial audio stops cleanly, and stale combat speech is cancelled.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST route all screen-reader speech strictly through NVDA (`NVDA.speak_text` / `NVDA.cancel`) and MUST NEVER call `DisplayServer.tts_speak` or SAPI TTS.
- **FR-002**: System MUST translate all visible UI, HUD, announcer subtitles, weapon labels, objective labels, and open-world prompts to English.
- **FR-003**: System MUST enable keyboard focus (`FOCUS_ALL`) and NVDA focus/value announcements across every menu, setting, and result screen in both `competitive_main.tscn` and `main.tscn`.
- **FR-004**: System MUST provide configurable Accessibility Settings persisted in `user://competitive_settings.cfg` (NVDA speech toggle, combat verbosity, cue volume, Snap Turn mode/angle, LOS Aim Assist, acoustic crosshair, Auto-Walk/beacon preferences, screen filter).
- **FR-005**: System MUST provide non-conflicting single-key accessibility bindings (excluding `Insert`, `CapsLock`, `F1-F12`, and `Alt+Space`) registered in `InputMap` and rebindable in Settings.
- **FR-006**: System MUST provide 3D spatialized audio cues (`AudioStreamPlayer3D` with inverse-distance attenuation) for gunfire, footsteps, impacts, hits, armor breaks, reloads, empty clicks, safe-zone alerts, and navigation beacons.
- **FR-007**: System MUST provide relative radar scanning, A*-guided waypoint beacons (`MatchArena.route()`), obstacle/cover proximity cues, and safely cancellable Auto-Walk for both Competitive and Open World modes.
- **FR-008**: System MUST provide LOS-validated Aim Assist and acoustic crosshair feedback without bypassing walls or gameplay rules.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of automated accessibility unit/integration tests pass headlessly with 0 calls to SAPI TTS.
- **SC-002**: 100% of interactive controls in `MatchHUD` and `GameHUD` are reachable via keyboard focus and emit NVDA speech descriptions.
- **SC-003**: Existing gameplay test suites (`test_stage_one.gd`, `test_combat.gd`, `test_cover.gd`, `test_lightweight_menu.gd`, `test_map_navigation.gd`, `test_modes_integration.gd`, `test_game_integration.gd`) pass with zero regressions caused by accessibility changes.
- **SC-004**: Zero bindings conflict with `Insert`, `CapsLock`, or existing `CombatInput` actions.
