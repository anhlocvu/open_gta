class_name A11ySpatialAudio
extends Node3D
## Pooled 3D spatial audio, persistent-slot Doppler vehicles, NPC footsteps, zone ambience, and tactical cues.

const RATE := 22050
const POOL_3D_SIZE := 16
const POOL_UI_SIZE := 6
const POOL_PED_SIZE := 8
const POOL_TRAFFIC_SIZE := 6
const POOL_SIREN_SIZE := 3

static var _wav_cache: Dictionary = {}

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _cursor_3d := 0
var _pool_ui: Array[AudioStreamPlayer] = []
var _cursor_ui := 0
var _pool_ped_3d: Array[AudioStreamPlayer3D] = []
var _cursor_ped := 0
var _pool_traffic_3d: Array[AudioStreamPlayer3D] = []
var _traffic_slot_ids: Array[int] = []
var _traffic_target_pitches: Array[float] = []
var _pool_siren_3d: Array[AudioStreamPlayer3D] = []
var _siren_slot_ids: Array[int] = []
var _aircraft_player: AudioStreamPlayer
var _ambience_players: Array[AudioStreamPlayer3D] = []
var _ambience_ready := false
var _loops_active := false
var _ped_step_cd: Dictionary = {}
var _ped_scan_timer := 0.0
var _traffic_scan_timer := 0.0
var _sonar_queue: Array[Dictionary] = []
var _speech_ref: Node = null

var _wav_shot_player: AudioStreamWAV
var _wav_shot_enemy: AudioStreamWAV
var _wav_shot_ally: AudioStreamWAV
var _wav_step: AudioStreamWAV
var _wav_hit: AudioStreamWAV
var _wav_armor_break: AudioStreamWAV
var _wav_headshot: AudioStreamWAV
var _wav_hurt: AudioStreamWAV
var _wav_empty: AudioStreamWAV
var _wav_reload_start: AudioStreamWAV
var _wav_reload_done: AudioStreamWAV
var _wav_plate_done: AudioStreamWAV
var _wav_pickup: AudioStreamWAV
var _wav_beacon: AudioStreamWAV
var _wav_crosshair: AudioStreamWAV
var _wav_obstacle: AudioStreamWAV
var _wav_punch_swing: AudioStreamWAV
var _wav_punch_hit: AudioStreamWAV
var _wav_npc_scare: AudioStreamWAV
var _wav_npc_down: AudioStreamWAV
var _wav_jump: AudioStreamWAV
var _wav_land: AudioStreamWAV
var _wav_slide: AudioStreamWAV
var _wav_bullet_impact: AudioStreamWAV
var _wav_car_door: AudioStreamWAV
var _wav_car_crash: AudioStreamWAV
var _wav_horn: AudioStreamWAV
var _wav_tire_screech: AudioStreamWAV
var _wav_siren: AudioStreamWAV
var _wav_traffic_engine: AudioStreamWAV
var _wav_aircraft_engine: AudioStreamWAV
var _wav_ocean: AudioStreamWAV
var _wav_bar_groove: AudioStreamWAV
var _wav_shop_chime: AudioStreamWAV
var _wav_sonar: AudioStreamWAV
var _wav_explosion: AudioStreamWAV
var _wav_metal_hit: AudioStreamWAV
var _wav_fire_alarm: AudioStreamWAV


func _ready() -> void:
	ensure_audio_buses()
	_build_streams()
	_speech_ref = A11yUIHelper.speech()
	for i in POOL_3D_SIZE:
		_pool_3d.append(_make_3d_player("SFX", 7.0, 130.0, false))
	for i in POOL_UI_SIZE:
		var u := AudioStreamPlayer.new()
		u.bus = _bus_or_master("A11y")
		add_child(u)
		_pool_ui.append(u)
	for i in POOL_PED_SIZE:
		_pool_ped_3d.append(_make_3d_player("SFX", 4.0, 32.0, false))
	for i in POOL_TRAFFIC_SIZE:
		var t := _make_3d_player("Vehicles", 6.5, 78.0, true)
		t.stream = _wav_traffic_engine
		_pool_traffic_3d.append(t)
		_traffic_slot_ids.append(0)
		_traffic_target_pitches.append(0.74)
	for i in POOL_SIREN_SIZE:
		var s := _make_3d_player("Vehicles", 10.0, 140.0, true)
		s.stream = _wav_siren
		_pool_siren_3d.append(s)
		_siren_slot_ids.append(0)
	_aircraft_player = AudioStreamPlayer.new()
	_aircraft_player.bus = _bus_or_master("Vehicles")
	_aircraft_player.stream = _wav_aircraft_engine
	add_child(_aircraft_player)


func _make_3d_player(bus_name: String, unit_sz: float, max_dist: float, doppler: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = _bus_or_master(bus_name)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = unit_sz
	p.max_distance = max_dist
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP if doppler else AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


static func ensure_audio_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.8
		limiter.threshold_db = -3.0
		AudioServer.add_bus_effect(0, limiter)
	for bus_name in ["SFX", "Vehicles", "Ambience", "A11y"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


static func _bus_or_master(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"


func _sync_a11y_bus_volume() -> void:
	var idx := AudioServer.get_bus_index("A11y")
	if idx < 0:
		return
	var scale := 0.85
	if is_instance_valid(_speech_ref) and _speech_ref.get("settings") != null:
		scale = float(_speech_ref.settings.cue_volume)
	AudioServer.set_bus_mute(idx, scale <= 0.01)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(scale, 0.01)))


func _pick_idle_3d(pool: Array[AudioStreamPlayer3D], cursor_is_main: bool) -> AudioStreamPlayer3D:
	for p in pool:
		if not p.playing:
			return p
	if cursor_is_main:
		var chosen := pool[_cursor_3d]
		_cursor_3d = (_cursor_3d + 1) % pool.size()
		return chosen
	var ped_chosen := pool[_cursor_ped]
	_cursor_ped = (_cursor_ped + 1) % pool.size()
	return ped_chosen


func _play_3d(stream: AudioStream, pos: Vector3, base_db := -4.0, pitch := 1.0, unit_sz := 7.0, bus_name := "SFX") -> void:
	if stream == null or _pool_3d.is_empty():
		return
	var p := _pick_idle_3d(_pool_3d, true)
	p.stop()
	p.bus = _bus_or_master(bus_name)
	p.global_position = pos
	p.unit_size = unit_sz
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = base_db
	p.play()


func _play_ui(stream: AudioStream, base_db := -8.0, pitch := 1.0, bus_name := "A11y") -> void:
	if stream == null or _pool_ui.is_empty():
		return
	if bus_name == "A11y":
		_sync_a11y_bus_volume()
	var p: AudioStreamPlayer = null
	for cand in _pool_ui:
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _pool_ui[_cursor_ui]
		_cursor_ui = (_cursor_ui + 1) % _pool_ui.size()
	p.stop()
	p.bus = _bus_or_master(bus_name)
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = base_db
	p.play()


func play_gunshot(pos: Vector3, is_local: bool, is_ally: bool) -> void:
	if is_local:
		_play_ui(_wav_shot_player, -6.0, randf_range(0.96, 1.04), "SFX")
	elif is_ally:
		_play_3d(_wav_shot_ally, pos, -5.0, randf_range(0.95, 1.05), 9.0, "SFX")
	else:
		_play_3d(_wav_shot_enemy, pos, -2.0, randf_range(0.96, 1.06), 11.0, "SFX")


func play_bullet_impact(pos: Vector3) -> void:
	_play_3d(_wav_bullet_impact, pos, -9.0, randf_range(0.9, 1.15), 5.0, "SFX")


func play_punch(pos: Vector3, landed: bool) -> void:
	if landed:
		_play_3d(_wav_punch_hit, pos, -3.0, randf_range(0.94, 1.06), 6.0, "SFX")
	else:
		_play_ui(_wav_punch_swing, -9.0, randf_range(0.95, 1.08), "SFX")


func play_npc_reaction(pos: Vector3, downed: bool) -> void:
	if downed:
		_play_3d(_wav_npc_down, pos, -6.0, randf_range(0.92, 1.06), 6.0, "SFX")
	else:
		_play_3d(_wav_npc_scare, pos, -7.0, randf_range(0.88, 1.16), 7.5, "SFX")


func play_footstep(pos: Vector3, is_local: bool, sprinting: bool) -> void:
	var pitch := 1.12 if sprinting else 0.94
	if is_local:
		_play_ui(_wav_step, -14.0, pitch, "SFX")
	elif not _pool_ped_3d.is_empty():
		var p := _pick_idle_3d(_pool_ped_3d, false)
		p.stop()
		p.global_position = pos
		p.stream = _wav_step
		p.pitch_scale = pitch * randf_range(0.94, 1.08)
		p.volume_db = -11.0 if sprinting else -14.0
		p.play()


func play_movement_cue(kind: StringName) -> void:
	match kind:
		&"jump": _play_ui(_wav_jump, -11.0, randf_range(0.96, 1.04), "SFX")
		&"land": _play_ui(_wav_land, -10.0, randf_range(0.94, 1.06), "SFX")
		&"slide": _play_ui(_wav_slide, -10.0, 1.0, "SFX")


func play_vehicle_event(kind: StringName, pos: Vector3, intensity := 1.0) -> void:
	match kind:
		&"door": _play_3d(_wav_car_door, pos, -6.0, randf_range(0.95, 1.05), 6.0, "Vehicles")
		&"crash": _play_3d(_wav_car_crash, pos, lerpf(-9.0, -1.5, clampf(intensity, 0.0, 1.0)), randf_range(0.9, 1.08), 11.0, "Vehicles")
		&"horn": _play_3d(_wav_horn, pos, -7.0, randf_range(0.94, 1.06), 9.0, "Vehicles")
		&"screech": _play_3d(_wav_tire_screech, pos, -9.0, randf_range(0.95, 1.08), 8.0, "Vehicles")


func play_vehicle_hit(pos: Vector3, melee := false) -> void:
	_play_3d(_wav_metal_hit, pos, -2.5 if melee else -6.0, randf_range(0.9, 1.12), 8.0, "SFX")


func play_vehicle_fire(pos: Vector3) -> void:
	_play_3d(_wav_fire_alarm, pos, -2.0, 1.0, 12.0, "SFX")


func play_explosion(pos: Vector3) -> void:
	_play_3d(_wav_explosion, pos, 2.0, randf_range(0.92, 1.05), 24.0, "SFX")


func play_shop_cue() -> void:
	_play_ui(_wav_shop_chime, -7.0, 1.0, "SFX")


func play_loot_drop(pos: Vector3, has_weapon := false) -> void:
	_play_3d(_wav_shop_chime if has_weapon else _wav_pickup, pos, -5.0, 1.25 if has_weapon else 1.05, 8.0, "SFX")


func play_hit_confirm(armored: bool, broken: bool, headshot: bool) -> void:
	if headshot:
		_play_ui(_wav_headshot, -5.0, 1.0, "A11y")
	elif broken:
		_play_ui(_wav_armor_break, -4.0, 1.0, "A11y")
	else:
		_play_ui(_wav_hit, -7.0, 0.86 if armored else 1.08, "A11y")


func play_damage_taken(from_pos: Vector3, player_pos: Vector3) -> void:
	var offset := from_pos - player_pos
	if offset.length_squared() < 0.04:
		_play_ui(_wav_hurt, -5.0, 1.0, "SFX")
	else:
		_play_3d(_wav_hurt, player_pos + offset.normalized() * 1.5, -2.0, 1.0, 6.0, "SFX")


func play_weapon_cue(kind: StringName) -> void:
	match kind:
		&"empty": _play_ui(_wav_empty, -6.0, 1.0, "A11y")
		&"reload_start": _play_ui(_wav_reload_start, -8.0, 1.0, "SFX")
		&"reload_done": _play_ui(_wav_reload_done, -7.0, 1.0, "SFX")
		&"plate_done": _play_ui(_wav_plate_done, -7.0, 1.0, "SFX")
		&"pickup": _play_ui(_wav_pickup, -7.0, 1.0, "A11y")


func play_beacon_ping(pos: Vector3, urgent := false) -> void:
	_sync_a11y_bus_volume()
	_play_3d(_wav_beacon, pos, -4.0 if not urgent else -1.0, 1.25 if urgent else 1.0, 16.0, "A11y")


func play_crosshair_ping(alignment: float) -> void:
	var pitch := lerpf(0.85, 1.65, clampf(alignment, 0.0, 1.0))
	_play_ui(_wav_crosshair, -12.0, pitch, "A11y")


func play_obstacle_tick(side: int) -> void:
	var pitch := 0.9 if side < 0 else (1.1 if side > 0 else 1.0)
	_play_ui(_wav_obstacle, -16.0, pitch, "A11y")


func queue_sonar_sweep(pings: Array[Dictionary]) -> void:
	_sonar_queue.clear()
	var t := 0.0
	for item in pings:
		_sonar_queue.append({
			"delay": t,
			"pos": item.get("pos", Vector3.ZERO),
			"pitch": float(item.get("pitch", 1.0)),
			"db": float(item.get("db", -6.0)),
		})
		t += 0.055


func stop_world_loops() -> void:
	if not _loops_active and _sonar_queue.is_empty():
		return
	_loops_active = false
	for i in _pool_traffic_3d.size():
		if _pool_traffic_3d[i].playing: _pool_traffic_3d[i].stop()
		_traffic_slot_ids[i] = 0
	for i in _pool_siren_3d.size():
		if _pool_siren_3d[i].playing: _pool_siren_3d[i].stop()
		_siren_slot_ids[i] = 0
	if _aircraft_player and _aircraft_player.playing:
		_aircraft_player.stop()
	for p in _ambience_players:
		if p.playing: p.stop()
	_sonar_queue.clear()


func tick_world_audio(game: Node, origin: Vector3, delta: float) -> void:
	_tick_sonar_queue(delta)
	if game == null or not game.is_inside_tree():
		return
	_loops_active = true
	var tree := game.get_tree()
	_ensure_ambience(game)
	for p in _ambience_players:
		if not p.playing:
			p.play()
	_tick_aircraft_audio(game, delta)
	_traffic_scan_timer -= delta
	if _traffic_scan_timer <= 0.0:
		_traffic_scan_timer = 0.08
		_tick_traffic_audio(tree, origin)
		_tick_siren_audio(game, tree, origin)
	else:
		_update_active_slot_positions(_pool_traffic_3d, _traffic_slot_ids)
		_update_active_slot_positions(_pool_siren_3d, _siren_slot_ids)
	_smooth_traffic_pitches(delta)
	_tick_ped_audio(tree, origin, delta)


func _smooth_traffic_pitches(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	for i in _pool_traffic_3d.size():
		if _traffic_slot_ids[i] == 0:
			continue
		var p := _pool_traffic_3d[i]
		p.pitch_scale = move_toward(p.pitch_scale, _traffic_target_pitches[i], 0.45 * dt)


func _update_active_slot_positions(pool: Array[AudioStreamPlayer3D], slot_ids: Array[int]) -> void:
	for i in pool.size():
		var vid := slot_ids[i]
		if vid == 0:
			continue
		var obj := instance_from_id(vid)
		if obj is Node3D and is_instance_valid(obj):
			pool[i].global_position = (obj as Node3D).global_position + Vector3(0.0, 1.0, 0.0)


func _tick_sonar_queue(delta: float) -> void:
	if _sonar_queue.is_empty():
		return
	_sync_a11y_bus_volume()
	var remaining: Array[Dictionary] = []
	for item in _sonar_queue:
		item["delay"] = float(item["delay"]) - delta
		if float(item["delay"]) <= 0.0:
			_play_3d(_wav_sonar, item["pos"], float(item["db"]), float(item["pitch"]), 14.0, "A11y")
		else:
			remaining.append(item)
	_sonar_queue = remaining


func _ensure_ambience(game: Node) -> void:
	if _ambience_ready:
		return
	var city = game.get("city")
	if city == null:
		return
	_ambience_ready = true
	var pier_z: float = city.st_zs[0] - 20.0 if city.st_zs.size() > 0 else -280.0
	var ocean := _make_3d_player("Ambience", 18.0, 120.0, false)
	ocean.stream = _wav_ocean
	ocean.global_position = Vector3(0.0, 1.0, pier_z)
	ocean.volume_db = -11.0
	_ambience_players.append(ocean)

	var bar := _make_3d_player("Ambience", 7.0, 44.0, false)
	bar.stream = _wav_bar_groove
	bar.global_position = city.bar_pos + Vector3(0.0, 1.8, 0.0)
	bar.volume_db = -12.0
	_ambience_players.append(bar)


func _tick_aircraft_audio(game: Node, delta: float = 0.016) -> void:
	var jet := game.get("active_aircraft") as Aircraft
	if not is_instance_valid(jet):
		if _aircraft_player.playing:
			_aircraft_player.stop()
		_aircraft_player.pitch_scale = 0.74
		return
	var spd := absf(jet.speed)
	var cap := maxf(jet.max_speed, 1.0)
	var amt := clampf(spd / cap, 0.0, 1.0)
	var target_pitch := lerpf(0.74, 1.45, pow(amt, 0.85))
	_aircraft_player.pitch_scale = move_toward(_aircraft_player.pitch_scale, target_pitch, 0.48 * maxf(delta, 0.0))
	_aircraft_player.volume_db = lerpf(-15.0, -5.0, amt)
	if not _aircraft_player.playing:
		_aircraft_player.pitch_scale = target_pitch
		_aircraft_player.play()


func _assign_persistent_slots(pool: Array[AudioStreamPlayer3D], slot_ids: Array[int], desired: Array[Vehicle], on_update: Callable) -> void:
	var wanted_ids := {}
	for v in desired:
		wanted_ids[v.get_instance_id()] = v
	for i in pool.size():
		var vid := slot_ids[i]
		if vid != 0 and not wanted_ids.has(vid):
			if pool[i].playing:
				pool[i].stop()
			slot_ids[i] = 0
	for v in desired:
		var vid := v.get_instance_id()
		var idx := slot_ids.find(vid)
		if idx < 0:
			idx = slot_ids.find(0)
		if idx >= 0:
			var p := pool[idx]
			var reassigned := slot_ids[idx] != vid
			slot_ids[idx] = vid
			p.global_position = v.global_position + Vector3(0.0, 1.0, 0.0)
			if reassigned:
				p.reset_physics_interpolation()
			on_update.call(p, v, idx, reassigned)
			if not p.playing:
				p.play()


func _tick_traffic_audio(tree: SceneTree, origin: Vector3) -> void:
	var movers: Array[Dictionary] = []
	for node in tree.get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or not is_instance_valid(v) or v.occupied or v.wrecked or absf(v.speed) < 1.2:
			continue
		var d_sq := origin.distance_squared_to(v.global_position)
		if d_sq <= 5625.0:
			movers.append({"v": v, "d_sq": d_sq})
	movers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d_sq) < float(b.d_sq))
	var chosen: Array[Vehicle] = []
	for i in mini(movers.size(), _pool_traffic_3d.size()):
		chosen.append(movers[i].v)
	_assign_persistent_slots(_pool_traffic_3d, _traffic_slot_ids, chosen, func(p: AudioStreamPlayer3D, v: Vehicle, idx: int, reassigned: bool) -> void:
		var target := CityAudio.engine_pitch(v.speed, v.max_speed) * 0.92
		_traffic_target_pitches[idx] = target
		if reassigned:
			p.pitch_scale = target
		p.volume_db = -14.0
	)


func _tick_siren_audio(game: Node, tree: SceneTree, origin: Vector3) -> void:
	var wanted := int(game.get_wanted()) if game.has_method("get_wanted") else 0
	if wanted <= 0:
		for i in _pool_siren_3d.size():
			if _pool_siren_3d[i].playing: _pool_siren_3d[i].stop()
			_siren_slot_ids[i] = 0
		return
	var cop_list: Array[Dictionary] = []
	for node in tree.get_nodes_in_group("cops"):
		var cop := node as Vehicle
		if cop == null or not is_instance_valid(cop) or cop.wrecked or cop.occupied:
			continue
		var d_sq := origin.distance_squared_to(cop.global_position)
		if d_sq <= 19600.0:
			cop_list.append({"v": cop, "d_sq": d_sq})
	cop_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d_sq) < float(b.d_sq))
	var chosen: Array[Vehicle] = []
	for i in mini(cop_list.size(), _pool_siren_3d.size()):
		chosen.append(cop_list[i].v)
	_assign_persistent_slots(_pool_siren_3d, _siren_slot_ids, chosen, func(p: AudioStreamPlayer3D, _v: Vehicle, idx: int, _reassigned: bool) -> void:
		p.volume_db = -7.0
		p.pitch_scale = 1.0 + float(idx) * 0.03
	)


func _tick_ped_audio(tree: SceneTree, origin: Vector3, delta: float) -> void:
	_ped_scan_timer -= delta
	if _ped_scan_timer > 0.0:
		return
	var step_dt := 0.1
	_ped_scan_timer = step_dt
	var near_peds: Array[Dictionary] = []
	for node in tree.get_nodes_in_group("peds"):
		var ped := node as Pedestrian
		if ped == null or not is_instance_valid(ped) or ped.downed:
			continue
		var spd := Vector2(ped.velocity.x, ped.velocity.z).length()
		if spd < 0.7:
			continue
		var d_sq := origin.distance_squared_to(ped.global_position)
		if d_sq >= 1.44 and d_sq <= 676.0:
			near_peds.append({"ped": ped, "d_sq": d_sq, "spd": spd})
	near_peds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d_sq) < float(b.d_sq))
	var active_ids := {}
	for i in mini(near_peds.size(), 6):
		var ped: Pedestrian = near_peds[i].ped
		var pid := ped.get_instance_id()
		active_ids[pid] = true
		var cd := float(_ped_step_cd.get(pid, 0.0)) - step_dt
		if cd <= 0.0:
			var running := float(near_peds[i].spd) > 3.2
			play_footstep(ped.global_position, false, running)
			cd = 0.30 if running else 0.52
		_ped_step_cd[pid] = cd
	if _ped_step_cd.size() > 24:
		for k in _ped_step_cd.keys():
			if not active_ids.has(k):
				_ped_step_cd.erase(k)


func _build_streams() -> void:
	if _wav_cache.is_empty():
		_wav_cache["shot_player"] = _make_shot(0.11, 140.0, 0.75)
		_wav_cache["shot_enemy"] = _make_shot(0.12, 190.0, 0.8)
		_wav_cache["shot_ally"] = _make_shot(0.10, 120.0, 0.65)
		_wav_cache["step"] = _make_step()
		_wav_cache["hit"] = _make_tone_sweep(0.065, 1180.0, 880.0, 0.55)
		_wav_cache["armor_break"] = _make_armor_break()
		_wav_cache["headshot"] = _make_double_tone(0.13, 1320.0, 1760.0)
		_wav_cache["hurt"] = _make_tone_sweep(0.14, 180.0, 75.0, 0.75)
		_wav_cache["empty"] = _make_tone_sweep(0.04, 1500.0, 600.0, 0.4)
		_wav_cache["reload_start"] = _make_tone_sweep(0.08, 420.0, 620.0, 0.35)
		_wav_cache["reload_done"] = _make_double_tone(0.11, 660.0, 990.0)
		_wav_cache["plate_done"] = _make_double_tone(0.12, 520.0, 780.0)
		_wav_cache["pickup"] = _make_double_tone(0.10, 740.0, 1110.0)
		_wav_cache["beacon"] = _make_tone_sweep(0.13, 660.0, 660.0, 0.45)
		_wav_cache["crosshair"] = _make_tone_sweep(0.045, 760.0, 760.0, 0.35)
		_wav_cache["obstacle"] = _make_tone_sweep(0.035, 320.0, 220.0, 0.3)
		_wav_cache["punch_swing"] = _make_noise_whoosh(0.12, 260.0, 140.0, 0.42)
		_wav_cache["punch_hit"] = _make_shot(0.13, 95.0, 0.85)
		_wav_cache["npc_scare"] = _make_tone_sweep(0.16, 480.0, 690.0, 0.45)
		_wav_cache["npc_down"] = _make_tone_sweep(0.14, 140.0, 58.0, 0.6)
		_wav_cache["jump"] = _make_tone_sweep(0.09, 220.0, 390.0, 0.3)
		_wav_cache["land"] = _make_shot(0.08, 72.0, 0.45)
		_wav_cache["slide"] = _make_noise_whoosh(0.24, 520.0, 220.0, 0.38)
		_wav_cache["bullet_impact"] = _make_tone_sweep(0.06, 980.0, 320.0, 0.45)
		_wav_cache["car_door"] = _make_double_tone(0.14, 190.0, 125.0)
		_wav_cache["car_crash"] = _make_shot(0.26, 70.0, 0.9)
		_wav_cache["horn"] = _make_chord_tone(0.22, 410.0, 515.0, 0.48)
		_wav_cache["tire_screech"] = _make_noise_whoosh(0.22, 1650.0, 1420.0, 0.32)
		_wav_cache["siren"] = _make_siren_loop()
		_wav_cache["traffic_engine"] = CityAudio.make_engine()
		_wav_cache["aircraft_engine"] = _make_prop_loop()
		_wav_cache["ocean"] = _make_ocean_loop()
		_wav_cache["bar_groove"] = _make_bar_loop()
		_wav_cache["shop_chime"] = _make_double_tone(0.20, 880.0, 1320.0)
		_wav_cache["sonar"] = _make_tone_sweep(0.07, 940.0, 860.0, 0.5)
		_wav_cache["explosion"] = _make_explosion()
		_wav_cache["metal_hit"] = _make_metal_hit()
		_wav_cache["fire_alarm"] = _make_tone_sweep(0.24, 520.0, 880.0, 0.55)
	_wav_shot_player = _wav_cache["shot_player"]
	_wav_shot_enemy = _wav_cache["shot_enemy"]
	_wav_shot_ally = _wav_cache["shot_ally"]
	_wav_step = _wav_cache["step"]
	_wav_hit = _wav_cache["hit"]
	_wav_armor_break = _wav_cache["armor_break"]
	_wav_headshot = _wav_cache["headshot"]
	_wav_hurt = _wav_cache["hurt"]
	_wav_empty = _wav_cache["empty"]
	_wav_reload_start = _wav_cache["reload_start"]
	_wav_reload_done = _wav_cache["reload_done"]
	_wav_plate_done = _wav_cache["plate_done"]
	_wav_pickup = _wav_cache["pickup"]
	_wav_beacon = _wav_cache["beacon"]
	_wav_crosshair = _wav_cache["crosshair"]
	_wav_obstacle = _wav_cache["obstacle"]
	_wav_punch_swing = _wav_cache["punch_swing"]
	_wav_punch_hit = _wav_cache["punch_hit"]
	_wav_npc_scare = _wav_cache["npc_scare"]
	_wav_npc_down = _wav_cache["npc_down"]
	_wav_jump = _wav_cache["jump"]
	_wav_land = _wav_cache["land"]
	_wav_slide = _wav_cache["slide"]
	_wav_bullet_impact = _wav_cache["bullet_impact"]
	_wav_car_door = _wav_cache["car_door"]
	_wav_car_crash = _wav_cache["car_crash"]
	_wav_horn = _wav_cache["horn"]
	_wav_tire_screech = _wav_cache["tire_screech"]
	_wav_siren = _wav_cache["siren"]
	_wav_traffic_engine = _wav_cache["traffic_engine"]
	_wav_aircraft_engine = _wav_cache["aircraft_engine"]
	_wav_ocean = _wav_cache["ocean"]
	_wav_bar_groove = _wav_cache["bar_groove"]
	_wav_shop_chime = _wav_cache["shop_chime"]
	_wav_sonar = _wav_cache["sonar"]
	_wav_explosion = _wav_cache["explosion"]
	_wav_metal_hit = _wav_cache["metal_hit"]
	_wav_fire_alarm = _wav_cache["fire_alarm"]


static func _make_shot(dur: float, thump_hz: float, amp: float) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 28.0)
		var noise := sin(float(i) * 19.7) * sin(float(i) * 0.63)
		var punch := sin(t * TAU * thump_hz * exp(-t * 12.0))
		samples[i] = clampf((noise * 0.65 + punch * 0.35) * env * amp, -1.0, 1.0)
	return _pcm(samples)


static func _make_metal_hit() -> AudioStreamWAV:
	var count := int(RATE * 0.14)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 24.0)
		var clang := sin(t * TAU * 320.0) * 0.45 + sin(t * TAU * 675.0) * 0.3
		var thud := sin(t * TAU * 92.0 * exp(-t * 10.0)) * 0.5
		samples[i] = clampf((clang + thud) * env * 0.8, -1.0, 1.0)
	return _pcm(samples)


static func _make_explosion() -> AudioStreamWAV:
	var count := int(RATE * 0.85)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 4.4)
		var boom := sin(t * TAU * lerpf(82.0, 34.0, clampf(t / 0.45, 0.0, 1.0))) * 0.55
		var raw_noise := sin(float(i) * 17.3) * sin(float(i) * 0.41) + cos(float(i) * 7.1) * 0.5
		lp = lerpf(lp, raw_noise, 0.18)
		samples[i] = clampf((boom + lp * 0.65) * env * 0.95, -1.0, 1.0)
	return _pcm(samples)


static func _make_step() -> AudioStreamWAV:
	var count := int(RATE * 0.075)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 42.0)
		var thump := sin(t * TAU * 92.0) * 0.6
		var grit := sin(float(i) * 13.0) * sin(float(i) * 0.37) * 0.4
		samples[i] = clampf((thump + grit) * env, -1.0, 1.0)
	return _pcm(samples)


static func _make_armor_break() -> AudioStreamWAV:
	var count := int(RATE * 0.16)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 16.0)
		var ring := sin(t * TAU * 1420.0) * 0.45 + sin(t * TAU * 2130.0) * 0.35
		var crack := sin(float(i) * 29.0) * sin(float(i) * 0.51) * 0.4
		samples[i] = clampf((ring + crack) * env * 0.65, -1.0, 1.0)
	return _pcm(samples)


static func _make_tone_sweep(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		var t := float(i) / float(RATE)
		var env := sin(u * PI)
		var freq := lerpf(f0, f1, u)
		samples[i] = clampf(sin(t * TAU * freq) * env * amp, -1.0, 1.0)
	return _pcm(samples)


static func _make_double_tone(dur: float, f1: float, f2: float) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var half := count / 2
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var local_i := i if i < half else (i - half)
		var u := float(local_i) / maxf(float(half), 1.0)
		var t := float(local_i) / float(RATE)
		var env := sin(u * PI)
		var freq := f1 if i < half else f2
		samples[i] = clampf(sin(t * TAU * freq) * env * 0.5, -1.0, 1.0)
	return _pcm(samples)


static func _make_noise_whoosh(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		var t := float(i) / float(RATE)
		var env := sin(u * PI)
		var air := sin(float(i) * 11.3) * sin(float(i) * 0.47) * 0.55
		var sweep := sin(t * TAU * lerpf(f0, f1, u)) * 0.45
		samples[i] = clampf((air + sweep) * env * amp, -1.0, 1.0)
	return _pcm(samples)


static func _make_chord_tone(dur: float, f1: float, f2: float, amp: float) -> AudioStreamWAV:
	var count := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var u := float(i) / maxf(float(count), 1.0)
		var t := float(i) / float(RATE)
		var env := clampf(minf(u * 10.0, (1.0 - u) * 10.0), 0.0, 1.0)
		var wave := sin(t * TAU * f1) * 0.5 + sin(t * TAU * f2) * 0.5 + sin(t * TAU * f1 * 2.0) * 0.18
		samples[i] = clampf(wave * env * amp, -1.0, 1.0)
	return _pcm(samples)


static func _make_siren_loop() -> AudioStreamWAV:
	var dur := 1.0
	var count := int(RATE * dur)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var u := float(i) / float(count)
		var freq := 680.0 + 260.0 * (0.5 - 0.5 * cos(u * TAU))
		phase += freq / float(RATE)
		var wave := sin(phase * TAU) * 0.72 + sin(phase * TAU * 2.0) * 0.2
		samples[i] = clampf(wave * 0.55, -1.0, 1.0)
	return _pcm(samples, true)


static func _make_prop_loop() -> AudioStreamWAV:
	var period := 588
	var cycles := 6
	var samples := PackedFloat32Array()
	samples.resize(period * cycles)
	for i in samples.size():
		var phase := float(i % period) / float(period)
		var s := sin(phase * TAU) * 0.58 + sin(phase * TAU * 2.0) * 0.28 + sin(phase * TAU * 4.0) * 0.12
		samples[i] = clampf(s * 0.85, -1.0, 1.0)
	return _pcm(samples, true)


static func _make_ocean_loop() -> AudioStreamWAV:
	var count := int(RATE * 2.0)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var u := float(i) / float(count)
		var swell := 0.35 + 0.65 * (0.5 - 0.5 * cos(u * TAU))
		var surf := sin(float(i) * 0.27) * sin(float(i) * 0.071) * 0.5 + sin(float(i) * 0.13) * 0.3
		samples[i] = clampf(surf * swell * 0.35, -1.0, 1.0)
	return _pcm(samples, true)


static func _make_bar_loop() -> AudioStreamWAV:
	var count := int(RATE * 1.6)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes := [110.0, 130.81, 146.83, 130.81]
	for i in count:
		var t := float(i) / float(RATE)
		var beat := int(floor(t / 0.4)) % 4
		var local_t := fmod(t, 0.4)
		var env := exp(-local_t * 6.0)
		var bass := sin(t * TAU * notes[beat]) * 0.55 + sin(t * TAU * notes[beat] * 1.5) * 0.2
		samples[i] = clampf(bass * env * 0.45, -1.0, 1.0)
	return _pcm(samples, true)


static func _pcm(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := clampi(int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)), -32768, 32767)
		bytes.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
