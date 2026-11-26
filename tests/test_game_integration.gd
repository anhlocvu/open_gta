extends SceneTree
## Exercises the shipped scene and existing systems, without synthetic replacements.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.city != null and game.roads.nodes.size() > 0, "main scene creates city and roads")
	check(game.phase == game.Phase.TITLE and game.player.locked, "title keeps player locked")
	check(game.clock.quality == GraphicsProfile.Quality.LOW, "game starts in LOW")
	game.begin()
	check(game.phase == game.Phase.STEAL and not game.player.locked, "existing mission begins")
	for _i in 90:
		await physics_frame
		await process_frame
		if game.player.is_on_floor():
			break
	check(game.player.is_on_floor(), "real game spawn settles before jump")
	var start_y: float = game.player.global_position.y
	var jump := InputEventKey.new()
	jump.keycode = KEY_SPACE
	jump.pressed = true
	game._unhandled_input(jump)
	var peak_y := start_y
	# Physics frames may be batched during the expensive procedural startup.
	# Observe the peak rather than one arbitrary render frame after landing.
	for _i in 45:
		await physics_frame
		peak_y = maxf(peak_y, game.player.global_position.y)
	check(peak_y > start_y + 0.2, "Space input jumps in real game")
	game._enter_vehicle(game.coupe)
	check(game.player.in_vehicle and game.camera.vehicle_mode, "existing car entry works")
	check(game.phase == game.Phase.HEAT and game.heat.stars > 0, "car theft starts police response")
	game.coupe.speed = 0.0
	game._exit_vehicle()
	check(not game.player.in_vehicle and not game.camera.vehicle_mode, "existing car exit works")
	game.clock.set_quality(GraphicsProfile.Quality.MEDIUM)
	game.clock.toggle()
	var advanced := RenderingServer.get_current_rendering_method() == "forward_plus"
	check(game.clock._env.ssao_enabled == advanced and not game.clock._env.sdfgi_enabled, "day/night preserves supported MEDIUM profile")
	game.player.give_weapon(Arsenal.Id.PISTOL, 3)
	var ammo_before: int = game.player.magazines[Arsenal.Id.PISTOL]
	game.player.locked = false
	var shot: Dictionary = game.player.spend_shot()
	check(not shot.is_empty() and game.player.magazines[Arsenal.Id.PISTOL] == ammo_before - 1, "weapon spends magazine ammunition")

	# F key fires when armed (open air + facing vehicle at horizon pitch) and punches when unarmed
	await physics_frame
	game.player.global_position = Vector3(0.0, 0.25, 0.0)
	game.player.force_update_transform()
	game.player.velocity = Vector3.ZERO
	game.player._fire_cd = 0.0
	game.camera.yaw = 0.0
	game.camera.pitch = 0.45
	game.player.rotation.y = 0.0
	for _i in 4:
		await physics_frame
		await process_frame
	var mag_before_f: int = game.player.magazines[Arsenal.Id.PISTOL]
	var f_press := InputEventKey.new()
	f_press.keycode = KEY_F
	f_press.physical_keycode = KEY_F
	f_press.pressed = true
	game._unhandled_input(f_press)
	check(game.player.magazines[Arsenal.Id.PISTOL] == mag_before_f - 1, "F key fires gun in open air and decrements magazine")
	var f_release := InputEventKey.new()
	f_release.keycode = KEY_F
	f_release.physical_keycode = KEY_F
	f_release.pressed = false
	game._unhandled_input(f_release)

	var target_car := Vehicle.new()
	target_car.kind = Vehicle.Kind.PARKED
	game.add_child(target_car)
	target_car.setup(Vehicle.Kind.PARKED, game.player.global_position + Vector3(0.0, 0.1, -7.0), 0.0)
	game.player._fire_cd = 0.0
	game.camera.yaw = 0.0
	game.camera.pitch = -0.04
	game.player.rotation.y = 0.0
	for _i in 4:
		await physics_frame
		await process_frame
	target_car.global_position = Vector3(game.player.global_position.x, 0.25, game.player.global_position.z - 7.0)
	target_car.force_update_transform()
	for _i in 3:
		await physics_frame
		await process_frame
	var hp_before_f := target_car.hp
	game._unhandled_input(f_press)
	game._unhandled_input(f_release)
	check(target_car.hp < hp_before_f, "F key gunfire hits and damages facing vehicle at horizon pitch")

	game.player.give_weapon(Arsenal.Id.RIFLE, 10)
	game.player._fire_cd = 0.0
	var rifle_mag_before: int = game.player.magazines[Arsenal.Id.RIFLE]
	game._unhandled_input(f_press)
	for _i in 18:
		await physics_frame
		await process_frame
	game._unhandled_input(f_release)
	check(game.player.magazines[Arsenal.Id.RIFLE] <= rifle_mag_before - 2, "Holding F fires full-auto rifle across frames until released")

	target_car.repair()
	game.player.select_weapon(Arsenal.Id.NONE)
	game.player.global_position = target_car.global_position + Vector3(0.0, 0.1, 2.4)
	game.player.force_update_transform()
	await physics_frame
	await process_frame
	game.player._punch_cd = 0.0
	var hp_before_punch := target_car.hp
	game._unhandled_input(f_press)
	game._unhandled_input(f_release)
	check(target_car.hp < hp_before_punch, "F key punches nearby vehicle when unarmed")
	target_car.queue_free()
	game._set_down(game.Phase.WASTED, "WASTED")
	game._respawn()
	check(game.phase == game.Phase.DELIVER, "respawn after theft preserves unfinished delivery")
	check(game.camera.follow == game.player and not game.camera.vehicle_mode, "respawn restores player camera")
	var graphics := InputEventKey.new()
	graphics.keycode = KEY_F6
	graphics.pressed = true
	game._unhandled_input(graphics)
	check(game.clock.quality == GraphicsProfile.Quality.HIGH, "F6 changes graphics profile")
	# Let short driver/UI timers finish before destroying the scene.
	await create_timer(2.5).timeout
	game.queue_free()
	await process_frame
	print("GAME_INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
