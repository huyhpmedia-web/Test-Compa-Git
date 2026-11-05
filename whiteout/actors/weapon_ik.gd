extends RefCounted
## Weapon handling for CharacterModel: places the weapon in aim / low-ready space (or in the right hand for melee and reloads), drives both arms to the
## weapon's Grip_R / Support_L markers with an analytic two-bone IK, curls the finger bones around the grip, and runs the procedural recoil spring and the
## moving parts (slide / pump / cylinder). Called once per frame by CharacterModel._process (after the AnimationTree and the aim-pitch bend).
##
## Marker contract (see world/fx.gd weapon_mesh): the marker frame IS the hand bone frame (X thumb/pinky axis, Y along the fingers, Z palm normal).
## Everything here runs in skeleton space; the weapon node is placed with one global transform per frame.

const ANCHOR_R := Vector3(0.0, 0.074, 0.012)    # palm contact point in the hand bone frame (right)
const ANCHOR_L := Vector3(0.0, 0.074, 0.012)
const POLE_R := Vector3(-0.45, -1.0, -0.35)
const POLE_L := Vector3(0.45, -1.0, -0.35)
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]

## Per-weapon handling. aim/low: model-space position of the weapon's glb origin; low_pitch: radians (negative = muzzle down).
## recoil: [pitch (rad), back (m), roll (rad)] peak of the critically damped spring. curl_r/curl_l: degrees for [thumb, index, middle, ring, pinky] (applied to all 3 joints, scaled 0.8/1/0.8).
const SPECS := {
	"handgun": {"ik": true, "aim": Vector3(-0.05, 1.405, 0.56), "low": Vector3(-0.085, 1.20, 0.42), "low_pitch": -0.78,
		"recoil": [0.115, 0.034, 0.035], "move": "Slide", "travel": 0.030, "eject_delay": 0.0,
		"curl_r": [18.0, 22.0, 72.0, 78.0, 80.0], "curl_l": [20.0, 66.0, 72.0, 76.0, 78.0]},
	"magnum": {"ik": true, "aim": Vector3(-0.05, 1.405, 0.55), "low": Vector3(-0.085, 1.20, 0.40), "low_pitch": -0.78,
		"recoil": [0.19, 0.05, 0.06], "move": "", "travel": 0.0, "eject_delay": 0.0,
		"curl_r": [18.0, 24.0, 74.0, 80.0, 82.0], "curl_l": [20.0, 66.0, 72.0, 76.0, 78.0]},
	"shotgun": {"ik": true, "aim": Vector3(-0.115, 1.435, 0.46), "low": Vector3(-0.13, 1.17, 0.30), "low_pitch": -0.70,
		"recoil": [0.15, 0.075, 0.045], "move": "", "travel": 0.0, "eject_delay": 0.30,
		"curl_r": [20.0, 26.0, 74.0, 80.0, 82.0], "curl_l": [32.0, 56.0, 66.0, 70.0, 72.0]},
	"launcher": {"ik": true, "aim": Vector3(-0.12, 1.44, 0.42), "low": Vector3(-0.14, 1.18, 0.28), "low_pitch": -0.70,
		"recoil": [0.16, 0.08, 0.04], "move": "", "travel": 0.0, "eject_delay": 0.0,
		"curl_r": [20.0, 26.0, 74.0, 80.0, 82.0], "curl_l": [32.0, 56.0, 66.0, 70.0, 72.0]},
	"knife": {"ik": false, "carry_rot": Vector3(0.45, 0.0, 0.0),
		"curl_r": [30.0, 78.0, 82.0, 84.0, 84.0], "curl_l": []},
}

var cm: Node3D                  # CharacterModel
var sk: Skeleton3D
var weapon: Node3D              # wrapper from FX.weapon_mesh
var wmodel: Node3D              # glb root (forward -Z)
var wid := ""
var spec := {}
var m_grip := Transform3D.IDENTITY
var m_supp := Transform3D.IDENTITY
var has_supp := false
var muzzle: Node3D
var eject: Node3D
var move_node: Node3D
var _move_base := Vector3.ZERO
var _move_dir := Vector3.ZERO
var cyl_node: Node3D
var _cyl_base := Basis.IDENTITY
var _cyl_ang := 0.0
var _cyl_target := 0.0
var hammer_node: Node3D
var _hammer_base := Basis.IDENTITY

# bones
var _b := {}
var _finger_bones := {"r": [], "l": []}
var _curl_axis := {}            # bone idx -> local axis
var _curl_rest := {}            # bone idx -> rest rotation

# state
var aim_point_world := Vector3.ZERO
var has_aim_point := false
var move_speed := 0.0
var _aim_w := 0.0
var _reload_w := 0.0
var _t := 0.0
var _slide_t := 9.0
var _slide_lock := false
var _eject_timer := -1.0
var _eject_pending_pos := Vector3.ZERO
var eject_cb: Callable          # func(world_pos: Vector3, world_dir: Vector3) -> void
# recoil spring (pitch rad, back m, roll rad)
var _sx := [0.0, 0.0, 0.0]
var _sv := [0.0, 0.0, 0.0]
const OMEGA := 26.0

func _init(model: Node3D) -> void:
	cm = model
	sk = model.skeleton
	if sk == null:
		return
	for n in ["upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "clavicle_l"]:
		_b[n] = sk.find_bone(n)
	for side in ["r", "l"]:
		for f in FINGERS:
			var arr := []
			for j in 3:
				arr.append(sk.find_bone("%s_%02d_%s" % [f, j + 1, side]))
			_finger_bones[side].append(arr)
	_prepare_curl_axes()

func valid() -> bool:
	return sk != null and _b.get("hand_r", -1) >= 0

# ------------------------------------------------------------------ setup
func set_weapon(w: Node3D) -> void:
	_release_fingers()
	if weapon != null and is_instance_valid(weapon):
		weapon.queue_free()
	weapon = null; wmodel = null; wid = ""; spec = {}
	muzzle = null; eject = null; move_node = null; cyl_node = null; hammer_node = null
	_slide_lock = false; _slide_t = 9.0; _eject_timer = -1.0
	for i in 3:
		_sx[i] = 0.0; _sv[i] = 0.0
	if w == null or not valid():
		return
	weapon = w
	wid = String(w.get_meta("weapon_id", ""))
	wmodel = w.get_meta("model", null)
	if wmodel == null or not SPECS.has(wid):
		# not one of ours (e.g. the foreman's pick): plain hand attachment
		weapon = null
		cm.held.add_child(w)
		return
	spec = SPECS[wid]
	cm.add_child(weapon)
	var g := wmodel.find_child("Grip_R", true, false) as Node3D
	var s := wmodel.find_child("Support_L", true, false) as Node3D
	m_grip = _rel(g, wmodel) if g else Transform3D.IDENTITY
	has_supp = s != null
	m_supp = _rel(s, wmodel) if s else Transform3D.IDENTITY
	muzzle = wmodel.find_child("Muzzle", true, false) as Node3D
	eject = wmodel.find_child("Eject", true, false) as Node3D
	var mv := String(spec.get("move", ""))
	if mv != "":
		move_node = wmodel.find_child(mv, true, false) as Node3D
		if move_node:
			_move_base = move_node.position
			# weapon back (+Z of the glb frame) expressed in the moving part's parent frame
			var pb := _rel(move_node.get_parent() as Node3D, wmodel).basis
			_move_dir = (pb.inverse() * Vector3(0, 0, 1)).normalized()
	cyl_node = wmodel.find_child("Cylinder", true, false) as Node3D
	if cyl_node:
		_cyl_base = cyl_node.basis
		_cyl_ang = 0.0; _cyl_target = 0.0
	hammer_node = wmodel.find_child("Hammer", true, false) as Node3D
	if hammer_node:
		_hammer_base = hammer_node.basis

func _rel(n: Node3D, anc: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != anc:
		t = cur.transform * t
		cur = cur.get_parent() as Node3D
	return t

# ------------------------------------------------------------------ gameplay hooks
## Fire: kicks the recoil spring and cycles the action. `scale` > 1 for heavier follow-up shots.
func kick(power := 1.0) -> void:
	if spec.is_empty():
		return
	var r: Array = spec.recoil
	var rnd := randf_range(0.85, 1.15)
	_sv[0] += r[0] * OMEGA * 2.718 * power * rnd * (1.0 if _aim_w > 0.5 else 0.7)
	_sv[1] += r[1] * OMEGA * 2.718 * power * rnd
	_sv[2] += r[2] * OMEGA * 2.718 * power * rnd * (1.0 if randf() < 0.5 else -1.0)
	_slide_t = 0.0
	if cyl_node:
		_cyl_target += PI / 3.0
	var d: float = spec.get("eject_delay", 0.0)
	if eject and d <= 0.0:
		_do_eject()
	elif eject and d > 0.0:
		_eject_timer = d

func set_slide_locked(on: bool) -> void:
	_slide_lock = on

func muzzle_xf() -> Transform3D:
	if muzzle and muzzle.is_inside_tree():
		return muzzle.global_transform
	return cm.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 0.6))

func _do_eject() -> void:
	if eject == null or not eject.is_inside_tree() or not eject_cb.is_valid():
		return
	eject_cb.call(eject.global_transform.origin, wmodel.global_transform.basis)

func weapon_basis() -> Basis:
	return wmodel.global_transform.basis if wmodel and wmodel.is_inside_tree() else cm.global_transform.basis

# ------------------------------------------------------------------ per frame
func update(delta: float) -> void:
	if not valid():
		return
	_t += delta
	if weapon == null or spec.is_empty():
		return
	var reload_now: bool = cm.is_playing("reload")
	_reload_w = move_toward(_reload_w, 1.0 if reload_now else 0.0, delta * 7.0)
	_aim_w = cm._aim_w
	_update_springs(delta)
	_update_parts(delta)
	var pose_w := 1.0 - _reload_w
	# ---- hand-attached weapon transform (melee, reloads, blends)
	var hand_r: Transform3D = sk.get_bone_global_pose(_b.hand_r)
	var carry_rot: Vector3 = spec.get("carry_rot", Vector3.ZERO)
	var a_r := Transform3D(Basis.from_euler(carry_rot), ANCHOR_R)
	var w_hand: Transform3D = hand_r * a_r * m_grip.affine_inverse()
	var w := w_hand
	var fwd := Vector3.FORWARD
	if spec.ik:
		var w_pose := _pose_transform(delta)
		w = w_hand.interpolate_with(w_pose, pose_w)
		# recoil about the grip (applied after blending so reloads stay clean)
		w = _apply_recoil(w, pose_w)
		fwd = -w.basis.z
		# reach check: keep the support hand reachable by pulling the weapon back
		var shift := _excess("upperarm_r", "lowerarm_r", "hand_r", (w * m_grip).origin)
		if has_supp:
			shift = maxf(shift, _excess("upperarm_l", "lowerarm_l", "hand_l", (w * m_supp).origin))
		if shift > 0.0 and pose_w > 0.0:
			w.origin -= fwd * shift * pose_w
	weapon.global_transform = _to_wrapper(w)
	if spec.ik:
		var iw := pose_w
		_ik_arm("r", w * m_grip, ANCHOR_R, POLE_R, iw)
		if has_supp:
			_ik_arm("l", w * m_supp, ANCHOR_L, POLE_L, iw)
		_apply_curls(1.0, iw if has_supp else 0.0)
	else:
		_apply_curls(1.0, 0.0)

func _to_wrapper(w_skel: Transform3D) -> Transform3D:
	# wmodel's world transform = skeleton world * w; the wrapper holds wmodel at wmodel.transform
	return sk.global_transform * w_skel * wmodel.transform.affine_inverse()

## Weapon (glb frame) transform in skeleton space for the current stance (aim <-> low ready).
func _pose_transform(delta: float) -> Transform3D:
	var pitch: float = cm.aim_pitch
	# --- aim
	var aim_pos: Vector3 = spec.aim
	var piv := Vector3(0.0, 1.43, 0.0)
	var ap := clampf(pitch, -0.9, 0.9)
	var aim_p := piv + Basis(Vector3.RIGHT, -ap) * (aim_pos - piv)
	var dir := Vector3(0, sin(ap), cos(ap))
	if has_aim_point:
		var tp := sk.global_transform.affine_inverse() * aim_point_world
		var to := tp - (aim_p + dir * 0.3)
		if to.length() > 2.0:
			var d2 := to.normalized()
			# limit the convergence to ~11 degrees off the camera-pitch direction
			var ang := dir.angle_to(d2)
			if ang > 0.19:
				d2 = dir.slerp(d2, 0.19 / ang)
			dir = d2
	# breathing / sway
	var sway := Vector3(sin(_t * 1.7) * 0.0025, sin(_t * 1.1 + 1.0) * 0.0035, 0.0) * (1.0 - 0.5 * clampf(move_speed, 0.0, 1.0))
	aim_p += sway
	var b_aim := Basis.looking_at(dir, Vector3.UP)
	var t_aim := Transform3D(b_aim, aim_p)
	# --- low ready (bobs while moving)
	var lp: Vector3 = spec.low
	var bob := clampf(move_speed / 2.5, 0.0, 1.2)
	lp += Vector3(sin(_t * 5.0) * 0.012 * bob, absf(sin(_t * 5.0)) * 0.018 * bob, 0.0) + sway
	var ld := Vector3(0.12, sin(spec.low_pitch), cos(spec.low_pitch)).normalized()
	var t_low := Transform3D(Basis.looking_at(ld, Vector3.UP), lp)
	return t_low.interpolate_with(t_aim, smoothstep(0.0, 1.0, _aim_w))

func _apply_recoil(w: Transform3D, pose_w: float) -> Transform3D:
	var gp: Vector3 = (w * m_grip).origin
	var b := w.basis
	var right := b.x
	var fwd := -b.z
	var pitch: float = _sx[0] * pose_w
	var roll: float = _sx[2] * pose_w
	var back: float = _sx[1] * pose_w
	var rot := Basis(right, pitch) * Basis(fwd, roll)
	var nb := rot * b
	var np := gp + rot * (w.origin - gp) - fwd * back
	return Transform3D(nb, np)

func _update_springs(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var steps := int(ceil(dt / 0.008))
	var h := dt / maxf(steps, 1)
	for s in steps:
		for i in 3:
			var a: float = -OMEGA * OMEGA * _sx[i] - 2.0 * OMEGA * _sv[i]
			_sv[i] += a * h
			_sx[i] += _sv[i] * h

func _update_parts(delta: float) -> void:
	# slide / pump: back in 0.03 s, forward in 0.07 s (pump waits 0.15 s after the shot, then cycles slower)
	if move_node:
		var tr: float = spec.travel
		var amt := 0.0
		if wid == "shotgun":
			var tt := _slide_t - 0.16
			if tt >= 0.0 and tt < 0.30:
				amt = sin(clampf(tt / 0.30, 0.0, 1.0) * PI)
		else:
			if _slide_t < 0.03:
				amt = _slide_t / 0.03
			elif _slide_t < 0.10:
				amt = 1.0 - (_slide_t - 0.03) / 0.07
			if _slide_lock:
				amt = 1.0 if _slide_t >= 0.10 or amt > 0.0 else amt
		move_node.position = _move_base + _move_dir * tr * amt
	_slide_t += delta
	if hammer_node:
		var k := 0.0
		if _slide_t < 0.06:
			k = _slide_t / 0.06
		elif _slide_t < 0.16:
			k = 1.0 - (_slide_t - 0.06) / 0.10
		hammer_node.basis = _hammer_base * Basis(Vector3.RIGHT, -k * 0.55)
	if cyl_node:
		_cyl_ang = lerpf(_cyl_ang, _cyl_target, clampf(delta * 14.0, 0.0, 1.0))
		cyl_node.basis = _cyl_base * Basis(_cyl_axis_local(), _cyl_ang)
	if _eject_timer >= 0.0:
		_eject_timer -= delta
		if _eject_timer < 0.0:
			_do_eject()

func _cyl_axis_local() -> Vector3:
	# the glb forward axis (-Z) in the cylinder's parent frame -> rotation axis (local coords, cylinder base orientation)
	var pb := _rel(cyl_node.get_parent() as Node3D, wmodel).basis
	return (_cyl_base.inverse() * pb.inverse() * Vector3(0, 0, -1)).normalized()

# ------------------------------------------------------------------ two-bone IK
func _excess(up: String, lo: String, hd: String, wrist_target: Vector3) -> float:
	var a: Vector3 = sk.get_bone_global_pose(_b[up]).origin
	var b: Vector3 = sk.get_bone_global_pose(_b[lo]).origin
	var c: Vector3 = sk.get_bone_global_pose(_b[hd]).origin
	var reach := a.distance_to(b) + b.distance_to(c)
	# approximate the wrist target as the palm point backed off by the anchor length along the weapon forward
	var d := a.distance_to(wrist_target) - ANCHOR_R.y
	return maxf(0.0, d - (reach - 0.02))

## target_palm: palm frame (skeleton space) = marker frame; the hand bone is placed so the anchor point sits on it.
func _ik_arm(side: String, target_palm: Transform3D, anchor: Vector3, pole: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var iu: int = _b["upperarm_" + side]; var il: int = _b["lowerarm_" + side]; var ih: int = _b["hand_" + side]
	if iu < 0 or il < 0 or ih < 0:
		return
	var q_u0 := sk.get_bone_pose_rotation(iu); var q_l0 := sk.get_bone_pose_rotation(il); var q_h0 := sk.get_bone_pose_rotation(ih)
	var hb := target_palm.basis.orthonormalized()
	var T := target_palm.origin - hb * anchor            # wrist target
	var gu := sk.get_bone_global_pose(iu)
	var gl := sk.get_bone_global_pose(il)
	var gh := sk.get_bone_global_pose(ih)
	var A := gu.origin; var B := gl.origin; var C := gh.origin
	var l1 := A.distance_to(B); var l2 := B.distance_to(C)
	var to := T - A
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.004)
	var dir := to.normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pv := pole - dir * pole.dot(dir)
	pv = pv.normalized() if pv.length() > 0.001 else Vector3.DOWN
	var E := A + dir * along + pv * hgt
	var Tc := A + dir * d
	# upper arm swing
	var q1 := _arc((B - A).normalized(), (E - A).normalized())
	sk.set_bone_global_pose(iu, Transform3D(Basis(q1) * gu.basis, A))
	gl = sk.get_bone_global_pose(il)
	gh = sk.get_bone_global_pose(ih)
	var q2 := _arc((gh.origin - gl.origin).normalized(), (Tc - gl.origin).normalized())
	var lb := Basis(q2) * gl.basis
	# forearm twist: take ~60% of the wrist roll so the hand does not candy-wrap
	var rel := (lb.inverse() * hb).get_rotation_quaternion()
	var tw := 2.0 * atan2(rel.y, rel.w)
	if tw > PI: tw -= TAU
	elif tw < -PI: tw += TAU
	lb = lb * Basis(Vector3.UP, tw * 0.6)
	sk.set_bone_global_pose(il, Transform3D(lb, gl.origin))
	gh = sk.get_bone_global_pose(ih)
	sk.set_bone_global_pose(ih, Transform3D(hb, gh.origin))
	if weight < 0.999:
		sk.set_bone_pose_rotation(iu, q_u0.slerp(sk.get_bone_pose_rotation(iu), weight))
		sk.set_bone_pose_rotation(il, q_l0.slerp(sk.get_bone_pose_rotation(il), weight))
		sk.set_bone_pose_rotation(ih, q_h0.slerp(sk.get_bone_pose_rotation(ih), weight))

static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var ax := a.cross(Vector3.UP)
		if ax.length() < 0.01:
			ax = a.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	var axis := a.cross(b).normalized()
	return Quaternion(axis, acos(d))

# ------------------------------------------------------------------ finger curls
func _prepare_curl_axes() -> void:
	for side in ["r", "l"]:
		var ih: int = _b.get("hand_" + side, -1)
		if ih < 0:
			continue
		var hrest := _global_rest(ih)
		var palm := hrest.basis.z
		for fi in FINGERS.size():
			for j in 3:
				var bi: int = _finger_bones[side][fi][j]
				if bi < 0:
					continue
				var grest := _global_rest(bi)
				var ax_g := grest.basis.y.cross(palm).normalized()
				_curl_axis[bi] = (grest.basis.inverse() * ax_g).normalized()
				_curl_rest[bi] = sk.get_bone_rest(bi).basis.get_rotation_quaternion()

func _global_rest(i: int) -> Transform3D:
	var t := sk.get_bone_rest(i)
	var p := sk.get_bone_parent(i)
	while p >= 0:
		t = sk.get_bone_rest(p) * t
		p = sk.get_bone_parent(p)
	return t

func _apply_curls(wr: float, wl: float) -> void:
	_curl_hand("r", spec.get("curl_r", []), wr)
	_curl_hand("l", spec.get("curl_l", []), wl)

func _curl_hand(side: String, amounts: Array, w: float) -> void:
	if amounts.is_empty() or w <= 0.001:
		return
	for fi in FINGERS.size():
		var ang := deg_to_rad(float(amounts[fi]))
		for j in 3:
			var bi: int = _finger_bones[side][fi][j]
			if bi < 0 or not _curl_axis.has(bi):
				continue
			var k := (0.55 if j == 0 else (1.0 if j == 1 else 0.8))
			if fi == 0:
				k = (1.0 if j == 0 else 0.7)
			var target: Quaternion = _curl_rest[bi] * Quaternion(_curl_axis[bi], ang * k)
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(target, w))

func _release_fingers() -> void:
	pass
