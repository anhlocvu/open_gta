class_name CityAudio
extends Node

const RATE := 22050

var _steps: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _step_cd := 0.0
var _step_side := 0
var _engine_vehicle_id := 0
var _engine_rpm := 0.0
var _engine_pitch := 0.74
var _engine_gain := 0.0
var _foot_a: AudioStreamWAV
var _foot_b: AudioStreamWAV
var _engine_loop: AudioStreamWAV
var _stinger: AudioStreamWAV


func _ready() -> void:
	_foot_a = make_footstep(0)
	_foot_b = make_footstep(1)
	_engine_loop = make_engine()
	_stinger = make_stinger()
	_steps = _player(_foot_a, -8.0, "SFX")
	_engine = _player(_engine_loop, -16.0, "Vehicles")
	_radio = _player(_stinger, -6.0, "SFX")


func play_stinger() -> void:
	if _radio:
		_radio.play()


func tick(delta: float, body: Player, vehicle: Vehicle, rank_up: int) -> void:
	if rank_up > 0 and _radio:
		_radio.play()
	_step_cd = maxf(_step_cd - delta, 0.0)
	if _steps:
		_tick_steps(body)
	if _engine:
		_tick_engine(delta, vehicle)


func _tick_steps(body: Player) -> void:
	if body == null or body.in_vehicle or body.locked or not body.is_on_floor():
		return
	var planar := Vector2(body.velocity.x, body.velocity.z).length()
	if planar < 0.8 or _step_cd > 0.0:
		return
	_step_side = 1 - _step_side
	_steps.stream = _foot_b if _step_side == 1 else _foot_a
	_steps.pitch_scale = 1.08 if body.sprinting else 0.94
	_steps.play()
	_step_cd = 0.32 if body.sprinting else 0.48


func _tick_engine(delta: float, vehicle: Vehicle) -> void:
	if vehicle == null or not vehicle.occupied or vehicle.exploded:
		_engine_vehicle_id = 0
		_engine_rpm = 0.0
		_engine_pitch = engine_pitch(0.0, 1.0)
		_engine_gain = 0.0
		if _engine.playing:
			_engine.stop()
		return
	var cap := maxf(vehicle.max_speed, 1.0)
	var speed_norm := clampf(absf(vehicle.speed) / cap, 0.0, 1.0)
	var raw_throttle := vehicle.throttle_input
	var driving_effort := (raw_throttle > 0.05 and vehicle.speed >= -0.2) or (raw_throttle < -0.05 and vehicle.speed <= 0.2)
	var drive_amt := clampf(absf(raw_throttle), 0.0, 1.0) if driving_effort else 0.0
	var vid := vehicle.get_instance_id()
	if vid != _engine_vehicle_id:
		_engine_vehicle_id = vid
		_engine_rpm = speed_norm * 0.35
		_engine_pitch = engine_pitch(_engine_rpm * cap, cap)
		_engine_gain = 0.0

	var target_rpm := clampf(speed_norm * 0.92 + drive_amt * 0.08, 0.0, 1.0) if driving_effort else speed_norm
	var dt := maxf(delta, 0.0)
	if target_rpm > _engine_rpm:
		var exp_up := lerpf(_engine_rpm, target_rpm, 1.0 - exp(-2.4 * dt))
		_engine_rpm = minf(exp_up, _engine_rpm + 0.46 * dt)
	else:
		var exp_dn := lerpf(_engine_rpm, target_rpm, 1.0 - exp(-1.9 * dt))
		_engine_rpm = maxf(exp_dn, _engine_rpm - 0.36 * dt)

	var target_pitch := engine_pitch(_engine_rpm * cap, cap)
	var exp_pitch := lerpf(_engine_pitch, target_pitch, 1.0 - exp(-5.0 * dt))
	_engine_pitch = move_toward(_engine_pitch, exp_pitch, 0.44 * dt)
	_engine_gain = move_toward(_engine_gain, 1.0, 4.5 * dt)

	_engine.pitch_scale = _engine_pitch
	var base_db := lerpf(-18.5, -8.5, _engine_rpm) + drive_amt * 1.8
	_engine.volume_db = lerpf(-32.0, base_db, _engine_gain)
	if not _engine.playing:
		_engine.play()


func _player(stream: AudioStream, volume: float, bus_name := "Master") -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	player.bus = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"
	add_child(player)
	return player


static func engine_pitch(speed: float, cap: float) -> float:
	var amount := clampf(absf(speed) / maxf(cap, 1.0), 0.0, 1.0)
	return lerpf(0.74, 1.48, pow(amount, 0.85))


static func make_footstep(side: int) -> AudioStreamWAV:
	var count := int(RATE * 0.09)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var tone := 86.0 if side == 0 else 74.0
	for i in count:
		var t := float(i) / float(RATE)
		var env := exp(-t * 36.0)
		var thump := sin(t * TAU * tone) * exp(-t * 55.0)
		var grit := sin(float(i) * (17.0 + float(side) * 3.0)) * sin(float(i) * 0.41)
		samples[i] = clampf((thump * 0.55 + grit * 0.45) * env, -1.0, 1.0)
	return _pcm(samples, false)


static func make_engine() -> AudioStreamWAV:
	var period := 525
	var cycles := 12
	var total := period * cycles
	var samples := PackedFloat32Array()
	samples.resize(total)
	for i in total:
		var u := float(i) / float(total)
		var phase := float(i % period) / float(period)
		var fire := sin(phase * TAU) * 0.46
		fire += sin(phase * TAU * 2.0 + 0.42) * 0.28
		fire += sin(phase * TAU * 3.0 + 0.95) * 0.14
		fire += sin(phase * TAU * 4.0 + 1.45) * 0.06
		var sub := sin(u * TAU * 6.0) * 0.18 + sin(u * TAU * 18.0 + 0.7) * 0.09 + sin(u * TAU * 30.0 + 1.3) * 0.04
		var air := (sin(u * TAU * 7.0) + sin(u * TAU * 11.0 + 1.1) + sin(u * TAU * 17.0 + 2.2) + sin(u * TAU * 23.0 + 0.5)) * 0.025
		samples[i] = clampf(tanh((fire + sub + air) * 1.15) * 0.72, -1.0, 1.0)
	return _pcm(samples, true)


static func make_stinger() -> AudioStreamWAV:
	var count := int(RATE * 0.62)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / float(RATE)
		var sample := 0.0
		if t < 0.07:
			sample += sin(float(i) * 23.0) * sin(float(i) * 0.17) * (1.0 - t / 0.07) * 0.35
		sample += _beep(t, 0.09, 0.2, 880.0) * 0.55
		sample += _beep(t, 0.26, 0.38, 660.0) * 0.5
		if t > 0.44 and t < 0.58:
			var u := (t - 0.44) / 0.14
			sample += sin(float(i) * 19.0) * (1.0 - u) * 0.18
		samples[i] = clampf(sample, -1.0, 1.0)
	return _pcm(samples, false)


static func _beep(t: float, start: float, end_at: float, freq: float) -> float:
	if t < start or t >= end_at:
		return 0.0
	var u := (t - start) / (end_at - start)
	var env := sin(u * PI)
	return sin((t - start) * TAU * freq) * env


static func _pcm(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
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


static func peak(stream: AudioStreamWAV) -> float:
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.data.is_empty():
		return 0.0
	var loudest := 0.0
	var count := stream.data.size() / 2
	for i in count:
		loudest = maxf(loudest, absf(float(stream.data.decode_s16(i * 2)) / 32767.0))
	return loudest
