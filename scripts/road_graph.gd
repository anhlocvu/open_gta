class_name RoadGraph
extends RefCounted

var nodes: Array[Vector3] = []
var links: Array = []


static func grid(xs: Array, zs: Array) -> RoadGraph:
	var g := RoadGraph.new()
	var nx := xs.size()
	var nz := zs.size()
	for zi in nz:
		for xi in nx:
			g.nodes.append(Vector3(float(xs[xi]), 0.15, float(zs[zi])))
	for zi in nz:
		for xi in nx:
			var i := zi * nx + xi
			var nbs: Array = []
			if xi > 0:
				nbs.append(i - 1)
			if xi < nx - 1:
				nbs.append(i + 1)
			if zi > 0:
				nbs.append(i - nx)
			if zi < nz - 1:
				nbs.append(i + nx)
			g.links.append(nbs)
	return g


func nearest(pos: Vector3) -> int:
	if nodes.is_empty():
		return -1
	var best := 0
	var best_d := INF
	for i in nodes.size():
		var d := pos.distance_squared_to(nodes[i])
		if d < best_d:
			best_d = d
			best = i
	return best


static func edge_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func nearest_clear(pos: Vector3, space: PhysicsDirectSpaceState3D = null, exclude_rids: Array[RID] = [], mask: int = 1) -> int:
	if nodes.is_empty():
		return -1
	if space == null:
		return nearest(pos)
	var ranked: Array[Dictionary] = []
	for i in nodes.size():
		ranked.append({"idx": i, "d2": Vector2(pos.x - nodes[i].x, pos.z - nodes[i].z).length_squared()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d2) < float(b.d2))
	var check_count := mini(ranked.size(), 8)
	for k in check_count:
		var idx: int = ranked[k].idx
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.0, nodes[idx] + Vector3.UP * 1.0, mask, exclude_rids)
		if space.intersect_ray(q).is_empty():
			return idx
	return int(ranked[0].idx)


func astar_path(from_pos: Vector3, to_pos: Vector3, blocked_edges: Dictionary = {}, space: PhysicsDirectSpaceState3D = null, exclude_rids: Array[RID] = []) -> Dictionary:
	if nodes.is_empty():
		return {"points": PackedVector3Array([to_pos]), "node_ids": PackedInt32Array()}
	var start_i := nearest_clear(from_pos, space, exclude_rids, 1)
	var goal_i := nearest_clear(to_pos, space, exclude_rids, 1)
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
			var step_cost := _xz_dist(nodes[cur], nodes[nbi])
			var penalty_count := int(blocked_edges.get(edge_key(cur, nbi), 0))
			if penalty_count > 0:
				step_cost += 420.0 * float(penalty_count)
			var tentative_g := float(g_score.get(cur, INF)) + step_cost
			if tentative_g < float(g_score.get(nbi, INF)):
				came_from[nbi] = cur
				g_score[nbi] = tentative_g
				f_score[nbi] = tentative_g + _xz_dist(nodes[nbi], nodes[goal_i])
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
	var options: Array = links[from_i]
	var best: int = options[0]
	var best_score := -9999.0
	for o in options:
		var idx: int = o
		if idx == avoid_i:
			continue
		var score := -nodes[idx].distance_to(dest)
		score += randf() * 0.4
		if score > best_score:
			best_score = score
			best = idx
	return best


func next_away(from_i: int, threat: Vector3) -> int:
	var options: Array = links[from_i]
	var best: int = options[0]
	var best_d := -1.0
	for o in options:
		var d: float = nodes[o].distance_to(threat)
		if d > best_d:
			best_d = d
			best = o
	return best


func light_open(from_i: int, to_i: int, ignore := false) -> bool:
	if ignore:
		return true
	var a := nodes[from_i]
	var b := nodes[to_i]
	var ns := absf(b.x - a.x) < 1.0
	var tick := int(Time.get_ticks_msec() / 7500.0) % 2
	return (tick == 0) == ns
