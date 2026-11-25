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

	# Path sandboxing & corrupt primary fallback
	check(not SaveManager.save_data({"money": 99}, "res://evil.json"), "SaveManager rejects non-user:// paths")
	check(not SaveManager.save_data({"money": 99}, "user://../evil.json"), "SaveManager rejects traversal paths")
	ow.save_current_game(test_save_path)
	var corrupt := FileAccess.open(test_save_path, FileAccess.WRITE)
	corrupt.store_string("{invalid json")
	corrupt.close()
	ow.money = 5
	var bak_ok: bool = ow.load_saved_game(test_save_path)
	check(bak_ok and ow.money == 1337, "corrupt primary save falls back to .bak backup")

	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if FileAccess.file_exists(test_bak_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_bak_path))

	ow.queue_free()
	await process_frame
	print("SAVE_AND_AUDIO_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
