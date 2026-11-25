# Feature Specification: Open-World-Only Streamline (Operation Chaos)

**Feature Branch**: `002-open-world-only`
**Created**: 2026-11-25
**Status**: Approved by User
**Input**: Remove competitive modes (`Protege o Corre`, `Favela Royale`, bots, LAN, announcer) and keep only the GTA-style Open World (`scenes/main.tscn`) with full NVDA accessibility, Settings, Pause Menu, and Windows `.exe` export.

## User Scenarios & Testing

1. **Direct Open World Launch**: Launching the project or `OperationChaos.exe` opens `scenes/main.tscn` directly into the Open World Main Menu with NVDA speech and keyboard navigation.
2. **Pause & Settings in Open World**: Pressing `Tab` or `Esc` during gameplay opens a Pause Menu (`Resume`, `Settings`, `Main Menu`, `Quit`) and full `Settings` (Graphics, Camera, Audio, Accessibility NVDA/3D options, Visual Screen Filters, Key Bindings) persisted in `user://open_world_settings.cfg`.
3. **Clean Repository**: Competitive scenes, `scripts/modes/`, `scripts/ai/`, `scripts/network/`, `audio/announcer/`, and competitive-only resources/tests are removed cleanly without breaking `Player`, `TacticalConfig`, or Open World integration tests.
