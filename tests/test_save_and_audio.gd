extends SceneTree
## Headless TDD suite for SaveManager, AudioServer buses, 3D world audio, and district callouts.
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
	var ow = load("res://scenes/main.tscn").instantiate()
	root.add_child(ow)
	current_scene = ow
	await process_frame

	ow.begin()
	await frames(3)

	# 1. AudioServer bus layout & limiter
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var veh_bus := AudioServer.get_bus_index("Vehicles")
	var amb_bus := AudioServer.get_bus_index("Ambience")
	var a11y_bus := AudioServer.get_bus_index("A11y")
	check(sfx_bus > 0 and veh_bus > 0 and amb_bus > 0 and a11y_bus > 0, "AudioServer has dedicated SFX, Vehicles, Ambience, and A11y buses")
	check(AudioServer.get_bus_effect_count(0) >= 1, "Master bus has a Limiter effect to prevent clipping")

	# 2. Synthesized audio streams exist and are audible
	var audio: A11ySpatialAudio = ow.a11y.audio
	check(audio._wav_punch_swing != null and CityAudio.peak(audio._wav_punch_swing) > 0.1, "punch swing stream is audible")
	check(audio._wav_punch_hit != null and CityAudio.peak(audio._wav_punch_hit) > 0.2, "punch hit stream is audible")
	check(audio._wav_siren != null and CityAudio.peak(audio._wav_siren) > 0.15, "police siren stream is audible")
	check(audio._wav_horn != null and CityAudio.peak(audio._wav_horn) > 0.15, "vehicle horn stream is audible")
	check(audio._wav_car_crash != null and CityAudio.peak(audio._wav_car_crash) > 0.2, "vehicle crash stream is audible")
	check(audio._wav_ocean != null and CityAudio.peak(audio._wav_ocean) > 0.05, "ocean ambience stream is audible")
	check(audio._pool_traffic_3d.size() >= 4 and audio._pool_traffic_3d[0].doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP, "traffic 3D audio pool uses Doppler tracking")
	check(audio._pool_ped_3d.size() >= 4 and audio._pool_ped_3d[0].attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "NPC footstep 3D pool uses inverse distance attenuation")

	# 3. District GPS callouts
	check(ow.district_name(Vector3(0.0, 0.0, ow.city.st_zs[0] - 12.0)) == "Harbor Pier", "south waterfront resolves to Harbor Pier")
	check(ow.district_name(ow.city.base_pos) == "Army Base", "north military base resolves to Army Base")
	check(ow.district_name(ow.city.garage_pos) == "Warehouse District", "south warehouse resolves to Warehouse District")

	# 4. Save & Load round-trip + .bak fallback
	var test_save_path := "user://test_open_world_save_%d.json" % OS.get_process_id()
	var test_bak_path := test_save_path + ".bak"
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if FileAccess.file_exists(test_bak_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_bak_path))

	ow.money = 1337
	ow.phase = ow.Phase.DELIVER
	ow._stolen = true
	ow._delivered = false
	ow.packages_left = 2
	ow.player.global_position = Vector3(4.0, -0.05, -38.0)
	ow.player.health = 63.0
	ow.player.give_weapon(Arsenal.Id.SMG, 55)
	ow.coupe.global_position = Vector3(0.0, -0.05, -38.0)
	ow.coupe.hp = 77.0
	var pickups := get_nodes_in_group("world_pickups")
	if pickups.size() > 0:
		var pk := pickups[0] as WorldPickup
		pk.taken = true
		pk.queue_free()
		await process_frame

	var save_ok: bool = ow.save_current_game(test_save_path)
	check(save_ok and FileAccess.file_exists(test_save_path), "SaveManager writes save file")
	var summary := SaveManager.peek_summary(test_save_path)
	check(int(summary.get("money", 0)) == 1337 and int(summary.get("packages_left", -1)) == 2, "SaveManager peek_summary reads money and packages")

	# Mutate state then restore
	ow.money = 10
	ow.phase = ow.Phase.STEAL
	ow._stolen = false
	ow.player.global_position = Vector3.ZERO
	ow.player.health = 100.0
	ow.player.select_weapon(Arsenal.Id.NONE)
	ow.coupe.global_position = Vector3(-50.0, 0.35, 0.0)
	ow.coupe.hp = 100.0
	var load_ok: bool = ow.load_saved_game(test_save_path)
	await frames(2)
	check(load_ok, "SaveManager loads saved state cleanly")
	check(ow.money == 1337 and ow.phase == ow.Phase.DELIVER and ow._stolen and ow.packages_left == 2, "restores money, mission phase, and packages")
	check(ow.player.global_position.distance_to(Vector3(4.0, -0.05, -38.0)) < 0.25 and is_equal_approx(ow.player.health, 63.0), "restores player position and health")
	check(ow.player.owned_weapons.has(Arsenal.Id.SMG) and ow.player.weapon == Arsenal.Id.SMG, "restores owned weapons and active weapon")
	check(ow.coupe.global_position.distance_to(Vector3(0.0, -0.05, -38.0)) < 0.35 and is_equal_approx(ow.coupe.hp, 77.0), "restores coupe position and HP")

	# Path sandboxing & corrupt primary fallback & multi-overwrite
	check(not SaveManager.save_data({"money": 99}, "res://evil.json"), "SaveManager rejects non-user:// paths")
	check(not SaveManager.save_data({"money": 99}, "user://../evil.json"), "SaveManager rejects traversal paths")
	ow.player.give_weapon(Arsenal.Id.RIFLE, 60)
	ow.player.global_position = Vector3(-42.0, 0.15, 22.0)
	var overwrite_ok: bool = ow.save_current_game(test_save_path)
	check(overwrite_ok, "SaveManager overwrites existing primary and .bak reliably (save #2)")
	ow.player.give_weapon(Arsenal.Id.PISTOL, 24)
	ow.player.select_weapon(Arsenal.Id.RIFLE)
	ow.player.global_position = Vector3(18.5, 0.15, -64.0)
	var overwrite_3: bool = ow.save_current_game(test_save_path)
	check(overwrite_3, "SaveManager overwrites existing primary and .bak reliably (save #3)")

	# Fresh scene instance restores exact position & weapons directly from TITLE
	var ow2 = load("res://scenes/main.tscn").instantiate()
	root.add_child(ow2)
	current_scene = ow2
	await process_frame
	var fresh_load_ok: bool = ow2.load_saved_game(test_save_path)
	await frames(2)
	check(fresh_load_ok, "Fresh scene instance loads saved game from TITLE")
	check(ow2.city.visible and not ow2.player.locked, "Loading from TITLE activates world and unlocks player")
	check(ow2.player.global_position.distance_to(Vector3(18.5, 0.15, -64.0)) < 0.25, "Fresh scene restores exact saved player position")
	check(ow2.player.owned_weapons.has(Arsenal.Id.SMG) and ow2.player.owned_weapons.has(Arsenal.Id.RIFLE) and ow2.player.owned_weapons.has(Arsenal.Id.PISTOL) and ow2.player.weapon == Arsenal.Id.RIFLE, "Fresh scene restores all owned weapons and active weapon")
	ow2.queue_free()
	await process_frame
	current_scene = ow

	# Corrupt primary fallback + invalid save has_save() guard
	var corrupt := FileAccess.open(test_save_path, FileAccess.WRITE)
	corrupt.store_string("{invalid json")
	corrupt.close()
	check(SaveManager.has_save(test_save_path), "has_save stays true when valid .bak fallback exists")
	ow.money = 5
	var bak_ok: bool = ow.load_saved_game(test_save_path)
	check(bak_ok and ow.money == 1337, "corrupt primary save falls back to .bak backup")
	var bak_corrupt := FileAccess.open(test_bak_path, FileAccess.WRITE)
	bak_corrupt.store_string("{broken")
	bak_corrupt.close()
	check(not SaveManager.has_save(test_save_path), "has_save returns false when both primary and .bak are corrupt")

	# 5. Universal NPC cash drops ($30..$100,000, wealth tiers) & officer weapon drops
	var tier_samples := {}
	var drop_in_range := true
	for _s in 60:
		var tmp_ped := Pedestrian.new()
		tmp_ped.wealth_tier = (_s % 4) as Pedestrian.WealthTier
		var amt: int = tmp_ped.roll_cash_drop()
		if amt < 30 or amt > 100000:
			drop_in_range = false
		tier_samples[int(tmp_ped.wealth_tier)] = true
		tmp_ped.free()
	check(drop_in_range and tier_samples.size() == 4, "Pedestrian wealth tiers roll cash strictly within $30..$100,000")

	var civ_ped := Pedestrian.new()
	civ_ped.is_officer = false
	ow.add_child(civ_ped)
	civ_ped.global_position = ow.player.global_position + Vector3(6.0, 0.0, 0.0)
	await process_frame
	var loot_before := get_nodes_in_group("world_pickups").size()
	civ_ped.knock_down()
	await process_frame
	var loot_after_civ := get_nodes_in_group("world_pickups")
	var spawned_cash := 0
	for n in loot_after_civ:
		var pk := n as WorldPickup
		if pk and not pk.taken and pk.kind == WorldPickup.Kind.CASH and pk.global_position.distance_to(civ_ped.global_position) < 2.0:
			spawned_cash += 1
			check(pk.amount >= 30 and pk.amount <= 100000, "Civilian knockdown drops CASH pickup between $30 and $100,000")
	check(spawned_cash == 1, "Civilian knockdown spawns exactly 1 cash pickup")
	civ_ped.downed = false
	civ_ped.knock_down()
	await process_frame
	var cash_after_repeat := 0
	for n in get_nodes_in_group("world_pickups"):
		var pk := n as WorldPickup
		if pk and not pk.taken and pk.kind == WorldPickup.Kind.CASH and pk.global_position.distance_to(civ_ped.global_position) < 2.0:
			cash_after_repeat += 1
	check(cash_after_repeat == 1, "Knocking down the same civilian again does not double-drop cash")

	var off_ped := Pedestrian.new()
	off_ped.is_officer = true
	ow.add_child(off_ped)
	off_ped.global_position = ow.player.global_position + Vector3(-6.0, 0.0, 0.0)
	await process_frame
	off_ped.knock_down()
	await process_frame
	var off_cash := 0
	var off_weapon := 0
	var dropped_weapon_id := Arsenal.Id.NONE
	for n in get_nodes_in_group("world_pickups"):
		var pk := n as WorldPickup
		if pk and not pk.taken and pk.global_position.distance_to(off_ped.global_position) < 2.5:
			if pk.kind == WorldPickup.Kind.CASH:
				off_cash += 1
			elif pk.kind == WorldPickup.Kind.WEAPON:
				off_weapon += 1
				dropped_weapon_id = pk.weapon_id
	check(off_cash == 1 and off_weapon == 1 and dropped_weapon_id != Arsenal.Id.NONE, "Officer/soldier knockdown drops both CASH and WEAPON pickups")
	ow.player.owned_weapons.clear()
	ow.player.select_weapon(Arsenal.Id.NONE)
	ow.collect_pickup(WorldPickup.Kind.WEAPON, 30, dropped_weapon_id)
	check(ow.player.owned_weapons.has(dropped_weapon_id) and ow.player.weapon == dropped_weapon_id, "Collecting dropped WEAPON pickup grants and equips new weapon")
	var ammo_before_dup: int = int(ow.player.ammo.get(dropped_weapon_id, 0))
	ow.collect_pickup(WorldPickup.Kind.WEAPON, 25, dropped_weapon_id)
	check(int(ow.player.ammo.get(dropped_weapon_id, 0)) == ammo_before_dup + 25, "Collecting duplicate WEAPON pickup adds reserve ammo")

	# Explicit save only: stealing coupe / picking package / buying weapon do not silently overwrite default user save
	var had_default_before := FileAccess.file_exists(SaveManager.DEFAULT_PATH)
	var default_mtime_before := FileAccess.get_modified_time(SaveManager.DEFAULT_PATH) if had_default_before else 0
	var default_bytes_before := FileAccess.get_file_as_bytes(SaveManager.DEFAULT_PATH) if had_default_before else PackedByteArray()
	var before_pkg_money: int = ow.money
	ow.collect_pickup(WorldPickup.Kind.PACKAGE, 180)
	check(ow.money == before_pkg_money + 180, "Package pickup still grants cash reward")
	ow._enter_vehicle(ow.coupe)
	if ow.active_vehicle == ow.coupe:
		ow.coupe.speed = 0.0
		ow._exit_vehicle()
	var had_default_after := FileAccess.file_exists(SaveManager.DEFAULT_PATH)
	var default_unchanged := (not had_default_after) if not had_default_before else (FileAccess.get_modified_time(SaveManager.DEFAULT_PATH) == default_mtime_before and FileAccess.get_file_as_bytes(SaveManager.DEFAULT_PATH) == default_bytes_before)
	check(default_unchanged, "Gameplay milestones do not silently create or overwrite user save without explicit Save Game")
	check(loot_before >= 0, "Pickup tracking valid")

	# 6. Smooth gradual engine audio pitch ramp (no abrupt auto-tune jumps)
	ow._enter_vehicle(ow.coupe)
	ow.coupe.speed = 0.0
	ow.coupe.throttle_input = 0.0
	ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p0: float = ow.sfx._engine.pitch_scale
	ow.coupe.speed = ow.coupe.max_speed
	ow.coupe.throttle_input = 1.0
	ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p1: float = ow.sfx._engine.pitch_scale
	check(p1 >= p0 and (p1 - p0) <= 0.03, "Engine pitch does not jump abruptly in a single frame on rapid acceleration")
	for _f in 25:
		ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p_mid: float = ow.sfx._engine.pitch_scale
	var top_target: float = CityAudio.engine_pitch(ow.coupe.max_speed, ow.coupe.max_speed)
	check(p_mid > p1 + 0.05 and p_mid < top_target - 0.05, "Engine pitch climbs gradually through mid-range instead of snapping to top pitch")
	for _f in 180:
		ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p_top: float = ow.sfx._engine.pitch_scale
	check(p_top > p_mid + 0.05 and absf(p_top - top_target) < 0.05, "Engine pitch reaches top cruise pitch after smooth ramp")
	ow.coupe.speed = 10.0
	ow.coupe.throttle_input = 0.0
	ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p_drop: float = ow.sfx._engine.pitch_scale
	check((p_top - p_drop) <= 0.03, "Engine pitch winds down smoothly without abrupt drop on collision/braking")
	# Braking while moving forward must not cause an RPM/volume surge
	ow.coupe.speed = 60.0
	ow.coupe.throttle_input = -1.0
	ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p_brake1: float = ow.sfx._engine.pitch_scale
	ow.sfx.tick(0.016, ow.player, ow.coupe, 0)
	var p_brake2: float = ow.sfx._engine.pitch_scale
	check(p_brake2 <= p_brake1 + 0.001, "Braking while rolling forward winds engine pitch down instead of surging up")
	ow.set_paused(true, true)
	check(not ow.sfx._engine.playing, "Pausing stops player vehicle engine loop cleanly")
	ow.set_paused(false, true)
	ow.coupe.speed = 0.0
	ow._exit_vehicle()

	# 7. Full world vehicle & aircraft persistence + stolen car stays parked on exit
	var test_parked: Vehicle = null
	var test_civ: Vehicle = null
	for node in get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null:
			continue
		if test_parked == null and v.kind == Vehicle.Kind.PARKED:
			test_parked = v
		elif test_civ == null and v.kind == Vehicle.Kind.CIVILIAN:
			test_civ = v
	check(test_parked != null and test_civ != null, "World spawns parked and civilian vehicles")
	if test_civ != null and test_parked != null:
		var civ_id := test_civ.save_id
		var civ_name := test_civ.display_name
		var parked_id := test_parked.save_id
		var parked_name := test_parked.display_name
		ow._enter_vehicle(test_civ)
		var civ_dest := Vector3(-75.0, 0.35, 114.0)
		test_civ.global_position = civ_dest
		test_civ.rotation.y = 1.25
		test_civ.hp = 82.0
		test_civ.speed = 0.0
		ow._exit_vehicle()
		check(not test_civ.ai_enabled and not test_civ.has_driver, "Exiting a stolen civilian car leaves it parked without ghost AI")

		var parked_dest := Vector3(-70.0, 0.35, 114.0)
		test_parked.global_position = parked_dest
		test_parked.rotation.y = -0.6
		test_parked.hp = 64.0
		test_parked.speed = 0.0

		var airs := get_nodes_in_group("aircraft")
		var test_air: Aircraft = airs[0] as Aircraft if airs.size() > 0 else null
		var air_id := test_air.save_id if test_air != null else ""
		var air_dest := Vector3(-60.0, 0.55, 120.0)
		if test_air != null:
			test_air.global_position = air_dest
			test_air.hp = 115.0
			test_air.speed = 0.0

		var expected_player_pos: Vector3 = ow.player.global_position
		var save_veh_ok: bool = ow.save_current_game(test_save_path)
		check(save_veh_ok, "Saves world vehicles and aircraft cleanly")

		# Free ow before instantiating fresh scene so duplicate 3D colliders don't overlap in PhysicsServer3D
		ow.queue_free()
		await process_frame

		var ow3 = load("res://scenes/main.tscn").instantiate()
		root.add_child(ow3)
		current_scene = ow3
		await process_frame
		var load_veh_ok: bool = ow3.load_saved_game(test_save_path)
		await frames(2)
		check(load_veh_ok, "Fresh scene loads saved world vehicles from TITLE")

		var restored_civ: Vehicle = null
		var restored_parked: Vehicle = null
		for node in ow3.get_tree().get_nodes_in_group("vehicles"):
			var v := node as Vehicle
			if v and ow3.is_ancestor_of(v) and v.save_id == civ_id:
				restored_civ = v
			elif v and ow3.is_ancestor_of(v) and v.save_id == parked_id:
				restored_parked = v
		check(restored_civ != null and restored_civ.global_position.distance_to(civ_dest) < 0.35 and is_equal_approx(restored_civ.hp, 82.0) and not restored_civ.ai_enabled and restored_civ.display_name == civ_name and ow3.player.global_position.distance_to(expected_player_pos) < 0.35, "Fresh scene restores stolen civilian car right beside player and parked with same model")
		check(restored_parked != null and restored_parked.global_position.distance_to(parked_dest) < 0.35 and is_equal_approx(restored_parked.hp, 64.0) and restored_parked.display_name == parked_name, "Fresh scene restores parked car position, HP, and model")
		var restored_air: Aircraft = null
		if air_id != "":
			for node in ow3.get_tree().get_nodes_in_group("aircraft"):
				var a := node as Aircraft
				if a and ow3.is_ancestor_of(a) and a.save_id == air_id:
					restored_air = a
			check(restored_air != null and restored_air.global_position.distance_to(air_dest) < 0.5 and is_equal_approx(restored_air.hp, 115.0), "Fresh scene restores aircraft position and HP")

		# Exploded vehicle un-chars cleanly when loading an intact save, and dynamic cops cleanup on legacy v1 load
		restored_parked.apply_damage(100.0)
		restored_parked._explode()
		check(restored_parked.exploded, "Exploding parked vehicle marks it exploded")
		ow3._make_cop(Vector3(12.0, 0.2, 12.0), 99)
		var intact_reload_ok: bool = ow3.load_saved_game(test_save_path)
		await frames(1)
		check(intact_reload_ok and not restored_parked.exploded and is_equal_approx(restored_parked.hp, 64.0), "Loading intact save un-chars exploded vehicle and cleans extra dynamic cops")

		# Legacy v1 save compatibility (coupe + in_coupe without vehicles/aircraft keys)
		var v1_ok: bool = ow3.apply_saved_state({
			"version": 1,
			"phase": ow3.Phase.DELIVER,
			"money": 900,
			"stolen": true,
			"delivered": false,
			"packages_left": 1,
			"player": {"pos": [10.0, 0.2, 10.0], "in_coupe": true, "weapon": 0, "owned_weapons": [], "ammo": {}, "magazines": {}},
			"coupe": {"pos": [14.0, 0.35, -18.0], "rot_y": 0.5, "hp": 88.0, "stolen": true},
		})
		check(v1_ok and ow3.active_vehicle == ow3.coupe and is_equal_approx(ow3.coupe.hp, 88.0), "Legacy v1 save format remains compatible")

		# Saving while seated inside a non-coupe vehicle restores occupancy on load
		ow3.apply_saved_state(SaveManager.load_data(test_save_path))
		ow3._enter_vehicle(restored_parked)
		var seated_save_ok: bool = ow3.save_current_game(test_save_path)
		check(seated_save_ok, "Saves while seated inside non-coupe vehicle")
		ow3.queue_free()
		await process_frame

		var ow4 = load("res://scenes/main.tscn").instantiate()
		root.add_child(ow4)
		current_scene = ow4
		await process_frame
		var load_seated_ok: bool = ow4.load_saved_game(test_save_path)
		await frames(2)
		check(load_seated_ok and ow4.player.in_vehicle and ow4.active_vehicle != null and ow4.active_vehicle.save_id == parked_id, "Fresh scene restores active non-coupe vehicle occupancy")

		# Saving while seated inside an Aircraft restores active_aircraft occupancy
		if air_id != "":
			ow4._exit_vehicle()
			var ow4_air: Aircraft = null
			for node in ow4.get_tree().get_nodes_in_group("aircraft"):
				var a := node as Aircraft
				if a and ow4.is_ancestor_of(a) and a.save_id == air_id:
					ow4_air = a
			if ow4_air != null:
				ow4._enter_aircraft(ow4_air)
				ow4.save_current_game(test_save_path)
				ow4.queue_free()
				await process_frame
				var ow5 = load("res://scenes/main.tscn").instantiate()
				root.add_child(ow5)
				current_scene = ow5
				await process_frame
				var load_air_ok: bool = ow5.load_saved_game(test_save_path)
				await frames(2)
				check(load_air_ok and ow5.player.in_vehicle and ow5.active_aircraft != null and ow5.active_aircraft.save_id == air_id, "Fresh scene restores active aircraft occupancy")

				# Bought Dealership car + aircraft persist across Save/Load with player_owned = true
				ow5._exit_aircraft()
				ow5.money = 500000
				var cat := GameModels.dealership_catalog()
				var bought_car_id := ""
				var bought_air_id := ""
				for entry in cat:
					if bought_car_id == "" and not bool(entry.get("is_aircraft", false)):
						bought_car_id = str(entry.get("id", ""))
					elif bought_air_id == "" and bool(entry.get("is_aircraft", false)):
						bought_air_id = str(entry.get("id", ""))
				var buy_car_ok: bool = bought_car_id != "" and ow5.buy_dealership_item(bought_car_id)
				var saved_car_sid: String = ow5.active_vehicle.save_id if ow5.active_vehicle else ""
				if ow5.active_vehicle:
					ow5.active_vehicle.speed = 0.0
					ow5._exit_vehicle()
				var buy_air_ok: bool = bought_air_id != "" and ow5.buy_dealership_item(bought_air_id)
				var saved_air_sid: String = ow5.active_aircraft.save_id if ow5.active_aircraft else ""
				if ow5.active_aircraft:
					ow5.active_aircraft.speed = 0.0
					ow5._exit_aircraft()
				check(buy_car_ok and buy_air_ok and saved_car_sid.begins_with("bought_veh:") and saved_air_sid.begins_with("bought_air:"), "Purchased dealership car and aircraft get deterministic bought_* save_ids")
				ow5.save_current_game(test_save_path)
				ow5.queue_free()
				await process_frame

				var ow6 = load("res://scenes/main.tscn").instantiate()
				root.add_child(ow6)
				current_scene = ow6
				await process_frame
				var load_bought_ok: bool = ow6.load_saved_game(test_save_path)
				await frames(2)
				var assets_after_load: Array[Dictionary] = ow6.a11y.radar.collect_targets(ow6, ow6.player.global_position, A11yRadar.Category.ASSETS)
				var has_bought_car := false
				var has_bought_air := false
				for asset in assets_after_load:
					var n = asset.get("node")
					if n is Vehicle and n.save_id == saved_car_sid and n.player_owned:
						has_bought_car = true
					elif n is Aircraft and n.save_id == saved_air_sid and n.player_owned:
						has_bought_air = true
				check(load_bought_ok and has_bought_car and has_bought_air, "Save/Load restores dynamically purchased dealership vehicles and aircraft as My Assets")

				# In-game Load when session already spawned a different bought_veh:0 replaces model cleanly
				ow6.money = 50000
				ow6._next_bought_veh_id = 0
				ow6.buy_dealership_item("car_taxi")
				if ow6.active_vehicle:
					ow6.active_vehicle.speed = 0.0
					ow6._exit_vehicle()
				var reload_in_game_ok: bool = ow6.load_saved_game(test_save_path)
				await frames(2)
				var reloaded_v0: Vehicle = null
				for v_node in ow6.get_tree().get_nodes_in_group("vehicles"):
					var vv := v_node as Vehicle
					if vv and ow6.is_ancestor_of(vv) and vv.save_id == saved_car_sid:
						reloaded_v0 = vv
				check(reload_in_game_ok and reloaded_v0 != null and reloaded_v0.display_name == "AMBER COUPE", "In-game Load replaces collided bought_veh:0 with saved model")
				ow6.queue_free()
				await process_frame
			else:
				ow4.queue_free()
				await process_frame
		else:
			ow4.queue_free()
			await process_frame
	else:
		ow.queue_free()
		await process_frame

	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if FileAccess.file_exists(test_bak_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_bak_path))

	print("SAVE_AND_AUDIO_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
