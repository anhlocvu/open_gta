class_name Radar
extends Control

var world_span := 360.0
var _redraw_cd := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(148, 148)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


static func _dim_col(col: Color, active_cat: int, matches: bool) -> Color:
	return col if (active_cat == A11yRadar.Category.ALL or matches) else Color(col.r, col.g, col.b, col.a * 0.25)


func _draw() -> void:
	var r := size * 0.5
	if r.x < 12.0:
		return
	var c := size * 0.5
	draw_circle(c, r.x - 2.0, Color(0.04, 0.07, 0.08, 0.72))
	draw_arc(c, r.x - 3.0, 0, TAU, 40, Color("f0a030"), 2.0)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var origin := player.global_position
	var game := get_tree().current_scene
	var tracked: Node3D = player
	if game and game.get("active_aircraft") and game.active_aircraft:
		tracked = game.active_aircraft
		origin = tracked.global_position
	elif game and game.get("active_vehicle") and game.active_vehicle:
		tracked = game.active_vehicle
		origin = tracked.global_position
	var active_cat := A11yRadar.Category.ALL
	var locked_pos := Vector3.ZERO
	var has_locked := false
	if game and game.get("a11y") and game.a11y:
		var a11y = game.a11y
		if a11y.get("radar"):
			active_cat = int(a11y.radar.selected_category)
			if a11y.radar.locked_target_id != "" and a11y.get("nav"):
				var tpos: Vector3 = a11y.nav.target_position
				if tpos != Vector3.ZERO:
					locked_pos = tpos
					has_locked = true
	for node in get_tree().get_nodes_in_group("peds"):
		var ped := node as Node3D
		if ped == null or bool(ped.get("downed")):
			continue
		var is_off := bool(ped.get("is_officer"))
		var col: Color = Color("ff6666") if is_off else Color(0.7, 0.7, 0.65, 0.55)
		var matches := (active_cat == A11yRadar.Category.ENEMIES) if is_off else (active_cat == A11yRadar.Category.CIVILIANS)
		_blip(origin, ped.global_position, c, r.x - 8.0, _dim_col(col, active_cat, matches), 2.4 if is_off else 2.0)
	for node in get_tree().get_nodes_in_group("vehicles"):
		var v := node as Vehicle
		if v == null or v.occupied:
			continue
		var col := Color(0.55, 0.6, 0.7, 0.8)
		var matches := active_cat == A11yRadar.Category.VEHICLES or (active_cat == A11yRadar.Category.ASSETS and v.player_owned)
		if v.kind == Vehicle.Kind.COP:
			col = Color("ff4a4a")
			matches = active_cat == A11yRadar.Category.ENEMIES or active_cat == A11yRadar.Category.VEHICLES or (active_cat == A11yRadar.Category.ASSETS and v.player_owned)
		elif v.kind == Vehicle.Kind.COUPE:
			col = Palette.amber()
			matches = active_cat == A11yRadar.Category.VEHICLES or active_cat == A11yRadar.Category.OBJECTIVES or (active_cat == A11yRadar.Category.ASSETS and v.player_owned)
		elif v.kind == Vehicle.Kind.MILITARY:
			col = Color("6a8a3a")
		if active_cat == A11yRadar.Category.ASSETS and v.player_owned:
			col = Color("5cf2ff")
		_blip(origin, v.global_position, c, r.x - 8.0, _dim_col(col, active_cat, matches), 3.2)
	for node in get_tree().get_nodes_in_group("aircraft"):
		var jet := node as Node3D
		if jet == null:
			continue
		var jet_owned := bool(jet.get("player_owned"))
		var jmatch := active_cat == A11yRadar.Category.VEHICLES or (active_cat == A11yRadar.Category.ASSETS and jet_owned)
		var jcol := Color("5cf2ff") if (active_cat == A11yRadar.Category.ASSETS and jet_owned) else Color("9ad46a")
		_blip(origin, jet.global_position, c, r.x - 8.0, _dim_col(jcol, active_cat, jmatch), 4.0)
	for node in get_tree().get_nodes_in_group("world_pickups"):
		var pk := node as Node3D
		if pk == null or bool(pk.get("taken")):
			continue
		_blip(origin, pk.global_position, c, r.x - 8.0, _dim_col(Color("4ef08c"), active_cat, active_cat == A11yRadar.Category.LOOT), 2.4)
	if game:
		var city = game.get("city")
		if city:
			var pm := active_cat == A11yRadar.Category.PLACES
			_blip(origin, city.gun_shop_pos, c, r.x - 8.0, _dim_col(Color("c45a2a"), active_cat, pm), 2.6)
			_blip(origin, city.bar_pos, c, r.x - 8.0, _dim_col(Color("f0a030"), active_cat, pm), 2.6)
			_blip(origin, city.hospital_pos, c, r.x - 8.0, _dim_col(Color("3dcc6a"), active_cat, pm), 2.6)
			_blip(origin, city.station_pos, c, r.x - 8.0, _dim_col(Color("4a66ff"), active_cat, pm), 2.6)
			_blip(origin, city.spray_pos, c, r.x - 8.0, _dim_col(Color("3aa0ff"), active_cat, pm), 2.6)
			_blip(origin, city.garage_pos, c, r.x - 8.0, _dim_col(Color("e8c84a"), active_cat, pm), 2.6)
			_blip(origin, city.dealership_pos, c, r.x - 8.0, _dim_col(Color("48d8ff"), active_cat, pm), 2.8)
			_blip(origin, city.base_pos, c, r.x - 8.0, _dim_col(Color("6dff88"), active_cat, pm), 3.0)
	if game and game.has_method("radar_objective"):
		var obj: Vector3 = game.radar_objective()
		if obj != Vector3.ZERO:
			_blip(origin, obj, c, r.x - 8.0, _dim_col(Color("5dff88"), active_cat, active_cat == A11yRadar.Category.OBJECTIVES), 4.0)
	if has_locked:
		var lpos := _blip_xy(origin, locked_pos, c, r.x - 8.0)
		draw_line(c, lpos, Color("ffd166", 0.55), 1.5)
		draw_arc(lpos, 6.2, 0.0, TAU, 20, Color("ffd166"), 1.8)
	draw_colored_polygon([
		c + Vector2(0, -7),
		c + Vector2(5, 6),
		c + Vector2(-5, 6),
	], Color("f0e6c8"))


func _blip_xy(origin: Vector3, pos: Vector3, center: Vector2, radius: float) -> Vector2:
	var d := Vector2(pos.x - origin.x, pos.z - origin.z)
	d = d / world_span * radius
	if d.length() > radius:
		d = d.limit_length(radius)
	return center + d


func _blip(origin: Vector3, pos: Vector3, center: Vector2, radius: float, color: Color, size_px: float) -> void:
	draw_circle(_blip_xy(origin, pos, center, radius), size_px, color)

func _process(delta: float) -> void:
	if not visible:
		return
	_redraw_cd -= delta
	if _redraw_cd <= 0.0:
		_redraw_cd = 0.05
		queue_redraw()
