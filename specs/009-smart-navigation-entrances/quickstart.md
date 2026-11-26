# Quickstart Validation Guide: Smart Entrance-Aware Navigation

## Prerequisites
- Godot `4.7.2` (`godot_console.exe`) available in environment/path (`tools/` or system PATH).

## Headless Automated Verification
Run all existing and new test suites:
```powershell
& "<godot_console>" --headless --path . --script tests/test_accessibility.gd
& "<godot_console>" --headless --path . --script tests/test_dealership_and_dev.gd
& "<godot_console>" --headless --path . --script tests/test_save_and_audio.gd
& "<godot_console>" --headless --path . --script tests/test_accessibility_speech.gd
& "<godot_console>" --headless --path . --script tests/test_combat.gd
& "<godot_console>" --headless --path . --script tests/test_cover.gd
& "<godot_console>" --headless --path . --script tests/test_game_integration.gd
& "<godot_console>" --headless --path . --script tests/test_harbor_feel.gd
& "<godot_console>" --headless --path . --script tests/test_stage_one.gd
```

## Key Scenarios Verified
1. **Dealership Escape (Auto-Walk)**: Player inside `Vehicle Dealership` targeting an outside vehicle parked behind (`-Z`) or beside (`±X`) the storefront exits cleanly through the south doorway and arrives at the vehicle.
2. **Pay and Spray Arrival (Auto-Drive)**: Vehicle driving from surrounding streets toward `Pay and Spray` enters `_spray` pad cleanly (`city.spray_contains(vehicle) == true`) and stops without hitting an overlapping wall or circling.
3. **Hospital -> Vehicle Dealership (Auto-Walk)**: Player starting at `city.hospital_pos` walks across the populated city to `city.dealership_pos` without snapping backward to passed intersections and arrives within `<= 2.4m`.
4. **Drive to Walk-In Storefront**: Auto-Drive targeting `Gun Shop` or `Vehicle Dealership` pulls up to the exterior apron/curb without ramming storefront walls.
5. **Circular Loop Recovery**: Artificially circling or blocked routes trigger net-progress loop recovery and rerouting.
