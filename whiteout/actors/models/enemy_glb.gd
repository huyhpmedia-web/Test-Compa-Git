extends RefCounted
## Shared helpers for the glTF enemy models (assets/enemies/*.glb, built by tools/charpipe/bosses/).
## Each model script loads its glb through load_scene(); if the file is missing at runtime the
## model falls back to its old procedural build.

const DIR := "res://assets/enemies/"

static func load_scene(file: String) -> Node3D:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if ps == null or not (ps is PackedScene):
		return null
	var n: Node = (ps as PackedScene).instantiate()
	if n is Node3D:
		fix_materials(n)
		return n as Node3D
	n.queue_free()
	return null

static func find(root: Node, nm: String) -> Node:
	return root.find_child(nm, true, false)

static func meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

## Gives glTF materials the look glTF cannot express: ice (transparent, glossy, rim, faint emission),
## wet flesh/blood (low roughness + clearcoat), emissive glows, translucent frost skin.
static func fix_materials(root: Node) -> void:
	var done := {}
	for mi: MeshInstance3D in meshes(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m == null:
				continue
			if done.has(m):
				continue
			done[m] = true
			if m is BaseMaterial3D:
				_fix(m as BaseMaterial3D)

static func _fix(m: BaseMaterial3D) -> void:
	var n := m.resource_name.to_lower()
	if n.begins_with("ice"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.05
		m.metallic_specular = 1.0
		m.rim_enabled = true
		m.rim = 0.9
		m.rim_tint = 0.5
		if n.begins_with("ice_blood"):
			m.emission_enabled = true
			m.emission = Color(0.5, 0.05, 0.05)
			m.emission_energy_multiplier = 0.25
		else:
			m.emission_enabled = true
			m.emission = Color(0.3, 0.75, 0.95)
			m.emission_energy_multiplier = 0.5 if not n.begins_with("ice_glow") else 2.2
		m.refraction_enabled = false
	elif n.begins_with("glow") or n.begins_with("throat"):
		m.emission_enabled = true
		if m.emission_energy_multiplier < 2.0:
			m.emission_energy_multiplier = 4.0
	elif n.begins_with("blood") or n.begins_with("wet"):
		m.roughness = 0.12
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.08
	elif n.begins_with("skin") or n.begins_with("flesh"):
		m.rim_enabled = true
		m.rim = 0.1
		m.rim_tint = 0.5
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.15
	elif n.begins_with("frost"):
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.7

## Duplicates every material whose name starts with `prefix` on the meshes under `root` so the caller
## can animate it independently (e.g. a head's throat glow); returns the unique materials.
static func unique_mats(root: Node, prefix: String) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m == null:
				m = mi.get_surface_override_material(s)
			if m != null and m.resource_name.to_lower().begins_with(prefix):
				var d := m.duplicate() as Material
				mi.set_surface_override_material(s, d)
				out.append(d)
	return out

## Quick skeleton pose helper: rotates `bone` by `ang` radians about `axis` given in the PARENT's rest frame.
static func bone_rot(sk: Skeleton3D, bone: int, axis: Vector3, ang: float) -> void:
	var rest := sk.get_bone_rest(bone)
	var par := sk.get_bone_parent(bone)
	var pr := Basis.IDENTITY
	if par >= 0:
		pr = sk.get_bone_global_rest(par).basis
	var ax := (pr * axis).normalized() if false else axis
	var d := Basis(ax.normalized(), ang)
	# rotation expressed in the parent's rest frame, applied before the rest rotation
	var q := Quaternion(d)
	sk.set_bone_pose_rotation(bone, q * rest.basis.get_rotation_quaternion())
