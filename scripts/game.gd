extends Node3D

enum Phase { TITLE, STEAL, HEAT, DELIVER, FREE, BUSTED, WASTED }

var phase: Phase = Phase.TITLE
var money := 420
var packages_left := 3
var _stolen := false
var _delivered := false
var _bust_timer := 0.0
var _end_timer := 0.0
var _spray_cd := 0.0
var _last_wanted := 0

var city: City
var clock: DayNight
var heat: WantedSystem
var player: Player
var camera: CameraRig
var hud: GameHUD
var touch: TouchControls
var coupe: Vehicle
var active_vehicle: Vehicle
var active_aircraft: Aircraft
var cops: Array[Vehicle] = []
var _crate_taken: Array[Vector3] = []
var _base_cd := 0.0
var _firing := false
var beacon: MeshInstance3D
var last_seen_mark: Marker3D
const SETTINGS_PATH := "user://open_world_settings.cfg"

var roads: RoadGraph
var shot_effects: ShotEffects
var sfx: CityAudio
var a11y: A11yGameplayController
var master_volume := 1.0
var paused := false
var _banner_seq := 0
var _next_cop_dyn_id := 0
var _settings := ConfigFile.new()


func _flash_banner(text: String, duration := 1.5) -> void:
	_banner_seq += 1
	var seq := _banner_seq
	hud.set_banner(text)
	if duration > 0.0 and is_inside_tree():
		get_tree().create_timer(duration).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_instance_valid(hud) and _banner_seq == seq:
				hud.set_banner(""))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_firing = false


func tracked_node() -> Node3D:
	return _tracked()


func is_gameplay_active() -> bool:
	return not paused and phase not in [Phase.TITLE, Phase.BUSTED, Phase.WASTED]


func objective_info() -> Dictionary:
	var dest := radar_objective()
	match phase:
		Phase.STEAL: return {"position": dest, "label": "Steal the amber coupe"}
		Phase.HEAT: return {"position": Vector3.ZERO, "label": "Lose the police units"}
		Phase.DELIVER: return {"position": dest, "label": "Deliver coupe to the warehouse"}
		Phase.FREE: return {"position": dest, "label": "Explore Harbor District or collect packages"}
	return {"position": dest, "label": "Current Objective"}


func get_wanted() -> int:
	return heat.stars if heat else 0


func radar_objective() -> Vector3:
	match phase:
		Phase.STEAL:
			return coupe.global_position if coupe else Vector3.ZERO
		Phase.DELIVER:
			return city.garage_pos
		Phase.HEAT:
			return Vector3.ZERO
		_:
			if packages_left > 0:
				var best_pos := Vector3.ZERO
				var best_dist := INF
				var origin := _tracked().global_position if player else Vector3.ZERO
				if is_inside_tree():
					for node in get_tree().get_nodes_in_group("world_pickups"):
						var pk := node as WorldPickup
						if pk and not pk.taken and pk.kind == WorldPickup.Kind.PACKAGE:
							var d := origin.distance_to(pk.global_position)
							if d < best_dist:
								best_dist = d
								best_pos = pk.global_position
				if best_pos != Vector3.ZERO:
					return best_pos
				return city.package_spawns[0] if city.package_spawns.size() else Vector3.ZERO
			return Vector3.ZERO


func _ready() -> void:
	CombatInput.install()
	shot_effects = ShotEffects.new()
	add_child(shot_effects)
	randomize()
	city = City.new()
	add_child(city)
	city.build()
	roads = city.make_graph()

	clock = DayNight.new()
	add_child(clock)
	clock.bind(city)

	heat = WantedSystem.new()
	add_child(heat)

	last_seen_mark = Marker3D.new()
	add_child(last_seen_mark)

	camera = CameraRig.new()
	camera.add_to_group("camera_rig")
	add_child(camera)

	hud = GameHUD.new()
	add_child(hud)

	touch = TouchControls.new()
	touch.visible = false
	add_child(touch)

	player = Player.new()
	add_child(player)
	player.global_position = city.player_spawn
	player.locked = true
	camera.follow = player

	coupe = Vehicle.new()
	coupe.kind = Vehicle.Kind.COUPE
	coupe.save_id = "coupe"
	add_child(coupe)
	coupe.setup(Vehicle.Kind.COUPE, city.coupe_spawn, city.coupe_facing)
	coupe.bind_graph(roads)

	for i in city.parked_spawns.size():
		var parked: Dictionary = city.parked_spawns[i]
		var v := Vehicle.new()
		v.kind = Vehicle.Kind.PARKED
		v.save_id = "parked:%d" % i
		add_child(v)
		v.setup(Vehicle.Kind.PARKED, parked["pos"], parked["yaw"])
		v.bind_graph(roads)

	for i in city.cop_spawns.size():
		_make_cop(city.cop_spawns[i], i)

	for i in city.traffic_spawns.size():
		var t := Vehicle.new()
		t.kind = Vehicle.Kind.CIVILIAN
		t.save_id = "civ:%d" % i
		add_child(t)
		var spec: Dictionary = city.traffic_spawns[i]
		t.setup(Vehicle.Kind.CIVILIAN, spec["pos"], spec["yaw"])
		t.patrol = city.patrol
		t.patrol_i = (i + 2) % city.patrol.size()
		t.bind_graph(roads)

	_spawn_peds()
	_spawn_pickups()
	_spawn_base_units()
	A11ySpatialAudio.ensure_audio_buses()
	sfx = CityAudio.new()
	add_child(sfx)
	_make_beacon()
	clock.apply(false)
	_sync_hud()
	a11y = A11yGameplayController.new()
	a11y.game = self
	add_child(a11y)
	player.vitality.damaged.connect(func(amt: float) -> void:
		if amt > 0.0 and a11y and a11y.audio:
			a11y.audio.play_damage_taken(player.global_position, player.global_position))
	_load_settings()
	_set_world_active(false)


func _set_world_active(active: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if city:
		city.visible = active
		city.process_mode = mode
	if player:
		player.visible = active and not player.in_vehicle
		player.process_mode = mode
	if camera:
		camera.process_mode = mode
	if beacon:
		beacon.visible = active and radar_objective() != Vector3.ZERO
	if is_inside_tree():
		for grp in [&"vehicles", &"peds", &"aircraft", &"world_pickups"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n is Node3D:
					(n as Node3D).visible = active
				if n is Node:
					(n as Node).process_mode = mode

func set_paused(on: bool, silent := false) -> void:
	if phase == Phase.TITLE:
		paused = false
		return
	paused = on
	_firing = false
	var mode := Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if is_inside_tree():
		for grp in [&"vehicles", &"peds", &"aircraft"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n is Node:
					(n as Node).process_mode = mode
	if player:
		player.locked = on or (phase in [Phase.BUSTED, Phase.WASTED])
		if on and a11y:
			a11y.nav.stop_autowalk(player)
	if on and sfx:
		sfx.tick(0.0, null, null, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (on or phase in [Phase.TITLE, Phase.BUSTED, Phase.WASTED] or DisplayServer.is_touchscreen_available()) else Input.MOUSE_MODE_CAPTURED
	hud.show_pause(on, silent)

func toggle_pause() -> void:
	set_paused(not paused)

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(master_volume, 0.0001)))


static func _serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {
			"kind": "key",
			"code": int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode),
			"shift": k.shift_pressed,
			"ctrl": k.ctrl_pressed,
			"alt": k.alt_pressed,
			"meta": k.meta_pressed,
		}
	if ev is InputEventMouseButton:
		var m := ev as InputEventMouseButton
		return {"kind": "mouse", "button": int(m.button_index)}
	return {}


static func _deserialize_event(raw: Variant) -> InputEvent:
	if raw is Dictionary:
		var d := raw as Dictionary
		var kind := str(d.get("kind", ""))
		if kind == "key":
			var code := SaveManager.safe_int(d.get("code"), 0, 1, 0x7FFFFFFF)
			if code == 0 or code in [KEY_INSERT, KEY_CAPSLOCK]:
				return null
			var kev := InputEventKey.new()
			kev.device = -1
			kev.physical_keycode = code
			kev.shift_pressed = bool(d.get("shift", false))
			kev.ctrl_pressed = bool(d.get("ctrl", false))
			kev.alt_pressed = bool(d.get("alt", false))
			kev.meta_pressed = bool(d.get("meta", false))
			return kev
		if kind == "mouse":
			var btn := SaveManager.safe_int(d.get("button"), 0, 1, 9)
			if btn <= 0:
				return null
			var mev := InputEventMouseButton.new()
			mev.device = -1
			mev.button_index = btn
			return mev
	elif raw is InputEvent and raw.get_script() == null:
		if raw is InputEventKey and (raw.keycode in [KEY_INSERT, KEY_CAPSLOCK] or raw.physical_keycode in [KEY_INSERT, KEY_CAPSLOCK]):
			return null
		var clone := raw.duplicate() as InputEvent
		clone.device = -1
		return clone
	return null


func _load_settings() -> void:
	var speech := A11yUIHelper.speech()
	if speech:
		speech.load_settings(SETTINGS_PATH)
	if _settings.load(SETTINGS_PATH) != OK:
		return
	clock.set_quality(SaveManager.safe_int(_settings.get_value("settings", "quality", 0), 0, 0, GraphicsProfile.Quality.HIGH))
	camera.mouse_sens = SaveManager.safe_float(_settings.get_value("settings", "mouse_sens", 0.0032), 0.0032, 0.0005, 0.02)
	camera.ads_sensitivity = SaveManager.safe_float(_settings.get_value("settings", "ads_sens", 0.55), 0.55, 0.1, 1.5)
	set_master_volume(SaveManager.safe_float(_settings.get_value("settings", "master_volume", 1.0), 1.0, 0.0, 1.0))
	var fp_val: Variant = _settings.get_value("settings", "first_person", false)
	camera.set_first_person(fp_val if fp_val is bool else false)
	camera.first_person_fov = SaveManager.safe_float(_settings.get_value("settings", "fov", 86.0), 86.0, 70.0, 110.0)
	if not _settings.has_section("bindings"):
		return
	for action in _settings.get_section_keys("bindings"):
		if InputMap.has_action(action):
			var raw_events: Variant = _settings.get_value("bindings", action)
			if not (raw_events is Array):
				continue
			var valid_events: Array[InputEvent] = []
			for raw_ev in raw_events:
				var ev := _deserialize_event(raw_ev)
				if ev != null:
					valid_events.append(ev)
			if valid_events.is_empty():
				continue
			InputMap.action_erase_events(action)
			for ev in valid_events:
				InputMap.action_add_event(action, ev)

func save_settings() -> void:
	_settings.set_value("settings", "quality", clock.quality)
	_settings.set_value("settings", "mouse_sens", camera.mouse_sens)
	_settings.set_value("settings", "ads_sens", camera.ads_sensitivity)
	_settings.set_value("settings", "master_volume", master_volume)
	_settings.set_value("settings", "first_person", camera.first_person)
	_settings.set_value("settings", "fov", camera.first_person_fov)
	for action in GameHUD.ACTION_LABELS:
		var encoded: Array[Dictionary] = []
		for ev in InputMap.action_get_events(action):
			var item := _serialize_event(ev)
			if not item.is_empty():
				encoded.append(item)
		_settings.set_value("bindings", action, encoded)
	var speech := A11yUIHelper.speech()
	if speech:
		speech.settings.save_to_config(_settings)
	_settings.save(SETTINGS_PATH)


func _make_cop(pos: Vector3, idx: int, custom_save_id := "") -> Vehicle:
	var cop := Vehicle.new()
	cop.kind = Vehicle.Kind.COP
	if custom_save_id != "":
		cop.save_id = custom_save_id
		if custom_save_id.begins_with("cop_dyn:"):
			var suffix := custom_save_id.substr(8)
			if suffix.is_valid_int():
				_next_cop_dyn_id = maxi(_next_cop_dyn_id, suffix.to_int() + 1)
	elif idx < city.cop_spawns.size():
		cop.save_id = "cop:%d" % idx
	else:
		cop.save_id = "cop_dyn:%d" % _next_cop_dyn_id
		_next_cop_dyn_id += 1
	add_child(cop)
	cop.setup(Vehicle.Kind.COP, pos, PI)
	cop.patrol = city.patrol
	cop.patrol_i = idx % city.patrol.size()
	cop.chase_slot = idx
	cop.bind_graph(roads)
	cops.append(cop)
	return cop


func _spawn_peds() -> void:
	const PEDS_PER_PATH := 6
	for path_i in city.sidewalk_paths.size():
		var raw: Array = city.sidewalk_paths[path_i]
		var typed: Array[Vector3] = []
		for p in raw:
			typed.append(p)
		for n in PEDS_PER_PATH:
			var ped := Pedestrian.new()
			add_child(ped)
			ped.setup(typed, n, PEDS_PER_PATH)


func _spawn_base_units() -> void:
	for i in city.military_spawns.size():
		var spec: Dictionary = city.military_spawns[i]
		var v := Vehicle.new()
		v.kind = Vehicle.Kind.MILITARY
		v.save_id = "mil:%d" % i
		add_child(v)
		v.setup(Vehicle.Kind.MILITARY, spec["pos"], spec["yaw"])
		v.bind_graph(roads)
	for i in city.aircraft_spawns.size():
		var spec: Dictionary = city.aircraft_spawns[i]
		var jet := Aircraft.new()
		jet.save_id = "air:%d" % i
		add_child(jet)
		jet.setup(spec["pos"], spec["yaw"])
	var patrol_base: Array[Vector3] = [
		city.base_pos + Vector3(-16, 0.15, 12),
		city.base_pos + Vector3(16, 0.15, 16),
		city.base_pos + Vector3(10, 0.15, -8),
		city.base_pos + Vector3(-12, 0.15, -4),
	]
	for n in 4:
		var ped := Pedestrian.new()
		ped.is_officer = true
		add_child(ped)
		ped.setup(patrol_base, n, 4)


func _spawn_pickups() -> void:
	for i in city.package_spawns.size():
		var pk := WorldPickup.new()
		pk.save_key = "pkg:%d" % i
		add_child(pk)
		pk.setup(WorldPickup.Kind.PACKAGE, city.package_spawns[i], 180)
	for i in city.health_spawns.size():
		var hp := WorldPickup.new()
		hp.save_key = "hp:%d" % i
		add_child(hp)
		hp.setup(WorldPickup.Kind.HEALTH, city.health_spawns[i], 40)


func begin_saved() -> void:
	if phase != Phase.TITLE:
		return
	if not SaveManager.has_save():
		begin()
		A11yUIHelper.say("No valid saved game found. Starting new game.", true, 2, &"a11y_save", true)
		return
	_enter_gameplay_from_title()
	if not load_saved_game():
		_sync_hud()
		A11yUIHelper.say("No valid saved game found. Starting new game.", true, 2, &"a11y_save", true)


func return_to_main_menu() -> void:
	set_paused(false, true)
	if is_inside_tree():
		get_tree().reload_current_scene()


func district_name(pos: Vector3) -> String:
	if city == null:
		return "Harbor District"
	if city.on_base(pos) or city.near_base_gate(pos):
		return "Army Base"
	if city.st_zs.size() > 0 and pos.z < city.st_zs[0] - 6.0:
		return "Harbor Pier"
	if pos.distance_to(city.hospital_pos) < 42.0:
		return "Hospital District"
	if pos.distance_to(city.station_pos) < 42.0:
		return "Police Precinct"
	if pos.distance_to(city.spray_pos) < 42.0:
		return "West Docks"
	if city.st_zs.size() > 3 and pos.z < city.st_zs[3]:
		return "Warehouse District"
	if city.st_zs.size() > 10 and absf(pos.x) < 110.0 and pos.z < city.st_zs[10]:
		return "Downtown"
	return "North Harbor"


func _collect_vehicles_by_id() -> Dictionary[String, Vehicle]:
	var out: Dictionary[String, Vehicle] = {}
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v and is_instance_valid(v) and is_ancestor_of(v) and v.save_id != "":
			out[v.save_id] = v
	return out


func _collect_aircraft_by_id() -> Dictionary[String, Aircraft]:
	var out: Dictionary[String, Aircraft] = {}
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group("aircraft"):
		var jet := node as Aircraft
		if jet and is_instance_valid(jet) and is_ancestor_of(jet) and jet.save_id != "":
			out[jet.save_id] = jet
	return out


func _cleanup_dynamic_cops(keep_ids: Dictionary[String, bool]) -> void:
	for cop in cops.duplicate():
		if not is_instance_valid(cop):
			cops.erase(cop)
			continue
		if cop.save_id.begins_with("cop_dyn:") and not keep_ids.has(cop.save_id):
			cops.erase(cop)
			cop.remove_from_group("vehicles")
			cop.remove_from_group("cops")
			cop.queue_free()


func _seat_in_vehicle(v: Vehicle) -> void:
	active_vehicle = v
	v.a11y_drive_override = Vector2.ZERO
	v.a11y_handbrake = false
	v.occupied = true
	v.ai_enabled = false
	v.fleeing = false
	player.in_vehicle = true
	player.set_hidden(true)
	camera.follow = v
	camera.set_vehicle_mode(true)
	touch.set_driving(true)


func _seat_in_aircraft(jet: Aircraft) -> void:
	active_aircraft = jet
	jet.occupied = true
	player.in_vehicle = true
	player.set_hidden(true)
	camera.follow = jet
	camera.set_aircraft_mode(true)
	touch.set_driving(true)


func serialize_state() -> Dictionary:
	var alive_pickups := {}
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("world_pickups"):
			var pk := node as WorldPickup
			if pk and is_instance_valid(pk) and not pk.taken and pk.save_key != "":
				alive_pickups[pk.save_key] = true
	var taken_pickups: Array[String] = []
	for i in city.package_spawns.size():
		var k := "pkg:%d" % i
		if not alive_pickups.has(k):
			taken_pickups.append(k)
	for i in city.health_spawns.size():
		var k := "hp:%d" % i
		if not alive_pickups.has(k):
			taken_pickups.append(k)
	var crates_arr: Array = []
	for pos in _crate_taken:
		crates_arr.append(SaveManager.vec3_to_array(pos))
	var ammo_dict := {}
	for k in player.ammo:
		ammo_dict[str(k)] = int(player.ammo[k])
	var mag_dict := {}
	for k in player.magazines:
		mag_dict[str(k)] = int(player.magazines[k])
	var owned_arr: Array[int] = []
	for w in player.owned_weapons:
		owned_arr.append(int(w))
	var save_phase := int(phase)
	if save_phase in [Phase.TITLE, Phase.BUSTED, Phase.WASTED]:
		save_phase = Phase.FREE if _delivered else (Phase.DELIVER if _stolen else Phase.STEAL)
	var tracked_pos := _tracked().global_position
	var vehicles_arr: Array[Dictionary] = []
	var aircraft_arr: Array[Dictionary] = []
	for v in _collect_vehicles_by_id().values():
		vehicles_arr.append(v.to_save_dict())
	for jet in _collect_aircraft_by_id().values():
		aircraft_arr.append(jet.to_save_dict())
	var active_veh_id := active_vehicle.save_id if (active_vehicle != null and is_instance_valid(active_vehicle)) else ""
	var active_air_id := active_aircraft.save_id if (active_aircraft != null and is_instance_valid(active_aircraft)) else ""
	return {
		"phase": save_phase,
		"money": money,
		"packages_left": packages_left,
		"stolen": _stolen,
		"delivered": _delivered,
		"taken_pickups": taken_pickups,
		"crate_taken": crates_arr,
		"active_vehicle_id": active_veh_id,
		"active_aircraft_id": active_air_id,
		"wanted": {
			"stars": heat.stars if heat else 0,
			"heat": heat.heat if heat else 0.0,
			"last_crime": heat.last_crime if heat else "",
		},
		"player": {
			"pos": SaveManager.vec3_to_array(tracked_pos),
			"rot_y": player.rotation.y,
			"health": player.health,
			"stamina": player.stamina,
			"armor": player.vitality.armor,
			"armor_plates": player.armor_plates,
			"crouched": player.crouched,
			"weapon": int(player.weapon),
			"owned_weapons": owned_arr,
			"ammo": ammo_dict,
			"magazines": mag_dict,
			"in_coupe": active_vehicle == coupe,
		},
		"camera": {
			"yaw": camera.yaw,
			"pitch": camera.pitch,
			"first_person": camera.first_person,
			"shoulder": camera.shoulder,
		},
		"coupe": coupe.to_save_dict() if coupe else {},
		"vehicles": vehicles_arr,
		"aircraft": aircraft_arr,
	}


func apply_saved_state(data: Dictionary) -> bool:
	if data.is_empty() or player == null or city == null:
		return false
	if active_aircraft:
		active_aircraft.occupied = false
		active_aircraft.speed = 0.0
		active_aircraft.velocity = Vector3.ZERO
		active_aircraft = null
	if active_vehicle:
		var old_v := active_vehicle
		old_v.occupied = false
		old_v.a11y_drive_override = Vector2.ZERO
		old_v.a11y_handbrake = false
		old_v.throttle_input = 0.0
		old_v.ai_enabled = old_v.has_driver and not old_v.wrecked and not old_v.exploded and (old_v.kind in [Vehicle.Kind.COP, Vehicle.Kind.CIVILIAN])
		active_vehicle = null
	player.in_vehicle = false
	player.set_hidden(false)
	camera.follow = player
	camera.set_vehicle_mode(false)
	camera.set_aircraft_mode(false)
	touch.set_driving(false)

	money = SaveManager.safe_int(data.get("money"), 420, 0, 999999999)
	_stolen = bool(data.get("stolen", false))
	_delivered = bool(data.get("delivered", false))
	packages_left = SaveManager.safe_int(data.get("packages_left"), city.package_spawns.size(), 0, city.package_spawns.size())
	phase = SaveManager.safe_int(data.get("phase"), Phase.STEAL, Phase.STEAL, Phase.FREE) as Phase

	_crate_taken.clear()
	var crates_raw: Variant = data.get("crate_taken", [])
	if crates_raw is Array:
		for item in crates_raw:
			_crate_taken.append(SaveManager.array_to_vec3(item))

	var taken_map := {}
	var taken_raw: Variant = data.get("taken_pickups", [])
	if taken_raw is Array:
		for k in taken_raw:
			taken_map[str(k)] = true
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("world_pickups"):
			var old_pk := node as WorldPickup
			if old_pk:
				old_pk.taken = true
			node.remove_from_group("world_pickups")
			node.queue_free()
	for i in city.package_spawns.size():
		var key := "pkg:%d" % i
		if not taken_map.has(key):
			var pk := WorldPickup.new()
			pk.save_key = key
			add_child(pk)
			pk.setup(WorldPickup.Kind.PACKAGE, city.package_spawns[i], 180)
	for i in city.health_spawns.size():
		var key := "hp:%d" % i
		if not taken_map.has(key):
			var hp := WorldPickup.new()
			hp.save_key = key
			add_child(hp)
			hp.setup(WorldPickup.Kind.HEALTH, city.health_spawns[i], 40)

	var pdata: Dictionary = data.get("player", {}) if data.get("player") is Dictionary else {}
	player.reset_combat()
	var saved_pos := SaveManager.array_to_vec3(pdata.get("pos"), city.player_spawn)
	saved_pos.y = maxf(saved_pos.y, 0.05)
	player.velocity = Vector3.ZERO
	player.global_position = saved_pos
	player.rotation.y = SaveManager.safe_float(pdata.get("rot_y"), 0.0, -TAU * 4.0, TAU * 4.0)
	player.force_update_transform()
	player.health = SaveManager.safe_float(pdata.get("health"), 100.0, 1.0, 100.0)
	player.stamina = SaveManager.safe_float(pdata.get("stamina"), 100.0, 0.0, 100.0)
	player.vitality.armor = SaveManager.safe_float(pdata.get("armor"), 0.0, 0.0, 150.0)
	player.armor_plates = SaveManager.safe_int(pdata.get("armor_plates"), 0, 0, 12)
	player.set_crouched(bool(pdata.get("crouched", false)))
	player.owned_weapons.clear()
	var owned_raw: Variant = pdata.get("owned_weapons", [])
	if owned_raw is Array:
		for wid in owned_raw:
			var id_int := SaveManager.safe_int(wid, 0, 0, 4)
			if id_int > 0 and not player.owned_weapons.has(id_int):
				player.owned_weapons.append(id_int)
	player.ammo = {1: 0, 2: 0, 3: 0, 4: 0}
	var ammo_raw: Variant = pdata.get("ammo", {})
	if ammo_raw is Dictionary:
		for k in ammo_raw:
			var wkey := str(k).to_int() if str(k).is_valid_int() else 0
			if wkey in [1, 2, 3, 4]:
				player.ammo[wkey] = SaveManager.safe_int(ammo_raw[k], 0, 0, 9999)
	player.magazines = {}
	var mag_raw: Variant = pdata.get("magazines", {})
	if mag_raw is Dictionary:
		for k in mag_raw:
			var wkey := str(k).to_int() if str(k).is_valid_int() else 0
			if wkey in [1, 2, 3, 4]:
				player.magazines[wkey] = SaveManager.safe_int(mag_raw[k], 0, 0, 200)
	var saved_w := SaveManager.safe_int(pdata.get("weapon"), Arsenal.Id.NONE, Arsenal.Id.NONE, Arsenal.Id.SHOTGUN)
	player.weapon = saved_w if (saved_w == Arsenal.Id.NONE or player.owned_weapons.has(saved_w)) else Arsenal.Id.NONE

	var veh_by_id := _collect_vehicles_by_id()
	var air_by_id := _collect_aircraft_by_id()
	var vehicles_raw: Variant = data.get("vehicles")
	if vehicles_raw is Array and not (vehicles_raw as Array).is_empty():
		var seen_veh_ids: Dictionary[String, bool] = {}
		for raw_v in vehicles_raw:
			if not (raw_v is Dictionary):
				continue
			var vd := raw_v as Dictionary
			var vid := SaveManager.safe_str(vd.get("id"))
			if vid == "":
				continue
			seen_veh_ids[vid] = true
			var target_v: Vehicle = veh_by_id.get(vid)
			if target_v == null and vid.begins_with("cop_dyn:"):
				target_v = _make_cop(Vector3.ZERO, cops.size(), vid)
				veh_by_id[vid] = target_v
			if target_v != null:
				target_v.apply_save_dict(vd)
		_cleanup_dynamic_cops(seen_veh_ids)
	else:
		var empty_keep: Dictionary[String, bool] = {}
		_cleanup_dynamic_cops(empty_keep)
		var cdata: Dictionary = data.get("coupe", {}) if data.get("coupe") is Dictionary else {}
		if coupe and not cdata.is_empty():
			var legacy_coupe := cdata.duplicate()
			if SaveManager.array_to_vec3(cdata.get("pos"), Vector3.INF) == Vector3.INF:
				legacy_coupe["pos"] = SaveManager.vec3_to_array(city.coupe_spawn)
			var raw_rot: Variant = cdata.get("rot_y")
			if not ((raw_rot is int or raw_rot is float) and is_finite(float(raw_rot))):
				legacy_coupe["rot_y"] = city.coupe_facing
			legacy_coupe["stolen"] = bool(cdata.get("stolen", _stolen))
			legacy_coupe["ai_enabled"] = false
			coupe.apply_save_dict(legacy_coupe)

	var aircraft_raw: Variant = data.get("aircraft")
	if aircraft_raw is Array:
		for raw_a in aircraft_raw:
			if not (raw_a is Dictionary):
				continue
			var ad := raw_a as Dictionary
			var aid := SaveManager.safe_str(ad.get("id"))
			var target_air: Aircraft = air_by_id.get(aid)
			if aid != "" and target_air != null:
				target_air.apply_save_dict(ad)

	var wdata: Dictionary = data.get("wanted", {}) if data.get("wanted") is Dictionary else {}
	if heat:
		heat.clear()
		heat.heat = SaveManager.safe_float(wdata.get("heat"), 0.0, 0.0, 100.0)
		heat.stars = SaveManager.safe_int(wdata.get("stars"), 0, 0, WantedSystem.MAX_STARS)
		heat.last_crime = SaveManager.safe_str(wdata.get("last_crime"))
		_last_wanted = heat.stars
		hud.set_crime(heat.label() if heat.stars > 0 else "")

	var cam_data: Dictionary = data.get("camera", {}) if data.get("camera") is Dictionary else {}
	if camera:
		camera.yaw = SaveManager.safe_float(cam_data.get("yaw"), camera.yaw, -TAU * 4.0, TAU * 4.0)
		camera.pitch = SaveManager.safe_float(cam_data.get("pitch"), camera.pitch, -1.5, 1.5)
		camera.set_first_person(bool(cam_data.get("first_person", camera.first_person)))
		camera.shoulder = -1.0 if SaveManager.safe_float(cam_data.get("shoulder"), 1.0, -1.0, 1.0) < 0.0 else 1.0

	var active_air_id := SaveManager.safe_str(data.get("active_aircraft_id"))
	var active_veh_id := SaveManager.safe_str(data.get("active_vehicle_id"))
	if active_veh_id == "" and bool(pdata.get("in_coupe", false)):
		active_veh_id = "coupe"
	if active_air_id != "" and air_by_id.has(active_air_id):
		var seat_jet := air_by_id[active_air_id]
		if seat_jet and not seat_jet.wrecked:
			_seat_in_aircraft(seat_jet)
	elif active_veh_id != "" and veh_by_id.has(active_veh_id):
		var seat_v := veh_by_id[active_veh_id]
		if seat_v and not seat_v.exploded and (not seat_v.wrecked or seat_v.burning):
			_seat_in_vehicle(seat_v)
		elif seat_v and player.global_position.distance_to(seat_v.global_position) < 2.6:
			player.global_position = seat_v.global_position + seat_v.global_transform.basis.x * 2.4 + Vector3(0, 0.1, 0)
			player.force_update_transform()

	if a11y:
		a11y.reset_state()
		a11y._prev_weapon = player.weapon
		a11y.sync_wanted(heat.stars if heat else 0)
	_sync_hud()
	return true


func save_current_game(path := SaveManager.DEFAULT_PATH) -> bool:
	if phase == Phase.TITLE:
		return false
	var ok := SaveManager.save_data(serialize_state(), path)
	if ok:
		_flash_banner("GAME SAVED", 1.4)
		A11yUIHelper.say("Game saved.", true, 2, &"a11y_save", true)
	else:
		_flash_banner("SAVE FAILED", 1.6)
		A11yUIHelper.say("Save failed.", true, 3, &"a11y_save", true)
	return ok


func load_saved_game(path := SaveManager.DEFAULT_PATH) -> bool:
	var data := SaveManager.load_data(path)
	if data.is_empty():
		return false
	if phase == Phase.TITLE:
		_enter_gameplay_from_title()
	var ok := apply_saved_state(data)
	if ok:
		set_paused(false, true)
		_flash_banner("GAME LOADED", 1.4)
		var dname := district_name(_tracked().global_position)
		var w_desc := "Unarmed" if player.weapon == Arsenal.Id.NONE else Player.weapon_spoken_name(player.weapon)
		A11yUIHelper.say("Saved game loaded in %s. Cash %d dollars. Equipped %s." % [dname, money, w_desc], true, 2, &"a11y_save", true)
	return ok


func _enter_gameplay_from_title() -> void:
	if phase != Phase.TITLE:
		return
	phase = Phase.STEAL
	_set_world_active(true)
	player.locked = false
	touch.visible = DisplayServer.is_touchscreen_available()
	hud.show_start(false)
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func begin() -> void:
	if phase != Phase.TITLE:
		return
	_enter_gameplay_from_title()
	_sync_hud()
	A11yUIHelper.say("Free Chaos started. Objective: Steal the amber coupe. Press Z for status, B and Period to scan radar, Slash for help.", true, 3, &"a11y_ow_start")


func _action_pressed(event: InputEvent, action: StringName) -> bool:
	return A11yUIHelper.action_pressed(event, action)


func _unhandled_input(event: InputEvent) -> void:
	if hud.capture_binding(event):
		return
	if a11y and a11y.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if phase != Phase.TITLE and ((not paused and _action_pressed(event, &"return_menu")) or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE))):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused:
		return
	if _action_pressed(event, &"graphics_profile"):
		clock.set_quality((clock.quality + 1) % 3)
		var q_label := GraphicsProfile.label(clock.quality)
		_flash_banner("GRAPHICS: " + q_label, 2.4)
	if phase == Phase.TITLE:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and get_viewport().gui_get_focus_owner() == null:
			begin()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and phase in [Phase.BUSTED, Phase.WASTED]:
		_respawn()
		return
	if player.locked or phase in [Phase.BUSTED, Phase.WASTED]:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.add_look(event.relative)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _action_pressed(event, &"camera_view"):
		camera.set_first_person(not camera.first_person)
		A11yUIHelper.say("First person view" if camera.first_person else "Third person view", true, 2, &"a11y_view", true)
	if _action_pressed(event, &"interact"):
		_try_interact()
	if _action_pressed(event, &"reload"):
		player.request_reload()
	if _action_pressed(event, &"swap_shoulder") and not player.in_vehicle:
		camera.shoulder *= -1.0
	if _action_pressed(event, &"jump"):
		player.request_jump()
	if _action_pressed(event, &"melee") or _action_pressed(event, &"fire"):
		if not player.in_vehicle:
			if player.weapon == Arsenal.Id.NONE:
				_try_punch()
			else:
				_firing = true
				_try_fire()
	if (event.is_action_released("fire") or event.is_action_released("melee")) and not Input.is_action_pressed("fire") and not Input.is_action_pressed("melee"):
		_firing = false
	if _action_pressed(event, &"cycle_weapon_up"):
		player.cycle_weapon(1)
		if a11y: a11y.announce_weapon_switch(player)
	if _action_pressed(event, &"cycle_weapon_down"):
		player.cycle_weapon(-1)
		if a11y: a11y.announce_weapon_switch(player)
	if _action_pressed(event, &"weapon_holster"):
		player.select_weapon(Arsenal.Id.NONE)
		if a11y: a11y.announce_weapon_switch(player, Arsenal.Id.NONE)
	if _action_pressed(event, &"weapon_1"):
		_weapon_or_buy(Arsenal.Id.PISTOL)
	elif _action_pressed(event, &"weapon_2"):
		_weapon_or_buy(Arsenal.Id.SMG)
	elif _action_pressed(event, &"weapon_3"):
		_weapon_or_buy(Arsenal.Id.RIFLE)
	elif _action_pressed(event, &"weapon_4"):
		_weapon_or_buy(Arsenal.Id.SHOTGUN)
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_4 or event.physical_keycode == KEY_4):
		if city.near_gun_shop(player.global_position) and not player.in_vehicle:
			player.cancel_plate()
			_buy_ammo()


func _process(delta: float) -> void:
	var look := touch.consume_look()
	if look != Vector2.ZERO:
		camera.add_look(look, true)
	if touch.consume_interact():
		if phase == Phase.TITLE:
			begin()
		elif phase in [Phase.BUSTED, Phase.WASTED]:
			_respawn()
		else:
			_try_interact()
	if touch.consume_punch():
		_try_punch()
	if touch.consume_jump():
		player.request_jump()
	if touch.reload_pressed:
		touch.reload_pressed = false
		player.request_reload()
	if touch.crouch_pressed:
		touch.crouch_pressed = false
		player.request_crouch()
	if touch.firing and not touch.was_firing:
		_try_fire()
	touch.was_firing = touch.firing
	if paused:
		return
	if phase in [Phase.BUSTED, Phase.WASTED]:
		_end_timer += delta
		if sfx:
			sfx.tick(delta, null, null, 0)
		return
	if phase == Phase.TITLE:
		return

	_spray_cd = maxf(_spray_cd - delta, 0.0)
	_update_crimes(delta)
	_update_wanted(delta)
	_update_cops()
	_update_civilians()
	_update_mission()
	_check_services()
	_check_busted(delta)
	_check_wasted()
	_update_beacon()
	_update_base(delta)
	if (_firing or touch.firing) and player.weapon != Arsenal.Id.NONE and Arsenal.data(player.weapon).automatic:
		_try_fire()
	if sfx and heat:
		sfx.tick(delta, player, active_vehicle, heat.just_ranked)
	_sync_hud()
	if heat:
		heat.just_ranked = 0


func _try_interact() -> void:
	if player.locked or paused:
		return
	if active_aircraft:
		_exit_aircraft()
		return
	if active_vehicle:
		_exit_vehicle()
		return
	if city.near_bar(player.global_position):
		_use_bar()
		return
	if _try_crate():
		return
	var jet := _nearest_aircraft()
	if jet:
		_enter_aircraft(jet)
		return
	var nearest := _nearest_enterable()
	if nearest:
		_enter_vehicle(nearest)


func _try_punch() -> void:
	if player.locked or player.in_vehicle or player._punch_cd > 0.0:
		return
	var officer := player.try_punch_officer()
	if officer:
		if a11y and a11y.audio: a11y.audio.play_punch(officer.global_position, true)
		_report("assault_cop", officer.global_position)
		_scare_nearby(officer.global_position)
		return
	var hit := player.try_punch()
	if hit:
		if a11y and a11y.audio: a11y.audio.play_punch(hit.global_position, true)
		_scare_nearby(hit.global_position)
		_report("assault", hit.global_position)
		return
	var veh := player.try_punch_vehicle()
	if veh:
		if a11y and a11y.audio: a11y.audio.play_vehicle_hit(veh.global_position, true)
		_scare_nearby(veh.global_position)
		_report("shoot_cop" if veh.kind == Vehicle.Kind.COP else "vandalism", veh.global_position)
		return
	player._punch_cd = 0.45
	if a11y and a11y.audio: a11y.audio.play_punch(player.global_position, false)


func _nearest_enterable() -> Vehicle:
	var best: Vehicle = null
	var best_d := 4.6
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or v.occupied or v.wrecked:
			continue
		var d := player.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _enter_vehicle(v: Vehicle) -> void:
	_firing = false
	var driver := v.eject_driver()
	if driver:
		player.locked = true
		get_tree().create_timer(0.28).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_instance_valid(player) and not paused and phase not in [Phase.TITLE, Phase.BUSTED, Phase.WASTED]:
				player.locked = false
		)
	_seat_in_vehicle(v)
	if v.kind == Vehicle.Kind.COUPE and not _stolen:
		_stolen = true
		v.stolen = true
		_report("jack_mission", v.global_position)
		phase = Phase.HEAT
	elif v.kind == Vehicle.Kind.COP:
		_report("jack_cop", v.global_position)
	elif v.kind == Vehicle.Kind.PARKED:
		_report("alarm", v.global_position)
	elif v.kind == Vehicle.Kind.MILITARY:
		_report("trespass", v.global_position)
	else:
		_report("jack", v.global_position)
	if a11y and a11y.audio:
		a11y.audio.play_vehicle_event(&"door", v.global_position)
	A11yUIHelper.say("Entered %s" % v.display_name, true, 2, &"a11y_vehicle")


func _nearest_aircraft() -> Aircraft:
	var best: Aircraft = null
	var best_d := 9.5
	for node in get_tree().get_nodes_in_group("aircraft"):
		var jet := node as Aircraft
		if jet == null or not jet.can_board(player):
			continue
		var d := player.global_position.distance_to(jet.global_position)
		if d < best_d:
			best_d = d
			best = jet
	return best


func _enter_aircraft(jet: Aircraft) -> void:
	_firing = false
	_seat_in_aircraft(jet)
	_report("steal_jet", jet.global_position)
	A11yUIHelper.say("Boarded %s" % jet.display_name, true, 2, &"a11y_vehicle")


func _exit_aircraft() -> void:
	if active_aircraft == null:
		return
	if abs(active_aircraft.speed) > 8.0 or active_aircraft.global_position.y > 3.5:
		hud.set_prompt("Land and slow down to exit")
		return
	var jet := active_aircraft
	player.global_position = jet.global_position + jet.global_transform.basis.x * 4.2 + Vector3(0, 0.2, 0)
	player.rotation.y = jet.rotation.y
	jet.occupied = false
	player.in_vehicle = false
	player.set_hidden(false)
	active_aircraft = null
	camera.follow = player
	camera.set_aircraft_mode(false)
	touch.set_driving(false)
	A11yUIHelper.say("Exited aircraft", true, 2, &"a11y_vehicle")


func _use_bar() -> void:
	if money < 40:
		_flash_banner("BAR  ·  $40 needed", 1.4)
		return
	money -= 40
	player.heal(40.0)
	player.stamina = 100.0
	if a11y and a11y.audio: a11y.audio.play_shop_cue()
	_flash_banner("WHISKEY  -$40", 1.5)


func _try_crate() -> bool:
	for pos in city.crate_spawns:
		if pos in _crate_taken:
			continue
		if player.global_position.distance_to(pos) < 2.4:
			_crate_taken.append(pos)
			player.give_weapon(Arsenal.Id.RIFLE, 60)
			if a11y and a11y.audio: a11y.audio.play_weapon_cue(&"pickup")
			_report("steal_arms", pos)
			_flash_banner("SERVICE RIFLE", 1.6)
			return true
	return false


func _weapon_or_buy(id: int) -> void:
	if city.near_gun_shop(player.global_position) and not player.in_vehicle:
		_buy_weapon(id)
	else:
		player.select_weapon(id)
		if a11y:
			a11y.announce_weapon_switch(player, id)


func _buy_weapon(id: int) -> void:
	var spec := Arsenal.spec(id)
	var price: int = spec["price"]
	if player.owned_weapons.has(id):
		_buy_ammo()
		return
	if money < price:
		_flash_banner("$%d needed" % price, 1.3)
		return
	money -= price
	player.give_weapon(id)
	if a11y and a11y.audio: a11y.audio.play_shop_cue()
	_flash_banner("%s  -$%d" % [spec["name"], price], 1.5)


func _buy_ammo() -> void:
	if player.weapon == Arsenal.Id.NONE:
		_flash_banner("Buy a gun first", 1.2)
		return
	if money < Arsenal.ammo_price():
		_flash_banner("$80 needed", 1.2)
		return
	money -= Arsenal.ammo_price()
	player.add_ammo(int(Arsenal.spec(player.weapon)["ammo"]))
	if a11y and a11y.audio: a11y.audio.play_shop_cue()
	_flash_banner("AMMO  -$80", 1.3)


func _try_fire() -> void:
	if player.locked or player.in_vehicle or phase in [Phase.TITLE, Phase.BUSTED, Phase.WASTED]:
		return
	if player.weapon == Arsenal.Id.NONE:
		_try_punch()
		return
	var spec := player.spend_shot()
	if spec.is_empty():
		if a11y and player.weapon != Arsenal.Id.NONE and int(player.magazines.get(player.weapon, 0)) == 0 and player.reload_remaining <= 0.0:
			a11y.on_empty_trigger()
		return
	var cam := camera.camera()
	if cam == null:
		return
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var data := Arsenal.data(player.weapon)
	var spread := data.spread * (data.ads_spread_multiplier if player.aiming else 1.0)
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
		spread *= data.moving_spread_multiplier
	dir += cam.global_transform.basis.x * randf_range(-spread, spread)
	dir += cam.global_transform.basis.y * randf_range(-spread, spread)
	dir = dir.normalized()
	var muzzle := player.global_position + Vector3.UP * (0.95 if player.crouched else 1.4)
	var result := Hitscan.cast(get_world_3d(), origin, dir, muzzle, data.effective_range, [player.get_rid()])
	var hit: Dictionary = result.hit
	var end: Vector3 = result.end
	if hit:
		end = hit.position
		var col = hit.collider
		if col is Pedestrian:
			var ped := col as Pedestrian
			var hit_height: float = hit.position.y - ped.global_position.y
			var region := data.head_multiplier if hit_height > 1.3 else (data.limb_multiplier if hit_height < 0.6 else 1.0)
			ped.take_damage(data.damage, region)
			hud.confirm_hit()
			if a11y: a11y.on_hit_confirmed(false, false, region > 1.1)
			if ped.is_officer:
				_report("shoot_cop", ped.global_position)
			else:
				_report("gunfire", ped.global_position)
		elif col is Vehicle:
			var v := col as Vehicle
			v.apply_damage(float(spec["dmg"]))
			hud.confirm_hit()
			if a11y and a11y.audio:
				a11y.audio.play_vehicle_hit(end, false)
			if v.kind == Vehicle.Kind.COP:
				_report("shoot_cop", v.global_position)
			else:
				_report("gunfire", v.global_position)
		else:
			if a11y and a11y.audio: a11y.audio.play_bullet_impact(end)
			_report("gunfire", end)
	else:
		_report("gunfire", player.global_position)
	# Every fired shot is the warning: hits and misses produce one witness reaction.
	_scare_nearby(player.global_position)
	_tracer(muzzle, end)
	if a11y: a11y.on_weapon_fired(0, muzzle, false)
	camera.kick(data)
	camera.add_shake(0.012)


func _tracer(from: Vector3, to: Vector3) -> void:
	shot_effects.emit_shot(from, to)


func _update_base(delta: float) -> void:
	_base_cd = maxf(_base_cd - delta, 0.0)
	if _base_cd > 0.0 or player.in_vehicle:
		return
	if city.on_base(player.global_position):
		_base_cd = 6.0
		_report("trespass", player.global_position)


func _exit_vehicle() -> void:
	if active_vehicle == null:
		return
	if not active_vehicle.burning and abs(active_vehicle.speed) > 6.0:
		return
	_firing = false
	var v := active_vehicle
	v.a11y_drive_override = Vector2.ZERO
	v.a11y_handbrake = false
	v.throttle_input = 0.0
	player.global_position = v.global_position + v.global_transform.basis.x * 1.8 + Vector3(0, 0.1, 0)
	player.rotation.y = v.rotation.y
	v.occupied = false
	if (v.kind == Vehicle.Kind.COP or v.kind == Vehicle.Kind.CIVILIAN) and v.has_driver and not v.wrecked and not v.exploded:
		v.ai_enabled = true
	else:
		v.ai_enabled = false
	player.in_vehicle = false
	player.set_hidden(false)
	active_vehicle = null
	camera.follow = player
	camera.set_vehicle_mode(false)
	touch.set_driving(false)
	if a11y and a11y.audio:
		a11y.audio.play_vehicle_event(&"door", v.global_position)
	A11yUIHelper.say("Exited vehicle", true, 2, &"a11y_vehicle")


func on_vehicle_damage_stage(v: Vehicle, stage: int) -> void:
	if v == null or not is_instance_valid(v):
		return
	var near := v == active_vehicle or (player != null and player.global_position.distance_to(v.global_position) <= 16.0)
	if not near:
		return
	if stage == 1:
		A11yUIHelper.say("%s smoking, %d percent durability." % [v.display_name, int(round(v.hp))], false, 1, &"a11y_veh_dmg")
	elif stage == 2:
		A11yUIHelper.say("%s critical, nearly destroyed!" % v.display_name, true, 2, &"a11y_veh_dmg")


func on_vehicle_burning(v: Vehicle) -> void:
	if v == null or not is_instance_valid(v):
		return
	if a11y and a11y.audio:
		a11y.audio.play_vehicle_fire(v.global_position)
	if v == active_vehicle:
		_flash_banner("VEHICLE ON FIRE!", 1.5)
		A11yUIHelper.say("Vehicle on fire, press E to get out!", true, 3, &"a11y_veh_fire", true)
	elif player and player.global_position.distance_to(v.global_position) <= 28.0:
		A11yUIHelper.say("%s on fire!" % v.display_name, true, 2, &"a11y_veh_fire")


func on_vehicle_exploded(v: Vehicle) -> void:
	if v == null or not is_instance_valid(v) or not is_inside_tree():
		return
	var blast_pos := v.global_position
	if shot_effects:
		shot_effects.emit_explosion(blast_pos + Vector3.UP * 0.8)
	if a11y and a11y.audio:
		a11y.audio.play_explosion(blast_pos)
	var player_dist := player.global_position.distance_to(blast_pos) if player else 999.0
	if camera and player_dist <= 45.0:
		camera.add_shake(clampf(0.42 - player_dist * 0.008, 0.08, 0.42))
	if v == active_vehicle:
		if a11y:
			a11y.nav.stop_autowalk(player, "", v)
		active_vehicle.occupied = false
		active_vehicle = null
		player.global_position = blast_pos + v.global_transform.basis.x * 2.2 + Vector3(0, 0.25, 0)
		player.in_vehicle = false
		player.set_hidden(false)
		camera.follow = player
		camera.set_vehicle_mode(false)
		touch.set_driving(false)
		player.take_damage(95.0, true)
	elif player and not player.in_vehicle and player_dist <= 9.5:
		player.take_damage(lerpf(85.0, 18.0, player_dist / 9.5))
	for node in get_tree().get_nodes_in_group("peds"):
		var ped := node as Pedestrian
		if ped and is_instance_valid(ped) and not ped.downed and blast_pos.distance_to(ped.global_position) <= 9.5:
			ped.knock_down()
	for node in get_tree().get_nodes_in_group("vehicles"):
		var other := node as Vehicle
		if other == null or other == v or not is_instance_valid(other) or other.exploded:
			continue
		var d := blast_pos.distance_to(other.global_position)
		if d <= 8.5:
			other.apply_damage(lerpf(80.0, 30.0, d / 8.5))
	_scare_nearby(blast_pos)
	_report("destroy_cop" if v.kind == Vehicle.Kind.COP else "vehicle_explosion", blast_pos)
	if player_dist <= 42.0:
		A11yUIHelper.say("%s exploded!" % v.display_name, true, 3, &"a11y_veh_blast")


func _report(crime: String, pos: Vector3) -> void:
	var added := heat.report(crime, _witnessed(pos))
	if added > 0:
		hud.set_crime(heat.label())


func _witnessed(pos: Vector3) -> bool:
	for cop in cops:
		if cop.global_position.distance_to(pos) < 46.0 and WantedSystem.has_los(get_world_3d(), cop.global_position, pos):
			return true
	for node in get_tree().get_nodes_in_group("peds"):
		var ped := node as Pedestrian
		if ped and not ped.downed and ped.global_position.distance_to(pos) < 11.0 and WantedSystem.has_los(get_world_3d(), ped.global_position, pos):
			return true
	return false


func _update_crimes(_delta: float) -> void:
	if active_vehicle == null:
		return
	if active_vehicle.last_impact > 8.0:
		camera.add_shake(active_vehicle.last_impact * 0.012)
		player.take_damage(active_vehicle.last_impact * 0.15)
		active_vehicle.last_impact = 0.0
	if abs(active_vehicle.speed) < 7.0:
		return
	for node in get_tree().get_nodes_in_group("peds"):
		var ped := node as Pedestrian
		if ped == null or ped.downed:
			continue
		if active_vehicle.global_position.distance_to(ped.global_position) < 1.9:
			ped.knock_down()
			_scare_nearby(ped.global_position)
			_report("hit_ped", ped.global_position)
			active_vehicle.apply_damage(10.0)
			player.take_damage(4.0)
	for i in range(active_vehicle.get_slide_collision_count()):
		var col := active_vehicle.get_slide_collision(i)
		var other := col.get_collider()
		if other is Vehicle:
			var ov := other as Vehicle
			if ov.kind == Vehicle.Kind.COP and abs(active_vehicle.speed) > 8.0:
				_report("ram_cop", active_vehicle.global_position)
			elif ov.kind != Vehicle.Kind.COP and abs(active_vehicle.speed) > 10.0:
				_report("ram_civ", active_vehicle.global_position)
				ov.fleeing = true


func _scare_nearby(pos: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("peds"):
		var ped := node as Pedestrian
		if ped and pos.distance_to(ped.global_position) < 16.0:
			ped.scare(pos)


func _update_wanted(delta: float) -> void:
	var seen := _cops_can_see()
	heat.tick(delta, seen, _tracked().global_position)
	if heat.stars != _last_wanted:
		if heat.stars > _last_wanted:
			hud.page("DISPATCH  ·  %s  ·  %d units" % [heat.label(), heat.cop_count()])
			_scare_nearby(_tracked().global_position)
		_last_wanted = heat.stars
		if heat.stars == 0:
			hud.set_crime("")


func _cops_can_see() -> bool:
	var target := _tracked()
	var world := get_world_3d()
	for cop in cops:
		if not is_instance_valid(cop):
			continue
		var d := cop.global_position.distance_to(target.global_position)
		if d > 52.0:
			continue
		if not WantedSystem.has_los(world, cop.global_position, target.global_position):
			continue
		var to := (target.global_position - cop.global_position)
		to.y = 0.0
		var fwd := -cop.global_transform.basis.z
		fwd.y = 0.0
		if d < 14.0 or fwd.dot(to.normalized()) > 0.12:
			return true
	for node in get_tree().get_nodes_in_group("foot_cops"):
		var foot := node as Pedestrian
		if foot and not foot.downed and foot.global_position.distance_to(player.global_position) < 16.0:
			if WantedSystem.has_los(world, foot.global_position, player.global_position):
				return true
	return false


func _update_cops() -> void:
	var need := heat.cop_count()
	while cops.size() < need:
		var spawn: Vector3 = city.patrol[cops.size() % city.patrol.size()]
		var me := _tracked().global_position
		if spawn.distance_to(me) < 22.0:
			spawn = city.patrol[(cops.size() + 3) % city.patrol.size()]
		_make_cop(spawn, cops.size())
	var target := _tracked()
	last_seen_mark.global_position = heat.last_seen
	for idx in cops.size():
		var cop := cops[idx]
		if not is_instance_valid(cop) or cop.occupied or not cop.has_driver or cop.wrecked or cop.exploded:
			continue
		cop.ai_enabled = true
		cop.chase_slot = idx
		if heat.stars <= 0:
			cop.chase_target = null
		elif heat.in_sight:
			cop.chase_target = target
			cop.ai_max_speed = 56.0 + float(heat.stars) * 2.4
		elif heat.searching():
			cop.chase_target = last_seen_mark
		else:
			cop.chase_target = null


func _update_civilians() -> void:
	var hot := heat.stars > 0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or not is_ancestor_of(v) or v.occupied:
			continue
		if hot and v.kind == Vehicle.Kind.CIVILIAN and v.has_driver and not v.wrecked and not v.exploded:
			v.fleeing = true
			v.ai_enabled = true


func _tracked() -> Node3D:
	if active_aircraft:
		return active_aircraft
	if active_vehicle:
		return active_vehicle
	return player


func _update_mission() -> void:
	if phase == Phase.HEAT and heat.stars == 0 and _stolen:
		phase = Phase.DELIVER
	elif phase == Phase.DELIVER and heat.stars > 0:
		phase = Phase.HEAT
	if _stolen and city.garage_contains(coupe) and heat.stars == 0 and phase == Phase.DELIVER:
		phase = Phase.FREE
		_delivered = true
		money += 800
		player.locked = false
		if sfx: sfx.play_stinger()
		_flash_banner("DROP COMPLETE  +$800", 2.4)


func _check_services() -> void:
	if active_vehicle == null or _spray_cd > 0.0:
		return
	if city.spray_contains(active_vehicle) and abs(active_vehicle.speed) < 3.0:
		if money >= 200:
			money -= 200
			heat.clear()
			active_vehicle.repair()
			_spray_cd = 4.0
			if a11y and a11y.audio: a11y.audio.play_shop_cue()
			_flash_banner("RESPRAY  -$200", 1.8)
		else:
			hud.set_prompt("Spray shop  ·  $200 needed")


func _check_busted(delta: float) -> void:
	if heat.stars <= 0 or player.in_vehicle or active_aircraft:
		_bust_timer = 0.0
		return
	var close := false
	for cop in cops:
		if is_instance_valid(cop) and cop.global_position.distance_to(player.global_position) < 2.8:
			close = true
			break
	for node in get_tree().get_nodes_in_group("foot_cops"):
		var foot := node as Pedestrian
		if foot and not foot.downed and foot.global_position.distance_to(player.global_position) < 1.55:
			close = true
			_bust_timer += delta * 0.6
	if close:
		_bust_timer += delta
		if _bust_timer >= 1.35:
			_set_down(Phase.BUSTED, "BUSTED")
	else:
		_bust_timer = 0.0


func _check_wasted() -> void:
	if player.health <= 0.0 and phase not in [Phase.BUSTED, Phase.WASTED]:
		_set_down(Phase.WASTED, "WASTED")


func _set_down(p: Phase, banner: String) -> void:
	_firing = false
	player.reset_combat()
	phase = p
	player.locked = true
	if active_vehicle:
		active_vehicle.a11y_drive_override = Vector2.ZERO
		active_vehicle.a11y_handbrake = false
		active_vehicle.occupied = false
		active_vehicle.speed = 0.0
		active_vehicle = null
	if active_aircraft:
		active_aircraft.occupied = false
		active_aircraft.speed = 0.0
		active_aircraft = null
	player.in_vehicle = false
	player.set_hidden(false)
	touch.set_driving(false)
	camera.set_aircraft_mode(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_banner_seq += 1
	hud.set_banner(banner)
	_end_timer = 0.0


func _respawn() -> void:
	var fine := 250 if phase == Phase.BUSTED else 150
	money = maxi(money - fine, 0)
	heat.clear()
	player.health = 100.0
	player.stamina = 100.0
	player.locked = false
	if phase == Phase.BUSTED:
		player.global_position = city.station_pos + Vector3(0, 0.2, 4)
	else:
		player.global_position = city.hospital_pos + Vector3(0, 0.2, 4)
	camera.follow = player
	camera.set_vehicle_mode(false)
	phase = Phase.FREE if _delivered else (Phase.DELIVER if _stolen else Phase.STEAL)
	_banner_seq += 1
	hud.set_banner("")
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_crime("")
	A11yUIHelper.say("Respawned. Health restored.", true, 2, &"a11y_respawn")


func on_pedestrian_knocked_down(ped: Pedestrian) -> void:
	if phase == Phase.TITLE or ped == null or not is_instance_valid(ped):
		return
	var base_y := maxf(ped.global_position.y, 0.0) + 0.1
	var cash_amt := clampi(ped.roll_cash_drop(), 30, 100000)
	var cash_pk := WorldPickup.new()
	add_child(cash_pk)
	cash_pk.setup(WorldPickup.Kind.CASH, Vector3(ped.global_position.x + 0.55, base_y, ped.global_position.z + 0.35), cash_amt, Arsenal.Id.NONE, 60.0)
	if ped.is_officer:
		var w_id: int = ped.loot_weapon_id if ped.loot_weapon_id != Arsenal.Id.NONE else Arsenal.Id.RIFLE
		var rounds := int(Arsenal.spec(w_id)["ammo"])
		var w_pk := WorldPickup.new()
		add_child(w_pk)
		w_pk.setup(WorldPickup.Kind.WEAPON, Vector3(ped.global_position.x - 0.55, base_y, ped.global_position.z - 0.35), rounds, w_id, 60.0)
		if a11y and a11y.audio:
			a11y.audio.play_loot_drop(ped.global_position, true)
		A11yUIHelper.say("Officer dropped %d dollars and %s." % [cash_amt, Player.weapon_spoken_name(w_id)], false, 2, &"a11y_loot")
	else:
		if a11y and a11y.audio:
			a11y.audio.play_loot_drop(ped.global_position, false)
		A11yUIHelper.say("%s dropped %d dollars." % [ped.wealth_label(), cash_amt], false, 1, &"a11y_loot")


func collect_pickup(kind: int, amount: int, weapon_id := Arsenal.Id.NONE) -> void:
	if a11y and a11y.audio:
		a11y.audio.play_weapon_cue(&"pickup")
	if kind == WorldPickup.Kind.HEALTH:
		player.heal(float(amount))
		_flash_banner("HEALTH", 1.4)
	elif kind == WorldPickup.Kind.CASH:
		money += amount
		_flash_banner("+$%d" % amount, 1.4)
	elif kind == WorldPickup.Kind.PACKAGE:
		money += amount
		packages_left = maxi(packages_left - 1, 0)
		_flash_banner("PACKAGE  +$%d" % amount, 1.4)
	elif kind == WorldPickup.Kind.WEAPON and weapon_id != Arsenal.Id.NONE:
		var wname := Player.weapon_spoken_name(weapon_id)
		if player.owned_weapons.has(weapon_id):
			player.add_ammo_for(weapon_id, amount)
			_flash_banner("%s AMMO +%d" % [wname.to_upper(), amount], 1.4)
		else:
			player.give_weapon(weapon_id, amount)
			if a11y:
				a11y._prev_weapon = player.weapon
			_flash_banner("PICKED UP %s" % wname.to_upper(), 1.5)


func _sync_hud() -> void:
	hud.set_wanted(heat.stars if heat else 0, heat.just_ranked if heat else 0)
	var spd := -1.0
	if active_aircraft:
		spd = absf(active_aircraft.speed)
	elif active_vehicle:
		spd = absf(active_vehicle.speed)
	hud.set_stats(player.health, money, player.weapon_label(), spd)
	hud.set_district(district_name(_tracked().global_position) if phase != Phase.TITLE else "")
	hud.set_combat(player.weapon != Arsenal.Id.NONE and not player.in_vehicle and not player.locked, player.aiming, Vector2(player.velocity.x, player.velocity.z).length())
	var near := _nearest_enterable()
	var jet := _nearest_aircraft()
	if active_aircraft:
		var can_land: bool = abs(active_aircraft.speed) <= 8.0 and active_aircraft.global_position.y <= 3.5
		touch.set_can_interact(can_land, "EXIT")
		if can_land:
			hud.set_prompt("E  ·  EXIT JET    WASD fly    mouse pitch")
		else:
			hud.set_prompt("Land and slow down to exit    HP %d" % int(active_aircraft.hp))
	elif active_vehicle:
		var can_exit: bool = active_vehicle.burning or abs(active_vehicle.speed) <= 6.0
		touch.set_can_interact(can_exit, "EXIT")
		if active_vehicle.burning:
			hud.set_prompt("VEHICLE ON FIRE  ·  E  EXIT NOW!")
		elif city.spray_contains(active_vehicle):
			hud.set_prompt("Hold still  ·  respray $200")
		elif can_exit:
			hud.set_prompt("E  ·  EXIT    Space  ·  e-brake    HP %d" % int(active_vehicle.hp))
		else:
			hud.set_prompt("Slow down to exit")
	elif city.near_gun_shop(player.global_position):
		touch.set_can_interact(false, "BUY")
		hud.set_prompt("1 pistol $250   2 SMG $600   3 rifle $900   4 ammo $80   5 shotgun $750")
	elif city.near_bar(player.global_position):
		touch.set_can_interact(true, "DRINK")
		hud.set_prompt("E  ·  WHISKEY $40  ·  heals you")
	elif city.near_base_gate(player.global_position):
		touch.set_can_interact(false, "BASE")
		hud.set_prompt("Drive through the open BASE gate  ·  amber arch")
	elif jet:
		touch.set_can_interact(true, "FLY")
		hud.set_prompt("E  ·  BOARD  " + jet.display_name)
	elif city.near_crate(player.global_position) and not player.in_vehicle:
		touch.set_can_interact(true, "TAKE")
		hud.set_prompt("E  ·  TAKE  RIFLE CRATE")
	elif near:
		touch.set_can_interact(true, "ENTER")
		var near_act := "    F / ; / click  ·  SHOOT" if player.weapon != Arsenal.Id.NONE else "    F / ; / click  ·  PUNCH"
		hud.set_prompt("E  ·  GET IN  " + near.display_name + near_act)
	else:
		touch.set_can_interact(false, "ENTER")
		var gun := "    F / ; / click  ·  SHOOT" if player.weapon != Arsenal.Id.NONE else "    F / ; / click  ·  PUNCH"
		hud.set_prompt((gun.strip_edges()) if phase != Phase.TITLE else "")

	match phase:
		Phase.TITLE:
			hud.set_objective("")
			hud.set_distance(-1.0, "")
		Phase.STEAL:
			hud.set_objective("Steal the amber coupe")
			hud.set_distance(player.global_position.distance_to(coupe.global_position), "COUPE")
		Phase.HEAT:
			hud.set_objective("Lose the harbor units")
			hud.set_distance(-1.0, "")
		Phase.DELIVER:
			hud.set_objective("Drop the coupe at the warehouse")
			hud.set_distance(_tracked().global_position.distance_to(city.garage_pos), "WAREHOUSE")
		Phase.FREE:
			if packages_left > 0:
				hud.set_objective("District open  ·  north streets  ·  BASE gate  ·  %d packages" % packages_left)
				hud.set_distance(_tracked().global_position.distance_to(city.base_pos), "BASE")
			else:
				hud.set_objective("District open  ·  ARMS / BAR / BASE on the radar")
				hud.set_distance(_tracked().global_position.distance_to(city.base_pos), "BASE")
		Phase.BUSTED:
			hud.set_objective("Busted  ·  you lose $250")
			hud.set_prompt("R  ·  RELEASE")
			touch.set_can_interact(true, "OUT")
		Phase.WASTED:
			hud.set_objective("Wasted  ·  hospital bill $150")
			hud.set_prompt("R  ·  WAKE UP")
			touch.set_can_interact(true, "UP")


func _make_beacon() -> void:
	beacon = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.38
	sphere.height = 0.76
	beacon.mesh = sphere
	beacon.material_override = Palette.mat(Palette.amber(), 0.15, 0.25, Palette.amber(), 4.5)
	beacon.visible = false
	add_child(beacon)


func _update_beacon() -> void:
	if beacon == null:
		return
	var dest := radar_objective()
	if dest == Vector3.ZERO:
		beacon.visible = false
		return
	beacon.visible = true
	dest.y += 2.7 + sin(float(Time.get_ticks_msec()) * 0.004) * 0.28
	beacon.global_position = dest
