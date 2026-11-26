# Implementation Plan: Full Vehicle Save/Load Persistence & Smooth Natural Engine Audio

**Branch**: `007-vehicle-save-and-smooth-engine-audio` | **Date**: 2026-11-26 | **Spec**: [spec.md](file:///C:/Users/LCBoy/Desktop/data/godot%20game/GTA-mini/specs/007-vehicle-save-and-smooth-engine-audio/spec.md)

## Summary
Fix open-world vehicle disappearance across Save/Load by persisting every `Vehicle` and `Aircraft` (with deterministic `save_id`s, active occupancy, and post-exit `has_driver` AI gating) and keeping backward compatibility with legacy v1 saves. Simultaneously overhaul engine audio synthesis (`CityAudio.make_engine()`) and add inertial slew-rate-limited RPM/pitch smoothing in `CityAudio._tick_engine()` and `A11ySpatialAudio` so acceleration and deceleration sound smooth, gradual, and natural without "auto-tune" pitch stepping.

## Technical Context
- **Language/Version**: GDScript (Godot 4.7.2 `GL Compatibility`)
- **Primary Files**: `scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/game.gd`, `scripts/city_audio.gd`, `scripts/accessibility/a11y_spatial_audio.gd`
- **Testing**: Headless Godot test suites (`tests/test_save_and_audio.gd`, `tests/test_harbor_feel.gd`, `tests/test_game_integration.gd`, plus all `tests/test_*.gd`)
- **Constraints**: Preserve `Vehicle.profile()` invariants and `CityAudio.engine_pitch()` monotonicity + `stinger.data.size() < engine.data.size() * 6` in `tests/test_harbor_feel.gd`; keep `SaveManager.SCHEMA_VERSION = 1` backward-compatible; follow Godot 4.7 & audio-systems patterns.

## Constitution Check
- Follows SpecKit + ECC workflow: TDD Red -> Green -> Refactor, small single-purpose helpers (`to_save_dict`/`apply_save_dict`), zero duplicated serialization logic, `gdscript-reviewer` audit, full headless verification, and `GEMINI.md` project logging.

## Architecture & Changes

1. **Deterministic Vehicle & Aircraft Serialization (`scripts/vehicle.gd`, `scripts/aircraft.gd`, `scripts/game.gd`)**:
   - Add `save_id: String` and `throttle_input: float` to `Vehicle`, plus `_orig_mesh_mats: Dictionary` captured before `_char_vehicle_visuals()` so `repair()` restores original materials if a wrecked/exploded vehicle is reverted on load.
   - Add `Vehicle.to_save_dict()` / `Vehicle.apply_save_dict()` and `Aircraft.to_save_dict()` / `Aircraft.apply_save_dict()` to keep serialization encapsulated and avoid bloating `game.gd`.
   - Assign stable `save_id`s in `Game._ready()`, `_make_cop()`, and `_spawn_base_units()`.
   - Update `Game._exit_vehicle()` so `ai_enabled` is only restored when `v.has_driver` is `true` (stolen driverless cars remain parked).
   - Extend `Game.serialize_state()` and `Game.apply_saved_state()` to persist/restore `"vehicles"`, `"aircraft"`, `"active_vehicle_id"`, and `"active_aircraft_id"` while supporting legacy saves and dynamic `cop_dyn:*` spawn/cleanup.

2. **Warm Combustion Synth & Inertial Engine Pitch Smoothing (`scripts/city_audio.gd`, `scripts/accessibility/a11y_spatial_audio.gd`)**:
   - Upgrade `CityAudio.make_engine()` to a `6300`-sample (`12` cycles of `525` samples = `42 Hz`) seamless 4-stroke loop combining warm fundamental, cylinder harmonics, `0.5x`/`1.5x` sub-harmonic firing cadence, low-level periodic mechanical texture, and soft `tanh` saturation.
   - Refine `CityAudio.engine_pitch(speed, cap)` to a smooth concave curve across `0.74..1.48` (strictly monotonic).
   - Add inertial RPM & slew-rate-limited `pitch_scale` filtering (`_engine_rpm`, `_engine_pitch`, `_engine_gain`, `_engine_vehicle_id`) in `CityAudio._tick_engine(delta, vehicle)` driven by `vehicle.speed / cap` and `vehicle.throttle_input`.
   - Smooth 3D traffic slot `pitch_scale` and `_aircraft_player.pitch_scale` every frame in `A11ySpatialAudio.tick_world_audio()`.

3. **TDD Verification (`tests/test_save_and_audio.gd`)**:
   - Add RED tests for stolen car exit parking, full Save/Load round-trip of `PARKED`/`CIVILIAN`/`Aircraft`/active vehicle across fresh `main.tscn` instantiation, and gradual engine pitch slew-rate bounds under sudden acceleration/impact.
   - Implement GREEN fixes, run all `tests/test_*.gd`, run code review, update `GEMINI.md`, and rebuild Windows export if needed.
