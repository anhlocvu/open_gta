class_name RoadGraph
extends RefCounted

var nodes: Array[Vector3] = []
var links: Array = []
var node_kinds: Array[String] = []
var edge_modes: Dictionary = {}
var zones: Array[Dictionary] = []
var grid_count := 0


static func grid(xs: Array, zs: Array) -> RoadGraph:
	var g := RoadGraph.new()
	var nx := xs.size()
	var nz := zs.size()
	for zi in nz:
		for xi in nx:
			g.add_node(Vector3(float(xs[xi]), 0.15, float(zs[zi])), "road")
	g.grid_count = g.nodes.size()
	for zi in nz:
		for xi in nx:
			var i := zi * nx + xi
			if xi > 0:
				g.connect_nodes(i, i - 1, "both")
			if xi < nx - 1:
				g.connect_nodes(i, i + 1, "both")
			if zi > 0:
				g.connect_nodes(i, i - nx, "both")
			if zi < nz - 1:
				g.connect_nodes(i, i + nx, "both")
	return g


func add_node(pos: Vector3, kind := "road") -> int:
	var idx := nodes.size()
	nodes.append(pos)
	links.append([])
	node_kinds.append(kind)
	return idx


func connect_nodes(a: int, b: int, mode := "both") -> void:
	if a < 0 or b < 0 or a >= nodes.size() or b >= nodes.size() or a == b:
		return
	if not links[a].has(b):
		links[a].append(b)
	if not links[b].has(a):
		links[b].append(a)
	var key := edge_key(a, b)
	if edge_modes.get(key, "") != "both":
		edge_modes[key] = mode


func _has_drivable_edge(idx: int) -> bool:
	if idx < 0 or idx >= links.size():
		return false
	for nb in links[idx]:
		if str(edge_modes.get(edge_key(idx, int(nb)), "both")) == "both":
			return true
	return false


func nearest(pos: Vector3) -> int:
	if nodes.is_empty():
		return -1
	var limit := mini(nodes.size(), grid_count) if grid_count > 0 else nodes.size()
	var best := 0
	var best_d := INF
	for i in limit:
		var d := pos.distance_squared_to(nodes[i])
		if d < best_d:
			best_d = d
			best = i
	return best


static func edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func corridor_clear(space: PhysicsDirectSpaceState3D, from_pos: Vector3, to_pos: Vector3, half_width: float, exclude_rids: Array[RID], mask: int = 1, ray_height: float = 0.92) -> bool:
	if space == null:
		return true
	var flat := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	if flat.length_squared() < 0.05:
		return true
	var fwd := flat.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var up := Vector3.UP * ray_height
	var offsets: Array[float] = [0.0]
	if half_width > 0.05:
		offsets.append(-half_width)
		offsets.append(half_width)
	for off in offsets:
		var shift := right * off
		var q := PhysicsRayQueryParameters3D.create(from_pos + up + shift, to_pos + up + shift, mask, exclude_rids)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func find_containing_zone(pos: Vector3, only_enclosed := true) -> Dictionary:
	return CityNavBuilder.find_containing_zone(zones, pos, only_enclosed)


func nearest_clear(pos: Vector3, space: PhysicsDirectSpaceState3D = null, exclude_rids: Array[RID] = [], mask: int = 1, mode := "walk", half_width := 0.42) -> int:
	if nodes.is_empty():
		return -1
	var candidates: Array[Dictionary] = []
	for i in nodes.size():
		var kind := node_kinds[i] if i < node_kinds.size() else "road"
		if mode == "drive":
			if kind in ["door", "interior", "sidewalk", "park"]:
				continue
			if not _has_drivable_edge(i):
				continue
		candidates.append({"idx": i, "d2": Vector2(pos.x - nodes[i].x, pos.z - nodes[i].z).length_squared()})
	if candidates.is_empty():
		return nearest(pos)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d2) < float(b.d2))
	if space == null:
		return int(candidates[0].idx)
	var check_count := mini(candidates.size(), 14)
	for k in check_count:
		var idx: int = int(candidates[k].idx)
		if corridor_clear(space, pos, nodes[idx], half_width, exclude_rids, mask):
			return idx
	for k in check_count:
		var idx2: int = int(candidates[k].idx)
		if corridor_clear(space, pos, nodes[idx2], 0.0, exclude_rids, mask):
			return idx2
	return int(candidates[0].idx)


func _zone_anchor(zone: Dictionary, other_zone: Dictionary, pos: Vector3, space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID], mode: String, cw: float) -> int:
	if zone.is_empty():
		return -1
	if mode == "drive" and bool(zone.get("walk_only_entry", false)):
		return -1
	var z_id := str(zone.get("id", ""))
	var o_id := str(other_zone.get("id", ""))
	var o_parent := str(other_zone.get("parent_zone", ""))
	var z_parent := str(zone.get("parent_zone", ""))
	var use_interior := (z_id == o_id) or (o_parent == z_id) or (z_parent == o_id and z_parent != "")
	if use_interior:
		var int_i := int(zone.get("interior_node", -1))
		if int_i >= 0 and int_i < nodes.size() and corridor_clear(space, pos, nodes[int_i], cw, exclude_rids, 1):
			return int_i
	var door_i := int(zone.get("door_node", -1))
	if door_i >= 0 and door_i < nodes.size():
		return door_i
	return -1


func astar_path(from_pos: Vector3, to_pos: Vector3, blocked_edges: Dictionary = {}, space: PhysicsDirectSpaceState3D = null, exclude_rids: Array[RID] = [], mode := "walk", half_width := -1.0) -> Dictionary:
	if nodes.is_empty():
		return {"points": PackedVector3Array([to_pos]), "node_ids": PackedInt32Array()}
	var cw := (1.02 if mode == "drive" else 0.42) if half_width < 0.0 else half_width
	var start_zone := find_containing_zone(from_pos, true)
	var goal_zone := find_containing_zone(to_pos, true)

	if not start_zone.is_empty() and str(start_zone.get("id", "")) == str(goal_zone.get("id", "")):
		if corridor_clear(space, from_pos, to_pos, cw, exclude_rids, 1):
			return {"points": PackedVector3Array([to_pos]), "node_ids": PackedInt32Array()}

	var start_i := _zone_anchor(start_zone, goal_zone, from_pos, space, exclude_rids, mode, cw)
	if start_i < 0:
		start_i = nearest_clear(from_pos, space, exclude_rids, 1, mode, cw)

	var goal_i := _zone_anchor(goal_zone, start_zone, to_pos, space, exclude_rids, mode, cw)
	if goal_i < 0:
		goal_i = nearest_clear(to_pos, space, exclude_rids, 1, mode, cw)

	if start_i < 0 or goal_i < 0:
		return {"points": PackedVector3Array([to_pos]), "node_ids": PackedInt32Array()}
	if start_i == goal_i:
		return {"points": PackedVector3Array([nodes[start_i], to_pos]), "node_ids": PackedInt32Array([start_i])}

	var open_set: Array[int] = [start_i]
	var closed := {}
	var came_from := {}
	var g_score := {start_i: 0.0}
	var f_score := {start_i: _xz_dist(nodes[start_i], nodes[goal_i])}
	var found := false

	while not open_set.is_empty():
		var best_pos := 0
		var best_f := INF
		for idx in open_set.size():
			var nid := open_set[idx]
			var fv := float(f_score.get(nid, INF))
			if fv < best_f:
				best_f = fv
				best_pos = idx
		var cur := open_set[best_pos]
		open_set.remove_at(best_pos)
		if cur == goal_i:
			found = true
			break
		closed[cur] = true
		for nb in links[cur]:
			var nbi := int(nb)
			if closed.has(nbi):
				continue
			var key := edge_key(cur, nbi)
			if mode == "drive" and str(edge_modes.get(key, "both")) == "walk":
				continue
			var step_cost := _xz_dist(nodes[cur], nodes[nbi])
			if mode == "walk" and nbi < node_kinds.size() and node_kinds[nbi] in ["sidewalk", "park", "apron"]:
				step_cost *= 0.94
			var penalty_count := int(blocked_edges.get(key, 0))
			if penalty_count > 0:
				step_cost += 420.0 * float(penalty_count)
			var tentative_g := float(g_score.get(cur, INF)) + step_cost
			if tentative_g < float(g_score.get(nbi, INF)):
				came_from[nbi] = cur
				g_score[nbi] = tentative_g
				f_score[nbi] = tentative_g + _xz_dist(nodes[nbi], nodes[goal_i]) * 0.94
				if not open_set.has(nbi):
					open_set.append(nbi)

	if not found:
		return {"points": PackedVector3Array([to_pos]), "node_ids": PackedInt32Array()}

	var rev_ids: Array[int] = []
	var step := goal_i
	while step != start_i:
		rev_ids.append(step)
		if not came_from.has(step):
			break
		step = int(came_from[step])
	rev_ids.append(start_i)
	rev_ids.reverse()

	var node_ids := PackedInt32Array()
	var pts := PackedVector3Array()
	for nid in rev_ids:
		node_ids.append(nid)
		pts.append(nodes[nid])
	pts.append(to_pos)
	return {"points": pts, "node_ids": node_ids}


func next_toward(from_i: int, dest: Vector3, avoid_i := -1) -> int:
	if from_i < 0 or from_i >= links.size() or links[from_i].is_empty():
		return from_i
	var limit := mini(nodes.size(), grid_count) if grid_count > 0 else nodes.size()
	var options: Array = links[from_i]
	var best: int = -1
	var best_score := -9999.0
	for o in options:
		var idx: int = o
		if idx >= limit:
			continue
		if idx == avoid_i:
			continue
		var score := -nodes[idx].distance_to(dest)
		score += randf() * 0.4
		if score > best_score:
			best_score = score
			best = idx
	if best < 0:
		for o in options:
			var idx2: int = o
			if idx2 < limit:
				return idx2
		return from_i
	return best


func next_away(from_i: int, threat: Vector3) -> int:
	if from_i < 0 or from_i >= links.size() or links[from_i].is_empty():
		return from_i
	var limit := mini(nodes.size(), grid_count) if grid_count > 0 else nodes.size()
	var options: Array = links[from_i]
	var best: int = -1
	var best_d := -1.0
	for o in options:
		var idx: int = o
		if idx >= limit:
			continue
		var d: float = nodes[idx].distance_to(threat)
		if d > best_d:
			best_d = d
			best = idx
	return best if best >= 0 else from_i


func light_open(from_i: int, to_i: int, ignore := false) -> bool:
	if ignore:
		return true
	var a := nodes[from_i]
	var b := nodes[to_i]
	var ns := absf(b.x - a.x) < 1.0
	var tick := int(Time.get_ticks_msec() / 7500.0) % 2
	return (tick == 0) == ns
