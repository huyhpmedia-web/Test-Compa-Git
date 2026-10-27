// Honey Farm Tycoon — single-file 3D playable (three.js global build)
(function () {
'use strict';
const $ = (id) => document.getElementById(id);
const rand = (a, b) => a + Math.random() * (b - a);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ---------- Config ----------
const CFG = {
  jarEvery: 2.6, hiveCap: 6, jarsPerCrate: 3, packTime: 1.4,
  cratePrice: 20, goal: 1000,
  carryCap: 6, speed: 6.2,
  custEvery: 6.5, patience: 28, maxQueue: 3,
  conveyorEvery: 1.1,
};

// ---------- Renderer / scene ----------
const canvas = $('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x9fdcff);
scene.fog = new THREE.Fog(0x9fdcff, 55, 110);
const camera = new THREE.PerspectiveCamera(42, 1, 0.5, 200);
const camOff = new THREE.Vector3(0, 24, 18);

scene.add(new THREE.HemisphereLight(0xffffff, 0xbfe59a, 1.9));
const sun = new THREE.DirectionalLight(0xfff0c8, 2.2);
sun.position.set(14, 26, 10);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -26, right: 26, top: 22, bottom: -22, near: 1, far: 80 });
scene.add(sun);

const M = (c, o) => new THREE.MeshStandardMaterial(Object.assign({ color: c, roughness: 0.85, metalness: 0 }, o));
function mesh(geo, mat, x, y, z, parent, shadow = true) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x || 0, y || 0, z || 0);
  m.castShadow = shadow; m.receiveShadow = true;
  if (parent) parent.add(m);
  return m;
}
const box = (w, h, d) => new THREE.BoxGeometry(w, h, d);
const cyl = (rt, rb, h, s = 20) => new THREE.CylinderGeometry(rt, rb, h, s);

function resize() {
  const w = innerWidth, h = innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.fov = w / h < 0.8 ? 70 : w / h < 1.2 ? 58 : 46; // keep the farm visible on portrait
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize); resize();

// ---------- World ----------
const ground = mesh(box(80, 1, 56), M(0x7ccf55), 0, -0.5, 0, scene, false);
for (let i = -3; i <= 3; i++) mesh(box(80, 0.02, 3.4), M(0x72c44d), 0, 0.01, i * 6.6, scene, false);
mesh(box(6, 0.1, 56), M(0x4b4f58), 18.5, 0.02, 0, scene, false);
for (let z = -26; z < 28; z += 4) mesh(box(0.25, 0.12, 2), M(0xf5e27a), 18.5, 0.04, z, scene, false);
mesh(box(2, 0.12, 56), M(0xd8c9a0), 14.5, 0.02, 0, scene, false);

function tree(x, z, s = 1) {
  const g = new THREE.Group(); g.position.set(x, 0, z); g.scale.setScalar(s);
  mesh(cyl(0.25, 0.35, 1.6, 8), M(0x7a5230), 0, 0.8, 0, g);
  mesh(new THREE.IcosahedronGeometry(1.4, 0), M(0x3f9f48), 0, 2.4, 0, g);
  mesh(new THREE.IcosahedronGeometry(1.0, 0), M(0x4cb356), 0.6, 3.2, 0.2, g);
  scene.add(g);
}
[[-24, -14], [-26, -4], [-24, 6], [-26, 14], [-17, -18], [-6, -19], [5, -19], [-14, 18], [-3, 19], [8, 18], [-21, 19], [14, -19]].forEach(p => tree(p[0], p[1], rand(0.9, 1.3)));
for (let x = -20; x <= 12; x += 2) mesh(box(0.15, 1, 0.15), M(0xb98b55), x, 0.5, -16.5, scene);
mesh(box(33, 0.12, 0.1), M(0xb98b55), -4, 0.75, -16.5, scene); mesh(box(33, 0.12, 0.1), M(0xb98b55), -4, 0.4, -16.5, scene);
const clouds = [];
for (let i = 0; i < 6; i++) {
  const c = new THREE.Group();
  for (let k = 0; k < 3; k++) mesh(new THREE.SphereGeometry(rand(1.5, 2.4), 10, 8), new THREE.MeshBasicMaterial({ color: 0xffffff }), k * 2 - 2, rand(0, 0.5), 0, c, false);
  c.position.set(rand(-40, 40), rand(14, 20), rand(-30, 0)); c.userData.sp = rand(0.3, 0.7);
  scene.add(c); clouds.push(c);
}
const flowerCols = [0xff6fa8, 0xffd23f, 0xffffff, 0xb78cff, 0xff8a3d];
const flowerGeo = new THREE.ConeGeometry(0.16, 0.34, 6), stemGeo = cyl(0.025, 0.025, 0.3, 4);
const flowers = [];
function flowerPatch(cx, cz, r, n) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, 6.28), d = Math.sqrt(Math.random()) * r;
    const g = new THREE.Group(); g.position.set(cx + Math.cos(a) * d, 0, cz + Math.sin(a) * d);
    mesh(stemGeo, M(0x2f8f3a), 0, 0.15, 0, g, false);
    const f = mesh(flowerGeo, M(flowerCols[i % 5]), 0, 0.42, 0, g, false); f.rotation.x = Math.PI;
    g.userData.ph = rand(0, 6); scene.add(g); flowers.push(g);
  }
}
flowerPatch(-16, -9, 3, 14); flowerPatch(-16, 9, 3, 14); flowerPatch(-3, -12, 3.5, 16); flowerPatch(8, 12, 3.5, 14); flowerPatch(-1, 13, 2.5, 10); flowerPatch(-18, 0, 2, 9); flowerPatch(5, -9, 2.5, 10);

// ---------- Text sprites ----------
function textSprite(txt, o = {}) {
  const cv = document.createElement('canvas'); cv.width = 256; cv.height = 128;
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(cv), transparent: true, depthTest: false }));
  sp.scale.set(o.w || 3, (o.w || 3) / 2, 1); sp.renderOrder = 10;
  sp.userData.set = (t, col) => {
    const c = cv.getContext('2d'); c.clearRect(0, 0, 256, 128);
    c.font = 'bold 64px system-ui,sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.lineWidth = 12; c.lineJoin = 'round'; c.strokeStyle = 'rgba(40,25,0,.85)'; c.strokeText(t, 128, 64);
    c.fillStyle = col || '#fff'; c.fillText(t, 128, 64); sp.material.map.needsUpdate = true;
  };
  sp.userData.set(txt, o.col); return sp;
}

// ---------- Item meshes ----------
const jarGeo = cyl(0.26, 0.26, 0.42, 14), lidGeo = cyl(0.28, 0.28, 0.08, 14);
const jarMat = M(0xffb21a, { emissive: 0x7a4300, emissiveIntensity: 0.35, roughness: 0.3 }), lidMat = M(0x8a5a2b);
function makeJar() { const g = new THREE.Group(); mesh(jarGeo, jarMat, 0, 0.21, 0, g); mesh(lidGeo, lidMat, 0, 0.46, 0, g); return g; }
const crateMat = M(0xc98d4e), crateTrim = M(0x8a5a2b);
function makeCrate() {
  const g = new THREE.Group();
  mesh(box(0.95, 0.5, 0.65), crateMat, 0, 0.25, 0, g);
  mesh(box(1, 0.08, 0.7), crateTrim, 0, 0.5, 0, g);
  for (let i = -1; i <= 1; i++) mesh(cyl(0.17, 0.17, 0.3, 10), jarMat, i * 0.28, 0.62, 0, g);
  return g;
}
const cashGeo = box(0.7, 0.14, 0.4), cashMat = M(0x58d36b, { emissive: 0x0b5a1b, emissiveIntensity: 0.4 });
function makeItem(type) { return type === 'jar' ? makeJar() : type === 'crate' ? makeCrate() : new THREE.Mesh(cashGeo, cashMat); }

// ---------- People ----------
function makePerson(shirt, hat) {
  const g = new THREE.Group(), body = new THREE.Group(); g.add(body);
  mesh(cyl(0.42, 0.5, 0.95, 14), M(shirt), 0, 0.75, 0, body);
  mesh(new THREE.SphereGeometry(0.4, 16, 12), M(0xffd2a8), 0, 1.5, 0, body);
  mesh(box(0.1, 0.1, 0.05), M(0x222222), -0.14, 1.55, 0.36, body, false);
  mesh(box(0.1, 0.1, 0.05), M(0x222222), 0.14, 1.55, 0.36, body, false);
  if (hat) { mesh(cyl(0.62, 0.62, 0.06, 18), M(0xf0c75a), 0, 1.8, 0, body); mesh(cyl(0.3, 0.34, 0.26, 14), M(0xf0c75a), 0, 1.95, 0, body); mesh(cyl(0.34, 0.34, 0.07, 14), M(0xc0392b), 0, 1.86, 0, body, false); }
  const armL = mesh(box(0.2, 0.6, 0.2), M(shirt), -0.58, 0.95, 0.1, body), armR = mesh(box(0.2, 0.6, 0.2), M(shirt), 0.58, 0.95, 0.1, body);
  g.userData = { body, armL, armR };
  return g;
}
const farmer = makePerson(0x3b82f6, true);
farmer.position.set(2, 0, 4); scene.add(farmer);
const carryGroup = new THREE.Group(); carryGroup.position.set(0, 0.7, -0.65); farmer.add(carryGroup);
const carry = [];
const carryCap = () => CFG.carryCap;
const countCarry = (t) => carry.filter(c => c.type === t).length;
function relayoutCarry() { let y = 0; carry.forEach((it) => { it.obj.position.set(0, y, 0); y += it.type === 'jar' ? 0.5 : 0.56; }); }
function addCarry(type) { const obj = makeItem(type); carryGroup.add(obj); carry.push({ type, obj }); relayoutCarry(); pop(obj); beep(type === 'jar' ? 640 : 520, 0.05); updateHud(); }
function takeCarry(type) {
  for (let i = carry.length - 1; i >= 0; i--) if (carry[i].type === type) { const it = carry.splice(i, 1)[0]; carryGroup.remove(it.obj); relayoutCarry(); updateHud(); return true; }
  return false;
}
const tweens = [];
function easeOutBack(x) { const c1 = 1.7, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); }
function pop(obj) { tweens.push({ t: 0, d: 0.22, f: (k) => obj.scale.setScalar(0.2 + 0.8 * easeOutBack(k)) }); }
function flyItem(type, from, to, done) {
  const o = makeItem(type); scene.add(o); o.position.copy(from);
  const a = from.clone(), b = to.clone();
  tweens.push({ t: 0, d: 0.35, f: (k) => { o.position.lerpVectors(a, b, k); o.position.y += Math.sin(k * Math.PI) * 1.2; }, end: () => { scene.remove(o); done && done(); } });
}
const farmerWorld = (y = 1.2) => farmer.position.clone().setY(y);

// ---------- State ----------
const S = { money: 0, earned: 0, jarsInMachine: 0, packTimer: 0, outCrates: 0, cash: 0, time: 0, custTimer: 2.5, delivered: 0, won: false, started: false, conveyor: false };
const HIVE_POS = [[-11, -3], [-11, 3.5], [-7, -7], [-7, 8]];
const MACHINE = new THREE.Vector3(-1, 0, 0), IN_ZONE = new THREE.Vector3(-4.2, 0, 0.2), OUT_ZONE = new THREE.Vector3(2.4, 0, 2.6);
const COUNTER = new THREE.Vector3(10.4, 0, -0.6), SERVE_ZONE = new THREE.Vector3(7.6, 0, -0.6), CASH_ZONE = new THREE.Vector3(9.4, 0, -5.4);

function ring(pos, r, col) {
  const g = new THREE.Group(); g.position.set(pos.x, 0.06, pos.z);
  const m = new THREE.Mesh(new THREE.RingGeometry(r - 0.16, r, 40), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.8, side: THREE.DoubleSide }));
  m.rotation.x = -Math.PI / 2; g.add(m);
  const f = new THREE.Mesh(new THREE.CircleGeometry(r - 0.16, 40), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.18, side: THREE.DoubleSide }));
  f.rotation.x = -Math.PI / 2; f.position.y = -0.01; g.add(f); scene.add(g); return g;
}

// ---------- Hives ----------
function makeHiveMesh(mat) {
  const g = new THREE.Group(); const m = (c) => mat || M(c);
  mesh(box(1.8, 0.3, 1.8), m(0x9b6b3a), 0, 0.15, 0, g);
  [0xffc93c, 0xffb21a, 0xffc93c].forEach((c, i) => mesh(box(1.5, 0.5, 1.5), m(c), 0, 0.55 + i * 0.52, 0, g));
  mesh(box(1.7, 0.18, 1.7), m(0xd94f3d), 0, 2.2, 0, g); mesh(box(1.2, 0.18, 1.2), m(0xd94f3d), 0, 2.35, 0, g);
  mesh(box(0.35, 0.18, 0.1), m(0x3a2410), 0, 0.5, 0.78, g, false);
  return g;
}
function makeBee() {
  const b = new THREE.Group();
  mesh(new THREE.SphereGeometry(0.13, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd21a }), 0, 0, 0, b, false);
  mesh(new THREE.SphereGeometry(0.1, 8, 6), new THREE.MeshBasicMaterial({ color: 0x222222 }), 0.1, 0, 0, b, false);
  mesh(box(0.02, 0.01, 0.2), new THREE.MeshBasicMaterial({ color: 0xffffff }), 0, 0.1, 0, b, false);
  return b;
}
const hives = [], bees = [];
const ghostMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.2, depthWrite: false });
HIVE_POS.forEach((p, i) => {
  const h = { i, x: p[0], z: p[1], unlocked: i === 0, jars: 0, timer: 0, g: new THREE.Group(), jarObjs: [], pos: new THREE.Vector3(p[0], 0, p[1]) };
  h.g.position.set(p[0], 0, p[1]); h.g.add(makeHiveMesh()); scene.add(h.g);
  h.ring = ring(h.pos, 2.6, 0xffd23f);
  h.ghost = makeHiveMesh(ghostMat); h.ghost.position.set(p[0], 0, p[1]); scene.add(h.ghost);
  h.cap = textSprite('0/6', { w: 2.4 }); h.cap.position.set(p[0], 3.4, p[1]); scene.add(h.cap);
  for (let k = 0; k < 4; k++) { const b = makeBee(); b.userData = { a: rand(0, 6), r: rand(1.4, 2.4), s: rand(1.5, 2.8), y: rand(1.2, 2.6) }; scene.add(b); bees.push({ b, h }); }
  hives.push(h);
});
function applyHiveVisibility(h) { h.g.visible = h.unlocked; h.ring.visible = h.unlocked; h.cap.visible = h.unlocked; h.ghost.visible = !h.unlocked; }
function refreshHive(h) {
  h.jarObjs.forEach(o => h.g.remove(o)); h.jarObjs = [];
  for (let i = 0; i < h.jars; i++) { const j = makeJar(); j.position.set(-1.2 + i * 0.48, 0, 1.45); h.g.add(j); h.jarObjs.push(j); }
  h.cap.userData.set(h.jars + '/' + CFG.hiveCap, h.jars >= CFG.hiveCap ? '#ff9a9a' : '#ffe9a3');
}

// ---------- Packing machine ----------
const machine = new THREE.Group(); machine.position.copy(MACHINE); scene.add(machine);
mesh(box(3.4, 1.6, 2.4), M(0x5c6bc0), 0, 0.8, 0, machine);
mesh(box(3.5, 0.2, 2.5), M(0x3949ab), 0, 1.65, 0, machine);
mesh(box(1.2, 0.8, 1.2), M(0x303f9f), -0.6, 2.1, 0, machine);
mesh(cyl(0.18, 0.18, 1.2, 10), M(0x9fa8da), 0.9, 2.2, 0.4, machine);
const gauge = mesh(box(0.3, 0.3, 0.05), M(0x66ff99, { emissive: 0x22aa55 }), -0.5, 1.2, 1.22, machine, false);
const gear = mesh(cyl(0.45, 0.45, 0.15, 8), M(0xffc107), 0.8, 1.0, 1.23, machine, false); gear.rotation.x = Math.PI / 2;
ring(IN_ZONE, 1.7, 0x6ec6ff); ring(OUT_ZONE, 1.7, 0xffffff);
const outLabel = textSprite('CRATES', { w: 2.6 }); outLabel.position.set(OUT_ZONE.x, 2.6, OUT_ZONE.z); scene.add(outLabel);
const inLabel = textSprite('JARS IN', { w: 2.6, col: '#bfe6ff' }); inLabel.position.set(IN_ZONE.x, 2.0, IN_ZONE.z); scene.add(inLabel);
const machineLabel = textSprite('0/3', { w: 2.4 }); machineLabel.position.set(MACHINE.x, 3.7, MACHINE.z); scene.add(machineLabel);
const outPile = new THREE.Group(); outPile.position.copy(OUT_ZONE); scene.add(outPile);
let outObjs = [];
function refreshOut() {
  outObjs.forEach(o => outPile.remove(o)); outObjs = [];
  for (let i = 0; i < Math.min(S.outCrates, 12); i++) { const c = makeCrate(); c.position.set(((i % 2) - 0.5) * 1.1, Math.floor(i / 2) * 0.55, 0); outPile.add(c); outObjs.push(c); }
  outLabel.userData.set(S.outCrates ? 'x' + S.outCrates : 'CRATES', '#fff');
}
function refreshMachine() { machineLabel.userData.set(S.jarsInMachine + '/' + CFG.jarsPerCrate, '#bfe6ff'); }

// ---------- Shop ----------
const shop = new THREE.Group(); shop.position.copy(COUNTER); scene.add(shop);
mesh(box(2.2, 1.4, 6.4), M(0xe9d6b0), 0, 0.7, 0, shop);
mesh(box(2.6, 0.18, 6.8), M(0xb5651d), 0, 1.45, 0, shop);
for (let i = 0; i < 7; i++) mesh(box(2.8, 0.1, 0.95), M(i % 2 ? 0xffffff : 0xe53935), 0, 3.6 - i * 0.0, -3.15 + i * 1.0, shop).rotation.z = 0.0;
[-3.1, 3.1].forEach(z => mesh(box(0.15, 2.2, 0.15), M(0x8a5a2b), -0.9, 2.5, z, shop));
const sign = mesh(box(0.2, 0.9, 4.2), M(0xffd23f, { emissive: 0x806000, emissiveIntensity: 0.4 }), 0.6, 4.4, 0, shop);
for (let i = 0; i < 5; i++) { const j = makeJar(); j.position.set(0, 1.55, -2.2 + i * 1.0); shop.add(j); }
ring(SERVE_ZONE, 1.7, 0x7dff8a); ring(CASH_ZONE, 1.5, 0x58d36b);
const srvLabel = textSprite('SELL', { w: 2.2, col: '#caffcf' }); srvLabel.position.set(SERVE_ZONE.x, 2.0, SERVE_ZONE.z); scene.add(srvLabel);
const cashPile = new THREE.Group(); cashPile.position.copy(CASH_ZONE); scene.add(cashPile);
const cashLabel = textSprite('$0', { w: 2.4, col: '#aaffb5' }); cashLabel.position.set(CASH_ZONE.x, 2.6, CASH_ZONE.z); scene.add(cashLabel);
let cashObjs = [];
function refreshCash() {
  cashObjs.forEach(o => cashPile.remove(o)); cashObjs = [];
  for (let i = 0; i < Math.min(Math.ceil(S.cash / 8), 18); i++) { const c = new THREE.Mesh(cashGeo, cashMat); c.castShadow = true; c.position.set(((i % 2) - 0.5) * 0.8, 0.08 + Math.floor(i / 2) * 0.16, ((i % 3) - 1) * 0.1); c.rotation.y = (i % 3 - 1) * 0.25; cashPile.add(c); cashObjs.push(c); }
  cashLabel.userData.set('$' + S.cash, '#aaffb5'); cashLabel.visible = S.cash > 0;
}
const conveyor = new THREE.Group(); conveyor.visible = false; scene.add(conveyor);
mesh(box(7.4, 0.3, 1.1), M(0x39414d), -8, 0.2, -2.2, conveyor);
const beltStripes = [];
for (let i = 0; i < 14; i++) beltStripes.push(mesh(box(0.2, 0.05, 0.95), M(0xffc107), -11.5 + i * 0.5, 0.38, -2.2, conveyor, false));

// ---------- Upgrade pads ----------
const PADS = [
  { label: 'Hive #2', price: 25, x: -11, z: 8.5, show: () => true, apply: () => { hives[1].unlocked = true; applyHiveVisibility(hives[1]); } },
  { label: 'Boots', price: 60, x: 0.5, z: 8.8, show: () => true, apply: () => { CFG.speed += 1.6; toast('Faster boots! 👟'); } },
  { label: 'Hive #3', price: 90, x: -7, z: -11.5, show: () => hives[1].unlocked, apply: () => { hives[2].unlocked = true; applyHiveVisibility(hives[2]); } },
  { label: 'Conveyor', price: 140, x: -6.5, z: 4.8, show: () => hives[1].unlocked, apply: () => { S.conveyor = true; conveyor.visible = true; toast('Conveyor belt online! ⚙️ Jars now travel by themselves'); } },
  { label: '+3 Carry', price: 180, x: 5, z: 8.8, show: () => hives[1].unlocked, apply: () => { CFG.carryCap += 3; toast('Bigger stack! 📦'); updateHud(); } },
  { label: 'Hive #4', price: 320, x: -7, z: 12.5, show: () => hives[2].unlocked, apply: () => { hives[3].unlocked = true; applyHiveVisibility(hives[3]); } },
];
PADS.forEach((p) => {
  p.paid = 0; p.done = false; p.pos = new THREE.Vector3(p.x, 0, p.z); p.g = new THREE.Group(); p.g.position.copy(p.pos); scene.add(p.g);
  const base = new THREE.Mesh(cyl(1.5, 1.5, 0.12, 32), new THREE.MeshStandardMaterial({ color: 0x2b2b2b, roughness: 0.9, transparent: true, opacity: 0.8 }));
  base.position.y = 0.06; p.g.add(base);
  p.fill = new THREE.Mesh(cyl(1.5, 1.5, 0.14, 32), new THREE.MeshBasicMaterial({ color: 0x58d36b }));
  p.fill.position.y = 0.07; p.fill.scale.set(0.001, 1, 0.001); p.g.add(p.fill);
  const rg = new THREE.Mesh(new THREE.RingGeometry(1.35, 1.55, 40), new THREE.MeshBasicMaterial({ color: 0xffe066, side: THREE.DoubleSide }));
  rg.rotation.x = -Math.PI / 2; rg.position.y = 0.16; p.g.add(rg);
  p.name = textSprite(p.label, { w: 3.2 }); p.name.position.set(0, 2.5, 0); p.g.add(p.name);
  p.cost = textSprite('$' + p.price, { w: 2.6, col: '#ffe066' }); p.cost.position.set(0, 1.5, 0); p.g.add(p.cost);
});
function padStatus() { PADS.forEach(p => { p.g.visible = !p.done && p.show(); }); }

// ---------- Customers ----------
const customers = [];
const QUEUE = [[13.6, -0.6], [13.6, 1.9], [13.6, 4.4]].map(a => new THREE.Vector3(a[0], 0, a[1]));
const shirtCols = [0xe91e63, 0x9c27b0, 0x00bcd4, 0xff9800, 0x8bc34a, 0xf44336];
function spawnCustomer() {
  if (customers.filter(c => !c.leaving).length >= CFG.maxQueue) return;
  const g = makePerson(shirtCols[Math.floor(Math.random() * shirtCols.length)], false);
  g.position.set(21, 0, 8); scene.add(g);
  const want = S.delivered < 3 ? 1 : Math.random() < 0.65 ? 1 : 2;
  const bub = textSprite('', { w: 2.8 }); bub.position.set(0, 3.4, 0); g.add(bub);
  const barBg = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.22), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.6, depthTest: false })); barBg.position.set(0, 2.55, 0); barBg.renderOrder = 11; g.add(barBg);
  const bar = new THREE.Mesh(new THREE.PlaneGeometry(1.44, 0.16), new THREE.MeshBasicMaterial({ color: 0x58d36b, depthTest: false })); bar.position.set(0, 2.55, 0.01); bar.renderOrder = 12; g.add(bar);
  const c = { g, want, got: 0, pat: CFG.patience, maxPat: CFG.patience, state: 'arrive', bub, bar, barBg, leaving: false, slot: 0 };
  setBubble(c); customers.push(c); assignSlots();
}
function setBubble(c) { c.bub.userData.set('📦 x' + (c.want - c.got), '#fff'); }
function assignSlots() { let n = 0; customers.forEach(c => { if (!c.leaving) c.slot = n++; }); }
function hideBars(c) { c.bar.visible = false; c.barBg.visible = false; }
function serveCustomer(c) {
  c.leaving = true; c.state = 'leave'; c.bub.visible = false; hideBars(c);
  const gain = c.want * CFG.cratePrice + (c.pat > c.maxPat * 0.5 ? c.want * 5 : 0);
  S.cash += gain; S.earned += gain; S.delivered++;
  flyItem('cash', c.g.position.clone().setY(1.5), CASH_ZONE.clone().setY(1), refreshCash);
  float('+$' + gain, c.g.position, '#aaffb5'); beep(880, 0.08); setTimeout(() => beep(1100, 0.08), 80);
  assignSlots(); updateHud();
}
function angryLeave(c) { c.leaving = true; c.state = 'leave'; c.bub.userData.set('😡', '#fff'); hideBars(c); beep(180, 0.2); assignSlots(); }

// ---------- Float text / toast ----------
const floats = [];
function float(txt, pos, col) { const s = textSprite(txt, { w: 2.6, col }); s.position.copy(pos).setY(3.2); scene.add(s); floats.push({ s, t: 0 }); }
let toastT = 0; function toast(t) { const e = $('toast'); e.textContent = t; e.style.opacity = 1; toastT = 2.4; }

// ---------- Audio ----------
let actx = null;
function beep(f, d = 0.08, type = 'triangle', vol = 0.06) {
  try {
    if (!actx) actx = new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), g = actx.createGain(); o.type = type; o.frequency.value = f;
    g.gain.setValueAtTime(vol, actx.currentTime); g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + d);
    o.connect(g); g.connect(actx.destination); o.start(); o.stop(actx.currentTime + d);
  } catch (e) { }
}

// ---------- Input ----------
const keys = {};
addEventListener('keydown', e => { keys[e.key.toLowerCase()] = true; start(); });
addEventListener('keyup', e => { keys[e.key.toLowerCase()] = false; });
const joy = { on: false, id: -1, sx: 0, sy: 0, dx: 0, dy: 0 };
const joyEl = $('joy'), knob = $('knob');
canvas.addEventListener('pointerdown', e => {
  start(); joy.on = true; joy.id = e.pointerId; joy.sx = e.clientX; joy.sy = e.clientY; joy.dx = joy.dy = 0;
  joyEl.style.display = 'block'; joyEl.style.left = e.clientX - 55 + 'px'; joyEl.style.top = e.clientY - 55 + 'px'; knob.style.transform = 'translate(0,0)';
  try { canvas.setPointerCapture(e.pointerId); } catch (x) { }
});
canvas.addEventListener('pointermove', e => {
  if (!joy.on || e.pointerId !== joy.id) return;
  let dx = e.clientX - joy.sx, dy = e.clientY - joy.sy; const l = Math.hypot(dx, dy), m = 50;
  if (l > m) { dx = dx / l * m; dy = dy / l * m; }
  joy.dx = dx / m; joy.dy = dy / m; knob.style.transform = `translate(${dx}px,${dy}px)`;
});
const endJoy = e => { if (e.pointerId === joy.id) { joy.on = false; joy.dx = joy.dy = 0; joyEl.style.display = 'none'; } };
canvas.addEventListener('pointerup', endJoy); canvas.addEventListener('pointercancel', endJoy);
function start() { if (!S.started) { S.started = true; $('intro').style.display = 'none'; } if (actx && actx.state === 'suspended') actx.resume(); }
$('play').addEventListener('click', () => { start(); beep(660, 0.1); });

// ---------- Objective arrow ----------
const arrow = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.0, 4), new THREE.MeshBasicMaterial({ color: 0xffffff }));
arrow.rotation.x = Math.PI; scene.add(arrow);
const guide = new THREE.Mesh(new THREE.PlaneGeometry(0.28, 1), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55, depthWrite: false }));
guide.rotation.order = 'YXZ'; scene.add(guide);
function objective() {
  const free = carryCap() - carry.length, hasCust = customers.some(c => !c.leaving && c.state === 'wait');
  const hiveWithJars = hives.some(h => h.unlocked && h.jars > 0);
  if (countCarry('crate') > 0 && hasCust) return { p: SERVE_ZONE, h: 2.8, t: 'Deliver the crates to the counter' };
  if (S.cash > 0) return { p: CASH_ZONE, h: 2.8, t: 'Grab the cash!' };
  if (countCarry('jar') > 0 && (free === 0 || !hiveWithJars)) return { p: IN_ZONE, h: 2.8, t: 'Bring the jars to the packing machine' };
  if (S.outCrates > 0 && free > 0) return { p: OUT_ZONE, h: 3.2, t: 'Pick up the packed crates' };
  if (countCarry('crate') > 0) return { p: SERVE_ZONE, h: 2.8, t: 'Take the crates to the counter' };
  let best = null; hives.forEach(h => { if (h.unlocked && h.jars > 0 && free > 0 && (!best || h.jars > best.jars)) best = h; });
  if (best) return { p: best.pos, h: 3.9, t: 'Collect honey jars from the hive' };
  if (countCarry('jar') > 0) return { p: IN_ZONE, h: 2.8, t: 'Bring the jars to the packing machine' };
  let pad = null; PADS.forEach(p => { if (!p.done && p.g.visible && S.money >= 1 && (!pad || p.price < pad.price)) pad = p; });
  if (pad) return { p: pad.pos, h: 3.4, t: 'Spend your cash: ' + pad.label };
  return null;
}

// ---------- Update ----------
const tmp = new THREE.Vector3();
let zoneTick = 0, convTimer = 0;
const inZone = (pos, r) => Math.hypot(farmer.position.x - pos.x, farmer.position.z - pos.z) < r;
function walkAnim(g, t, mv) {
  const u = g.userData; u.body.position.y = mv ? Math.abs(Math.sin(t * 11)) * 0.08 : 0;
  u.armL.rotation.x = mv ? Math.sin(t * 11) * 0.7 : 0; u.armR.rotation.x = mv ? -Math.sin(t * 11) * 0.7 : 0;
}

function update(dt) {
  S.time += dt;
  let mx = 0, mz = 0;
  if (keys['a'] || keys['arrowleft']) mx -= 1; if (keys['d'] || keys['arrowright']) mx += 1;
  if (keys['w'] || keys['arrowup']) mz -= 1; if (keys['s'] || keys['arrowdown']) mz += 1;
  if (joy.on) { mx += joy.dx; mz += joy.dy; }
  const ml = Math.hypot(mx, mz); let moving = false;
  if (ml > 0.08 && S.started) {
    const k = Math.min(1, ml); mx /= ml; mz /= ml; moving = true;
    const sp = CFG.speed * (1 - 0.02 * carry.length) * k;
    farmer.position.x = clamp(farmer.position.x + mx * sp * dt, -22, 14);
    farmer.position.z = clamp(farmer.position.z + mz * sp * dt, -15, 14.5);
    const dx = farmer.position.x - MACHINE.x, dz = farmer.position.z - MACHINE.z;
    if (Math.abs(dx) < 2.3 && Math.abs(dz) < 1.9) { if (Math.abs(dz) / 1.9 > Math.abs(dx) / 2.3) farmer.position.z = MACHINE.z + (dz < 0 ? -1.9 : 1.9); else farmer.position.x = MACHINE.x + (dx < 0 ? -2.3 : 2.3); }
    if (farmer.position.x > COUNTER.x - 1.7 && Math.abs(farmer.position.z - COUNTER.z) < 3.5) farmer.position.x = COUNTER.x - 1.7;
    const ta = Math.atan2(mx, mz); let da = ta - farmer.rotation.y; da = Math.atan2(Math.sin(da), Math.cos(da)); farmer.rotation.y += da * Math.min(1, dt * 14);
  }
  walkAnim(farmer, S.time, moving);
  if (carry.length) { farmer.userData.armL.rotation.x = -1.2; farmer.userData.armR.rotation.x = -1.2; }
  if (!S.started) return;

  hives.forEach(h => { if (h.unlocked && h.jars < CFG.hiveCap) { h.timer += dt; if (h.timer >= CFG.jarEvery) { h.timer = 0; h.jars++; refreshHive(h); } } });

  if (S.jarsInMachine >= CFG.jarsPerCrate) {
    S.packTimer += dt; gear.rotation.z += dt * 8; gauge.material.color.set(0xffcc33);
    if (S.packTimer >= CFG.packTime) { S.packTimer = 0; S.jarsInMachine -= CFG.jarsPerCrate; S.outCrates++; refreshOut(); refreshMachine(); beep(420, 0.12, 'square', 0.04); pop(machine); }
  } else gauge.material.color.set(0x66ff99);

  zoneTick -= dt;
  if (zoneTick <= 0) {
    zoneTick = 0.12;
    for (const h of hives) { if (h.unlocked && h.jars > 0 && carry.length < carryCap() && inZone(h.pos, 2.6)) { h.jars--; refreshHive(h); addCarry('jar'); break; } }
    if (inZone(IN_ZONE, 1.8) && countCarry('jar') > 0 && S.jarsInMachine < CFG.jarsPerCrate * 2) {
      takeCarry('jar'); flyItem('jar', farmerWorld(1.3), MACHINE.clone().setY(2.2), () => { S.jarsInMachine++; refreshMachine(); }); beep(500, 0.05);
    }
    if (inZone(OUT_ZONE, 1.8) && S.outCrates > 0 && carry.length < carryCap()) { S.outCrates--; refreshOut(); addCarry('crate'); }
    if (inZone(SERVE_ZONE, 1.9) && countCarry('crate') > 0) {
      const c = customers.find(c => !c.leaving && c.state === 'wait' && c.got < c.want);
      if (c) { takeCarry('crate'); c.got++; flyItem('crate', farmerWorld(1.4), c.g.position.clone().setY(1.5)); if (c.got >= c.want) serveCustomer(c); else setBubble(c); }
    }
    if (inZone(CASH_ZONE, 1.7) && S.cash > 0) {
      const take = Math.min(S.cash, Math.max(5, Math.ceil(S.cash / 3)));
      S.cash -= take; S.money += take; refreshCash(); beep(980, 0.05);
      flyItem('cash', CASH_ZONE.clone().setY(1), farmerWorld(1.6)); updateHud(true);
    }
  }

  PADS.forEach(p => {
    if (p.done || !p.g.visible) return;
    if (inZone(p.pos, 1.6) && S.money >= 1) {
      const amt = Math.floor(Math.min(S.money, p.price - p.paid, Math.max(1, p.price * 1.8 * dt)));
      if (amt > 0) {
        S.money -= amt; p.paid += amt; updateHud(); if (Math.random() < 0.5) beep(500 + p.paid * 4, 0.03, 'square', 0.02);
        p.cost.userData.set('$' + (p.price - p.paid), '#ffe066');
        const k = p.paid / p.price; p.fill.scale.set(k, 1, k);
        if (p.paid >= p.price) { p.done = true; p.apply(); float(p.label + ' unlocked!', p.pos, '#ffe066'); beep(523, .12); setTimeout(() => beep(784, .15), 110); setTimeout(() => beep(1047, .2), 230); padStatus(); }
      }
    }
  });

  if (S.conveyor) {
    convTimer += dt;
    beltStripes.forEach(s => { s.position.x += dt * 1.6; if (s.position.x > -4.6) s.position.x -= 7.0; });
    if (convTimer >= CFG.conveyorEvery && S.jarsInMachine < CFG.jarsPerCrate * 2) {
      let best = null; hives.forEach(h => { if (h.unlocked && h.jars > 0 && (!best || h.jars > best.jars)) best = h; });
      if (best) { convTimer = 0; best.jars--; refreshHive(best); flyItem('jar', new THREE.Vector3(best.x, 1.5, best.z), new THREE.Vector3(MACHINE.x, 2.2, MACHINE.z), () => { S.jarsInMachine++; refreshMachine(); }); }
    }
  }

  S.custTimer -= dt;
  if (S.custTimer <= 0) { S.custTimer = CFG.custEvery * (S.delivered < 3 ? 0.7 : 1) * rand(0.8, 1.2); spawnCustomer(); }
  for (let i = customers.length - 1; i >= 0; i--) {
    const c = customers[i], g = c.g;
    if (c.state === 'leave') {
      g.position.x += 5 * dt; g.position.z += 2.2 * dt; g.rotation.y = Math.PI / 2; walkAnim(g, S.time + i, true);
      if (g.position.x > 24) { scene.remove(g); customers.splice(i, 1); }
      continue;
    }
    tmp.copy(QUEUE[c.slot] || QUEUE[0]).sub(g.position); tmp.y = 0; const d = tmp.length();
    if (d > 0.1) { tmp.normalize(); g.position.addScaledVector(tmp, Math.min(d, 4.5 * dt)); g.rotation.y = Math.atan2(tmp.x, tmp.z); walkAnim(g, S.time + i, true); }
    else { g.rotation.y = -Math.PI / 2; walkAnim(g, 0, false); if (c.state === 'arrive') c.state = 'wait'; }
    if (c.state === 'wait') {
      c.pat -= dt * (S.delivered < 2 ? 0.4 : 1);
      const k = clamp(c.pat / c.maxPat, 0, 1);
      c.bar.scale.x = Math.max(0.001, k); c.bar.position.x = -0.72 * (1 - k);
      c.bar.material.color.set(k > 0.5 ? 0x58d36b : k > 0.25 ? 0xffc83d : 0xff4d4d);
      if (c.pat <= 0) angryLeave(c);
    }
  }

  if (!S.won && S.earned >= CFG.goal) { S.won = true; showWin(); }

  const o = objective();
  if (o) {
    arrow.visible = true; arrow.position.set(o.p.x, o.h + Math.sin(S.time * 5) * 0.25, o.p.z); arrow.rotation.y += dt * 3;
    const dx = o.p.x - farmer.position.x, dz = o.p.z - farmer.position.z, dist = Math.hypot(dx, dz);
    guide.visible = dist > 4;
    if (guide.visible) { const len = dist - 3; guide.scale.set(1, len, 1); guide.rotation.set(-Math.PI / 2, Math.atan2(-dx, -dz), 0); guide.position.set(farmer.position.x + dx / dist * (len / 2 + 1), 0.14, farmer.position.z + dz / dist * (len / 2 + 1)); }
    $('hint').textContent = o.t; $('hint').style.opacity = 1;
  } else { arrow.visible = false; guide.visible = false; $('hint').style.opacity = 0; }
}

// ---------- HUD ----------
function updateHud(bump) {
  $('money').textContent = '$' + Math.floor(S.money);
  $('fill').style.width = Math.min(100, S.earned / CFG.goal * 100) + '%';
  $('goalTxt').textContent = '$' + Math.min(S.earned, CFG.goal) + ' / $' + CFG.goal;
  $('carryTxt').textContent = carry.length + '/' + carryCap();
  if (bump) { const m = $('moneyBox'); m.classList.remove('bump'); void m.offsetWidth; m.classList.add('bump'); }
}
function showWin() {
  $('winStats').textContent = 'You served ' + S.delivered + ' customers and earned $' + S.earned + '!';
  $('win').style.display = 'flex';
  [523, 659, 784, 1047].forEach((f, i) => setTimeout(() => beep(f, i === 3 ? 0.4 : 0.15), i * 150));
}
$('cont').addEventListener('click', () => { $('win').style.display = 'none'; });
$('again').addEventListener('click', () => location.reload());

// ---------- Boot ----------
hives[0].jars = 3;
hives.forEach(h => { applyHiveVisibility(h); refreshHive(h); });
refreshMachine(); refreshOut(); refreshCash(); padStatus(); updateHud();

const clock = new THREE.Clock();
function frame() {
  const dt = Math.min(clock.getDelta(), 0.05);
  update(dt);
  for (let i = tweens.length - 1; i >= 0; i--) { const t = tweens[i]; t.t += dt; const k = Math.min(1, t.t / t.d); t.f(k); if (k >= 1) { t.end && t.end(); tweens.splice(i, 1); } }
  for (let i = floats.length - 1; i >= 0; i--) { const f = floats[i]; f.t += dt; f.s.position.y += dt * 1.5; f.s.material.opacity = Math.max(0, 1 - f.t / 1.2); if (f.t > 1.2) { scene.remove(f.s); floats.splice(i, 1); } }
  if (toastT > 0) { toastT -= dt; if (toastT <= 0) $('toast').style.opacity = 0; }
  const now = performance.now() / 1000;
  clouds.forEach(c => { c.position.x += c.userData.sp * dt; if (c.position.x > 50) c.position.x = -50; });
  flowers.forEach(f => { f.rotation.z = Math.sin(now * 1.6 + f.userData.ph) * 0.08; });
  bees.forEach(o => { const u = o.b.userData; u.a += u.s * dt; o.b.position.set(o.h.x + Math.cos(u.a) * u.r, u.y + Math.sin(u.a * 2) * 0.25, o.h.z + Math.sin(u.a) * u.r); o.b.rotation.y = -u.a; o.b.visible = o.h.unlocked; });
  PADS.forEach(p => { if (p.g.visible) p.name.position.y = 2.5 + Math.sin(now * 3) * 0.08; });
  sign.material.emissiveIntensity = 0.3 + Math.sin(now * 3) * 0.15;
  const tx = clamp(farmer.position.x * 0.8, -12, 9), tz = clamp(farmer.position.z * 0.55, -6, 6);
  tmp.set(tx, 0, tz).add(camOff);
  camera.position.lerp(tmp, Math.min(1, dt * 4));
  camera.lookAt(camera.position.x, 0, camera.position.z - camOff.z);
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
camera.position.set(-1, camOff.y, camOff.z + 2);
frame();
window.__game = { S, CFG, hives, farmer, PADS, carry, customers, update, keys, QUEUE, SERVE_ZONE, CASH_ZONE, IN_ZONE, OUT_ZONE };
})();
