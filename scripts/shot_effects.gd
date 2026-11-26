class_name ShotEffects
extends Node3D
## Fixed pool: no timers or nodes are allocated per shot or explosion.
const CAPACITY := 12
var _slots: Array[Node3D] = []
var _life: Array[float] = []
var _impact_life: Array[float] = []
var _explosion_life: Array[float] = []
var _cursor := 0


func _ready() -> void:
	var tracer_material := StandardMaterial3D.new()
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color = Color("fff2c0")
	var geometry := BoxMesh.new()
	geometry.size = Vector3(0.018, 0.018, 1.0)
	var flash_geometry := SphereMesh.new()
	flash_geometry.radius = 0.07
	flash_geometry.height = 0.14
	for i in CAPACITY:
		var slot := Node3D.new()
		var tracer := MeshInstance3D.new()
		tracer.mesh = geometry
		tracer.material_override = tracer_material
		slot.add_child(tracer)
		var flash := MeshInstance3D.new()
		flash.mesh = flash_geometry
		flash.material_override = tracer_material
		slot.add_child(flash)
		var impact := MeshInstance3D.new()
		impact.mesh = flash_geometry
		impact.material_override = tracer_material
		impact.scale = Vector3.ONE * 0.5
		slot.add_child(impact)
		add_child(slot)
		slot.visible = false
		_slots.append(slot)
		_life.append(0.0)
		_impact_life.append(0.0)
		_explosion_life.append(0.0)


func emit_shot(from: Vector3, to: Vector3, has_impact := false) -> void:
	if from.distance_squared_to(to) < 0.0001:
		return
	var slot := _slots[_cursor]
	var tracer := slot.get_child(0) as MeshInstance3D
	var flash := slot.get_child(1) as MeshInstance3D
	var impact := slot.get_child(2) as MeshInstance3D
	tracer.visible = true
	flash.visible = true
	flash.scale = Vector3.ONE
	impact.visible = has_impact
	impact.scale = Vector3.ONE * 0.5
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to)
	tracer.scale = Vector3(1, 1, from.distance_to(to))
	flash.global_position = from
	impact.global_position = to
	slot.visible = true
	_life[_cursor] = 0.055
	_impact_life[_cursor] = 0.18 if has_impact else 0.0
	_explosion_life[_cursor] = 0.0
	_cursor = (_cursor + 1) % CAPACITY


func emit_explosion(pos: Vector3) -> void:
	var slot := _slots[_cursor]
	var tracer := slot.get_child(0) as MeshInstance3D
	var flash := slot.get_child(1) as MeshInstance3D
	var impact := slot.get_child(2) as MeshInstance3D
	tracer.visible = false
	flash.visible = true
	flash.global_position = pos
	flash.scale = Vector3.ONE * 16.0
	impact.visible = true
	impact.global_position = pos + Vector3.UP * 1.4
	impact.scale = Vector3.ONE * 22.0
	slot.visible = true
	_life[_cursor] = 0.0
	_impact_life[_cursor] = 0.0
	_explosion_life[_cursor] = 0.48
	_cursor = (_cursor + 1) % CAPACITY


func _process(delta: float) -> void:
	for i in CAPACITY:
		if _life[i] > 0.0 or _impact_life[i] > 0.0 or _explosion_life[i] > 0.0:
			_life[i] = maxf(_life[i] - delta, 0.0)
			_impact_life[i] = maxf(_impact_life[i] - delta, 0.0)
			_explosion_life[i] = maxf(_explosion_life[i] - delta, 0.0)
			var exp_active := _explosion_life[i] > 0.0
			var flash := _slots[i].get_child(1) as MeshInstance3D
			var impact := _slots[i].get_child(2) as MeshInstance3D
			if exp_active:
				var grow := lerpf(40.0, 14.0, _explosion_life[i] / 0.48)
				flash.scale = Vector3.ONE * grow
				impact.scale = Vector3.ONE * (grow * 1.15)
			else:
				flash.scale = Vector3.ONE
				impact.scale = Vector3.ONE * 0.5
			_slots[i].get_child(0).visible = _life[i] > 0.0
			flash.visible = _life[i] > 0.0 or exp_active
			impact.visible = _impact_life[i] > 0.0 or exp_active
			_slots[i].visible = _life[i] > 0.0 or _impact_life[i] > 0.0 or exp_active
