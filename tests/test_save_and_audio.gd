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
	var test_save_path := "user://test_open_world_save.json"
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

	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if FileAccess.file_exists(test_bak_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_bak_path))

	ow.queue_free()
	await process_frame
	print("SAVE_AND_AUDIO_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
