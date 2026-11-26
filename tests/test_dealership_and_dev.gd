extends SceneTree
## Headless TDD suite for DevMode (anhloc.env), F1 Dev Panel, and Vehicle Dealership.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + msg)
	else:
		failures += 1
		push_error("FAIL: " + msg)

func frames(n: int) -> void:
	for _i in n:
		await physics_frame
		await process_frame

func run() -> void:
	CombatInput.install()

	# 1. DevMode anhloc.env verification
	var tmp_ok := "user://test_anhloc_ok_%d.env" % OS.get_process_id()
	var tmp_kv := "user://test_anhloc_kv_%d.env" % OS.get_process_id()
	var tmp_bad := "user://test_anhloc_bad_%d.env" % OS.get_process_id()
	var f1 := FileAccess.open(tmp_ok, FileAccess.WRITE)
	f1.store_string("  lll20042004 \n")
	f1.close()
	var f2 := FileAccess.open(tmp_kv, FileAccess.WRITE)
	f2.store_string("# dev secret\nDEV_CODE=lll20042004\n")
	f2.close()
	var f3 := FileAccess.open(tmp_bad, FileAccess.WRITE)
	f3.store_string("wrong_code\n")
	f3.close()
	check(DevMode.verify_env_file(tmp_ok), "DevMode accepts anhloc.env with bare lll20042004")
	check(DevMode.verify_env_file(tmp_kv), "DevMode accepts anhloc.env with DEV_CODE=lll20042004")
	check(not DevMode.verify_env_file(tmp_bad), "DevMode rejects anhloc.env with wrong code")
	check(not DevMode.verify_env_file("user://nonexistent_anhloc_%d.env" % OS.get_process_id()), "DevMode rejects missing anhloc.env")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_ok))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_kv))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_bad))

	# 2. Dealership catalog completeness
	var catalog := GameModels.dealership_catalog()
	var seen_paths := {}
	var seen_ids := {}
	var unique_ids := true
	var has_coupe := false
	var has_cop := false
	var has_jeep := false
	var aircraft_count := 0
	for item in catalog:
		var iid := str(item.get("id", ""))
		if seen_ids.has(iid):
			unique_ids = false
		seen_ids[iid] = true
		if bool(item.get("is_aircraft", false)):
			aircraft_count += 1
		else:
			seen_paths[str(item.get("path", ""))] = true
			if iid == "coupe":
				has_coupe = true
			elif iid == "cop":
				has_cop = true
			elif iid == "military_jeep":
				has_jeep = true
	var missing_car := false
	for row in GameModels.CIV_CARS:
		if not seen_paths.has(str(row[0])):
			missing_car = true
	for row in GameModels.PARKED_CARS:
		if not seen_paths.has(str(row[0])):
			missing_car = true
	check(unique_ids and has_coupe and has_cop and has_jeep and not missing_car and aircraft_count >= 2, "Dealership catalog has unique IDs and includes all cars, special units, and aircraft")
	var cab_item := GameModels.dealership_item("car_taxi")
	var real_taxi_item := GameModels.dealership_item("car_real_taxi")
	check(str(cab_item.get("name", "")) == "CAB" and int(cab_item.get("price", 0)) == 1200 and str(real_taxi_item.get("name", "")) == "TAXI" and int(real_taxi_item.get("price", 0)) == 1400, "CAB and TAXI resolve to distinct catalog entries and prices")

	# 3. Gameplay integration: F1 Dev Panel gating + cheats + Enter Dealership purchase
	var ow = load("res://scenes/main.tscn").instantiate()
	root.add_child(ow)
	current_scene = ow
	await process_frame
	ow.begin()
	await frames(2)

	# Locked when dev_unlocked is false
	ow.dev_unlocked = false
	var f1_ev := InputEventKey.new()
	f1_ev.physical_keycode = KEY_F1
	f1_ev.keycode = KEY_F1
	f1_ev.pressed = true
	ow._unhandled_input(f1_ev)
	check(ow.hud._dev_panel == null or not ow.hud._dev_panel.visible, "F1 does not open Dev Panel when dev_unlocked is false")

	# Unlocked: F1 opens Dev Panel, applies Infinite Money, Infinite Ammo, Clear Wanted
	ow.dev_unlocked = true
	ow._unhandled_input(f1_ev)
	await process_frame
	check(ow.hud._dev_panel != null and ow.hud._dev_panel.visible and ow.paused, "F1 opens Dev Panel and pauses gameplay when dev_unlocked is true")
	ow.heat.report("shoot_cop", true)
	check(ow.heat.stars > 0, "Wanted stars raised before dev clear")
	ow.dev_grant_infinite_money()
	check(ow.dev_infinite_money and ow.money >= 999999999, "Dev Infinite Money grants $999,999,999")
	ow.dev_toggle_infinite_ammo(true)
	check(ow.player.infinite_ammo and ow.player.owned_weapons.size() >= 4, "Dev Infinite Ammo enables unlimited ammo and grants weapons")
	var mag_before: int = ow.player.magazines[ow.player.weapon]
	ow.dev_clear_wanted()
	check(ow.heat.stars == 0 and ow.heat.heat == 0.0, "Dev Clear Wanted zeroes stars and heat")
	ow._unhandled_input(f1_ev)
	await process_frame
	check(not ow.hud._dev_panel.visible and not ow.paused, "Pressing F1 again closes Dev Panel and resumes gameplay")
	ow.player._fire_cd = 0.0
	var shot: Dictionary = ow.player.spend_shot()
	check(not shot.is_empty() and ow.player.magazines[ow.player.weapon] == mag_before, "Infinite Ammo does not deplete magazine on shot")

	# 4. Dealership Enter trigger, outside spawn, and instant seating
	ow.dev_infinite_money = false
	ow.money = 100
	ow.player.global_position = ow.city.dealership_pos
	ow.player.velocity = Vector3.ZERO
	await frames(2)
	var enter_ev := InputEventKey.new()
	enter_ev.physical_keycode = KEY_ENTER
	enter_ev.keycode = KEY_ENTER
	enter_ev.pressed = true
	ow._unhandled_input(enter_ev)
	await process_frame
	check(ow.hud._dealer_panel != null and ow.hud._dealer_panel.visible and ow.paused, "Pressing Enter near Vehicle Dealership opens accessible menu")

	# Speech repeat/history keys (\) remain active inside Dealership modal
	var repeat_ev := InputEventKey.new()
	repeat_ev.physical_keycode = KEY_BACKSLASH
	repeat_ev.keycode = KEY_BACKSLASH
	repeat_ev.pressed = true
	check(ow.a11y.handle_input(repeat_ev), "Repeat-last NVDA speech key works while Dealership modal is open")

	# Insufficient funds keeps menu open
	var first_car_id := ""
	var first_car_price := 0
	var first_air_id := ""
	var first_air_price := 0
	for item in catalog:
		if first_car_id == "" and not bool(item.get("is_aircraft", false)):
			first_car_id = str(item.id)
			first_car_price = int(item.price)
		elif first_air_id == "" and bool(item.get("is_aircraft", false)):
			first_air_id = str(item.id)
			first_air_price = int(item.price)
	check(not ow.buy_dealership_item(first_car_id), "Dealership rejects purchase when money is insufficient")

	# Sufficient funds buys car, spawns outside dealership, and seats player immediately
	ow.money = first_car_price + first_air_price + 5000
	var money_before: int = ow.money
	var car_bought: bool = ow.buy_dealership_item(first_car_id)
	await frames(2)
	check(car_bought and ow.money == money_before - first_car_price, "Buying dealership car deducts price")
	check(ow.player.in_vehicle and ow.active_vehicle != null and ow.active_vehicle.player_owned, "Buying dealership car spawns it outside and seats player immediately")
	check(ow.active_vehicle.global_position.distance_to(ow.city.dealership_spawn_pos) < 18.0 and not ow.hud._dealer_panel.visible, "Bought car spawns at dealership exterior lane and closes menu")
	ow.active_vehicle.speed = 0.0
	ow._exit_vehicle()

	# Buying aircraft spawns AN-2 outside and seats player immediately
	ow.player.global_position = ow.city.dealership_pos
	var air_bought: bool = ow.buy_dealership_item(first_air_id)
	await frames(2)
	check(air_bought and ow.player.in_vehicle and ow.active_aircraft != null and ow.active_aircraft.player_owned, "Buying dealership aircraft spawns AN-2 outside and seats player immediately")
	ow.active_aircraft.speed = 0.0
	ow._exit_aircraft()

	ow.queue_free()
	await process_frame
	print("DEALERSHIP_AND_DEV_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
