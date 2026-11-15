import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

// Gray Hexagonal Ring (60-deg step order, 1 bit flip per adjacent step)
const GRAY_RING = [0b001, 0b011, 0b010, 0b110, 0b111, 0b101];

// Full 8-state catalog of 3-bit Gray Hexagonal encoding
const STATE_TABLE = {
  0b000: { code: "3'b000", short: "000", role: "center", angle: null, qrs: [0, 0, 0], pos2d: [0, 0] },
  0b001: { code: "3'b001", short: "001", role: "ring", angle: 0, qrs: [1, 0, -1], pos2d: [1, 0] },
  0b011: { code: "3'b011", short: "011", role: "ring", angle: 60, qrs: [0, 1, -1], pos2d: [0.5, 0.866] },
  0b010: { code: "3'b010", short: "010", role: "ring", angle: 120, qrs: [-1, 1, 0], pos2d: [-0.5, 0.866] },
  0b110: { code: "3'b110", short: "110", role: "ring", angle: 180, qrs: [-1, 0, 1], pos2d: [-1, 0] },
  0b111: { code: "3'b111", short: "111", role: "ring", angle: 240, qrs: [0, -1, 1], pos2d: [-0.5, -0.866] },
  0b101: { code: "3'b101", short: "101", role: "ring", angle: 300, qrs: [1, -1, 0], pos2d: [0.5, -0.866] },
  0b100: { code: "3'b100", short: "100", role: "sentinel", angle: null, qrs: null, pos2d: null },
};

const COLOR_GOLD = new THREE.Color(0xdca93e);
const COLOR_CYAN = new THREE.Color(0x38bdf8);
const COLOR_EMERALD = new THREE.Color(0x34d399);
const COLOR_FAULT = new THREE.Color(0xff4d6d);
const COLOR_DIM = new THREE.Color(0x334155);

const state = {
  currentCode: 0b001,
  prevCode: 0b001,
  changedMask: 0b000,
  flashTimer: 0,
  autoOrbit: false,
  autoAccum: 0,
  time: 0,
  reducedMotion: window.matchMedia("(prefers-reduced-motion: reduce)").matches,
};

// Scene, Camera, Renderer
const viewport = document.getElementById("viewport");
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x080c15);
scene.fog = new THREE.FogExp2(0x080c15, 0.028);

const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.set(0.0, 2.35, 11.4);

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.12;
viewport.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.06;
controls.target.set(0.0, -0.35, 0.0);
controls.minDistance = 5.5;
controls.maxDistance = 18;

// Lighting
scene.add(new THREE.AmbientLight(0x94a3b8, 0.9));
const keyLight = new THREE.DirectionalLight(0xfff4e0, 2.2);
keyLight.position.set(5, 10, 8);
scene.add(keyLight);
const rimLight = new THREE.DirectionalLight(0x38bdf8, 1.15);
rimLight.position.set(-7, 5, -5);
scene.add(rimLight);

const grid = new THREE.GridHelper(24, 32, 0x1e293b, 0x0f172a);
grid.position.y = -1.75;
scene.add(grid);

function makeSpriteLabel(text, colorHex, heightScale = 0.34) {
  const canvas = document.createElement("canvas");
  const isWide = text.length > 2;
  const fontSize = isWide ? 54 : 70;
  const fontStr = `700 ${fontSize}px ui-monospace, SFMono-Regular, Menlo, monospace`;
  const tmpCtx = canvas.getContext("2d");
  tmpCtx.font = fontStr;
  const textW = tmpCtx.measureText(text).width;
  canvas.width = Math.max(128, Math.ceil(textW + 48));
  canvas.height = 128;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.font = fontStr;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = colorHex;
  ctx.fillText(text, canvas.width * 0.5, canvas.height * 0.52);
  const tex = new THREE.CanvasTexture(canvas);
  tex.needsUpdate = true;
  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(heightScale * (canvas.width / canvas.height), heightScale, 1);
  return sprite;
}

// =========================================================================
// 1. LEFT: 3D BINARY HYPERCUBE Q3 (8 VERTICES + 6-CYCLE GRAY HAMILTONIAN RING)
// =========================================================================
const cubeGroup = new THREE.Group();
cubeGroup.position.set(-3.05, 0.88, 0.0);
cubeGroup.rotation.set(0.28, -0.56, 0.0);
scene.add(cubeGroup);

const HALF = 1.12;
function vertexCoord(code) {
  const b2 = (code >> 2) & 1;
  const b1 = (code >> 1) & 1;
  const b0 = code & 1;
  return new THREE.Vector3(
    b0 ? HALF : -HALF,
    b1 ? HALF : -HALF,
    b2 ? HALF : -HALF
  );
}

// Determine which edges belong to the 6-cycle Gray Ring
const ringEdgeSet = new Set();
for (let i = 0; i < GRAY_RING.length; i++) {
  const a = GRAY_RING[i];
  const b = GRAY_RING[(i + 1) % GRAY_RING.length];
  const key = `${Math.min(a, b)}-${Math.max(a, b)}`;
  ringEdgeSet.add(key);
}

// Draw all 12 Q3 edges: Gray Ring edges in glowing tube, non-ring edges thin slate
for (let a = 0; a < 8; a++) {
  for (let bit = 0; bit < 3; bit++) {
    const b = a ^ (1 << bit);
    if (a > b) continue;
    const key = `${a}-${b}`;
    const isRingEdge = ringEdgeSet.has(key);
    const pA = vertexCoord(a);
    const pB = vertexCoord(b);
    const dir = pB.clone().sub(pA);
    const len = dir.length();
    const mid = pA.clone().add(pB).multiplyScalar(0.5);

    const edgeMesh = new THREE.Mesh(
      new THREE.CylinderGeometry(isRingEdge ? 0.042 : 0.016, isRingEdge ? 0.042 : 0.016, len, 10),
      new THREE.MeshStandardMaterial({
        color: isRingEdge ? COLOR_CYAN : 0x334155,
        emissive: isRingEdge ? COLOR_CYAN : 0x1e293b,
        emissiveIntensity: isRingEdge ? 0.55 : 0.1,
        transparent: !isRingEdge,
        opacity: isRingEdge ? 1.0 : 0.45,
        roughness: 0.3,
      })
    );
    edgeMesh.position.copy(mid);
    edgeMesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize());
    cubeGroup.add(edgeMesh);
  }
}

// 8 Vertex nodes on Q3
const vertexMeshes = new Map();
for (let code = 0; code < 8; code++) {
  const info = STATE_TABLE[code];
  const pos = vertexCoord(code);
  const geo =
    info.role === "sentinel"
      ? new THREE.OctahedronGeometry(0.22, 0)
      : new THREE.SphereGeometry(info.role === "center" ? 0.2 : 0.18, 20, 16);
  const baseColor =
    info.role === "sentinel" ? COLOR_FAULT : info.role === "center" ? COLOR_EMERALD : COLOR_CYAN;
  const mat = new THREE.MeshStandardMaterial({
    color: baseColor,
    emissive: baseColor,
    emissiveIntensity: 0.25,
    roughness: 0.25,
    metalness: 0.4,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(pos);
  mesh.userData = { selectCode: code };
  cubeGroup.add(mesh);

  const labelColor =
    info.role === "sentinel" ? "#fda4af" : info.role === "center" ? "#6ee7b7" : "#e0f2fe";
  const lbl = makeSpriteLabel(info.short, labelColor, 0.27);
  lbl.position.copy(
    info.role === "center"
      ? pos.clone().add(new THREE.Vector3(-0.36, -0.34, 0.1))
      : pos.clone().multiplyScalar(1.28)
  );
  cubeGroup.add(lbl);

  vertexMeshes.set(code, { mesh, mat, baseColor, pos });
}

// Active beacon halo on Q3
const cubeHaloMat = new THREE.MeshStandardMaterial({
  color: COLOR_GOLD,
  emissive: COLOR_GOLD,
  emissiveIntensity: 1.0,
});
const cubeHalo = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.035, 12, 32), cubeHaloMat);
cubeGroup.add(cubeHalo);

const cubeTitle = makeSpriteLabel("Cubo Q3 (3 bits)", "#cbd5e1", 0.3);
cubeTitle.position.set(-3.05, 2.88, 0.0);
scene.add(cubeTitle);

// =========================================================================
// 2. CENTER: 3-WIRE BUS (b2, b1, b0) SHOWING 1-BIT HAMMING TRANSITIONS
// =========================================================================
const busGroup = new THREE.Group();
busGroup.position.set(0.0, 0.88, 0.0);
scene.add(busGroup);

const bitWires = [];
const bitDefs = [
  { bit: 2, y: 0.72, name: "b[2]" },
  { bit: 1, y: 0.0, name: "b[1]" },
  { bit: 0, y: -0.72, name: "b[0]" },
];
for (const d of bitDefs) {
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-1.18, d.y, 0),
    new THREE.Vector3(-0.35, d.y * 0.9, 0.1),
    new THREE.Vector3(0.45, d.y * 0.75, 0.1),
    new THREE.Vector3(1.18, d.y * 0.65, 0),
  ]);
  const wireMat = new THREE.MeshStandardMaterial({
    color: 0x334155,
    emissive: COLOR_DIM,
    emissiveIntensity: 0.12,
    roughness: 0.35,
    metalness: 0.6,
  });
  const wireMesh = new THREE.Mesh(new THREE.TubeGeometry(curve, 20, 0.04, 8, false), wireMat);
  busGroup.add(wireMesh);

  const beadMat = new THREE.MeshStandardMaterial({
    color: COLOR_GOLD,
    emissive: COLOR_GOLD,
    emissiveIntensity: 1.8,
  });
  const bead = new THREE.Mesh(new THREE.SphereGeometry(0.085, 12, 12), beadMat);
  bead.visible = false;
  busGroup.add(bead);

  const lbl = makeSpriteLabel(`${d.name}=0`, "#cbd5e1", 0.27);
  lbl.position.set(0.0, d.y + 0.24, 0.18);
  busGroup.add(lbl);

  bitWires.push({ bit: d.bit, curve, wireMat, bead, lbl });
}

// =========================================================================
// 3. RIGHT: 7-CELL TRYTE6 ROSETTE (q + r + s = 0)
// =========================================================================
const rosetteGroup = new THREE.Group();
rosetteGroup.position.set(3.05, 0.88, 0.0);
rosetteGroup.rotation.x = -0.2;
scene.add(rosetteGroup);

function buildSimpleHex(radius, code) {
  const g = new THREE.Group();
  const shape = new THREE.Shape();
  for (let i = 0; i < 6; i++) {
    const a = ((30 + i * 60) * Math.PI) / 180;
    const px = Math.cos(a) * radius;
    const py = Math.sin(a) * radius;
    if (i === 0) shape.moveTo(px, py);
    else shape.lineTo(px, py);
  }
  shape.closePath();

  const bodyMat = new THREE.MeshStandardMaterial({
    color: 0x131a29,
    emissive: COLOR_CYAN,
    emissiveIntensity: 0.05,
    roughness: 0.3,
    metalness: 0.22,
  });
  const body = new THREE.Mesh(
    new THREE.ExtrudeGeometry(shape, { depth: 0.24, bevelEnabled: true, bevelSize: 0.025, bevelThickness: 0.025, bevelSegments: 2 }),
    bodyMat
  );
  body.position.z = -0.12;
  body.userData = { selectCode: code };
  g.add(body);

  // Golden border + subtle 120-deg Y-junction lines
  const rimMat = new THREE.MeshStandardMaterial({
    color: COLOR_GOLD,
    emissive: COLOR_GOLD,
    emissiveIntensity: 0.2,
    roughness: 0.26,
    metalness: 0.82,
  });
  const rimShape = new THREE.Shape();
  for (let i = 0; i < 6; i++) {
    const a = ((30 + i * 60) * Math.PI) / 180;
    const px = Math.cos(a) * (radius * 1.03);
    const py = Math.sin(a) * (radius * 1.03);
    if (i === 0) rimShape.moveTo(px, py);
    else rimShape.lineTo(px, py);
  }
  rimShape.closePath();
  const hole = new THREE.Path();
  for (let i = 0; i < 6; i++) {
    const a = ((30 + i * 60) * Math.PI) / 180;
    const px = Math.cos(a) * (radius * 0.92);
    const py = Math.sin(a) * (radius * 0.92);
    if (i === 0) hole.moveTo(px, py);
    else hole.lineTo(px, py);
  }
  hole.closePath();
  rimShape.holes.push(hole);
  const rimMesh = new THREE.Mesh(new THREE.ExtrudeGeometry(rimShape, { depth: 0.28, bevelEnabled: false }), rimMat);
  rimMesh.position.z = -0.14;
  g.add(rimMesh);

  for (const deg of [30, 150, 270]) {
    const arm = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.9, 0.032, 0.29), rimMat);
    const rad = (deg * Math.PI) / 180;
    arm.position.set(Math.cos(rad) * radius * 0.45, Math.sin(rad) * radius * 0.45, 0);
    arm.rotation.z = rad;
    g.add(arm);
  }

  const info = STATE_TABLE[code];
  const codeSprite = makeSpriteLabel(info.short, "#f8fafc", 0.34);
  codeSprite.position.set(0, 0.08, 0.2);
  g.add(codeSprite);

  const qrsText = `(${info.qrs.join(",")})`;
  const qrsSprite = makeSpriteLabel(qrsText, "#94a3b8", 0.2);
  qrsSprite.position.set(0, -0.26, 0.2);
  g.add(qrsSprite);

  return { group: g, bodyMat, rimMat, codeSprite, qrsSprite };
}

const R_CELL = 0.7;
const D_CENTER = 1.42;
const rosetteCells = new Map();
for (const code of [0b000, ...GRAY_RING]) {
  const info = STATE_TABLE[code];
  const cell = buildSimpleHex(R_CELL, code);
  cell.group.position.set(info.pos2d[0] * D_CENTER, info.pos2d[1] * D_CENTER, 0);
  rosetteGroup.add(cell.group);
  rosetteCells.set(code, cell);
}

const rosetteTitle = makeSpriteLabel("Roseta Tryte6 (q+r+s=0)", "#cbd5e1", 0.3);
rosetteTitle.position.set(3.05, 2.88, 0.0);
scene.add(rosetteTitle);

// =========================================================================
// 4. INTERACTION & DIAGNOSTIC SYNC
// =========================================================================
const codeReadout = document.getElementById("code-readout");
const qrsReadout = document.getElementById("qrs-readout");
const deltaReadout = document.getElementById("delta-readout");
const diagLive = document.getElementById("diag-live");
const lutSnippet = document.getElementById("lut-snippet");
const codeBtns = Array.from(document.querySelectorAll("[data-code]"));
const autoBtn = document.getElementById("btn-auto");

function refreshWireLabelTexture(wireObj, isHigh, isChanged) {
  const canvas = wireObj.lbl.material.map.image;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.font = "700 54px ui-monospace, SFMono-Regular, Menlo, monospace";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = isChanged ? "#fde047" : isHigh ? "#e0f2fe" : "#64748b";
  ctx.fillText(`b[${wireObj.bit}]=${isHigh ? 1 : 0}`, canvas.width * 0.5, canvas.height * 0.52);
  wireObj.lbl.material.map.needsUpdate = true;
}

function selectCode(nextCode) {
  const prev = state.currentCode;
  state.prevCode = prev;
  state.currentCode = nextCode & 0b111;
  state.changedMask = prev ^ state.currentCode;
  state.flashTimer = state.changedMask !== 0 ? 1.0 : 0.0;
  syncVisuals();
}

function stepRing(dir) {
  const idx = GRAY_RING.indexOf(state.currentCode);
  if (idx === -1) {
    selectCode(GRAY_RING[0]);
  } else {
    const nextIdx = (idx + dir + GRAY_RING.length) % GRAY_RING.length;
    selectCode(GRAY_RING[nextIdx]);
  }
}

function syncVisuals() {
  const cur = state.currentCode;
  const info = STATE_TABLE[cur];
  const xor = state.changedMask;
  const flippedCount = ((xor >> 2) & 1) + ((xor >> 1) & 1) + (xor & 1);

  // Q3 Cube vertices
  for (const [code, v] of vertexMeshes.entries()) {
    const active = code === cur;
    v.mat.emissiveIntensity = active ? 1.25 : 0.22;
    v.mesh.scale.setScalar(active ? 1.35 : 1.0);
  }
  const activeV = vertexMeshes.get(cur);
  cubeHalo.position.copy(activeV.pos);
  cubeHaloMat.color.copy(info.role === "sentinel" ? COLOR_FAULT : COLOR_GOLD);
  cubeHaloMat.emissive.copy(info.role === "sentinel" ? COLOR_FAULT : COLOR_GOLD);

  // 3-wire bus
  for (const w of bitWires) {
    const high = ((cur >> w.bit) & 1) === 1;
    const changed = ((xor >> w.bit) & 1) === 1;
    w.wireMat.color.copy(changed ? COLOR_GOLD : high ? COLOR_CYAN : COLOR_DIM);
    w.wireMat.emissive.copy(changed ? COLOR_GOLD : high ? COLOR_CYAN : COLOR_DIM);
    w.wireMat.emissiveIntensity = changed ? 1.15 : high ? 0.55 : 0.08;
    w.bead.visible = changed;
    refreshWireLabelTexture(w, high, changed);
  }

  // Hexagonal Rosette cells
  for (const [code, cell] of rosetteCells.entries()) {
    const active = code === cur;
    const isSentinel = info.role === "sentinel";
    if (isSentinel) {
      cell.bodyMat.color.setHex(0x2a1018);
      cell.bodyMat.emissive.copy(COLOR_FAULT);
      cell.bodyMat.emissiveIntensity = 0.28;
      cell.rimMat.color.copy(COLOR_FAULT);
      cell.rimMat.emissive.copy(COLOR_FAULT);
      cell.codeSprite.material.color.setHex(0xfda4af);
      cell.qrsSprite.material.color.setHex(0xfecdd3);
      cell.group.position.z = 0;
    } else if (active) {
      const c = info.role === "center" ? COLOR_EMERALD : COLOR_CYAN;
      cell.bodyMat.color.copy(c);
      cell.bodyMat.emissive.copy(c);
      cell.bodyMat.emissiveIntensity = 0.45;
      cell.rimMat.color.copy(COLOR_GOLD);
      cell.rimMat.emissive.copy(COLOR_GOLD);
      cell.codeSprite.material.color.setHex(0x090d16);
      cell.qrsSprite.material.color.setHex(0x0f172a);
      cell.group.position.z = 0.12;
    } else {
      cell.bodyMat.color.setHex(0x131a29);
      cell.bodyMat.emissive.copy(COLOR_CYAN);
      cell.bodyMat.emissiveIntensity = 0.04;
      cell.rimMat.color.copy(COLOR_GOLD);
      cell.rimMat.emissive.copy(COLOR_GOLD);
      cell.codeSprite.material.color.setHex(0xf8fafc);
      cell.qrsSprite.material.color.setHex(0xffffff);
      cell.group.position.z = 0;
    }
  }

  // DOM HUD
  codeReadout.textContent = info.code;
  qrsReadout.textContent = info.qrs ? `(${info.qrs.join(", ")})` : "SENTINELA / FORA DO PLANO";
  deltaReadout.textContent = `${flippedCount} ${flippedCount === 1 ? "bit" : "bits"}`;

  for (const btn of codeBtns) {
    btn.setAttribute("aria-pressed", String(parseInt(btn.dataset.code, 2) === cur));
  }

  diagLive.classList.remove("is-ring", "is-center", "is-sentinel");
  if (info.role === "sentinel") {
    diagLive.classList.add("is-sentinel");
    diagLive.innerHTML =
      `<strong>${info.code} (Sentinela 1/8 livre):</strong> vértice reservado no cubo Q3 para sinalizar erro, borda de grade ou evento de carry fora do anel de 7 células.`;
  } else if (info.role === "center") {
    diagLive.classList.add("is-center");
    diagLive.innerHTML =
      `<strong>${info.code} -> Centro (0, 0, 0):</strong> origem nula da roseta Tryte6. Delta da última transição: <code>${flippedCount} bit(s)</code>.`;
  } else {
    diagLive.classList.add("is-ring");
    diagLive.innerHTML =
      `<strong>${info.code} -> Direção ${info.angle}° (${info.qrs.join(", ")}):</strong> ` +
      (flippedCount === 1
        ? `comutou exatamente <code>1 bit</code> no cubo Q3 (passo mínimo ΔV²).`
        : `delta de <code>${flippedCount} bits</code> em relação ao estado anterior.`);
  }

  const nextCCW = GRAY_RING[(Math.max(0, GRAY_RING.indexOf(cur)) + 1) % 6];
  const nextCW = GRAY_RING[(Math.max(0, GRAY_RING.indexOf(cur)) + 5) % 6];
  lutSnippet.textContent =
    `// 1 unica LUT4 recebe (estado[2:0], sentido_rot)\n` +
    `cur = ${info.code}; next(+60°) = ${STATE_TABLE[nextCCW].code}; prev(-60°) = ${STATE_TABLE[nextCW].code}`;
}

// =========================================================================
// 5. RAYCASTING & CONTROLS
// =========================================================================
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
let downPos = { x: 0, y: 0 };

renderer.domElement.addEventListener("pointerdown", (e) => {
  downPos = { x: e.clientX, y: e.clientY };
});

renderer.domElement.addEventListener("pointerup", (e) => {
  if (Math.hypot(e.clientX - downPos.x, e.clientY - downPos.y) > 6) return;
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);

  const clickTargets = [];
  for (const v of vertexMeshes.values()) clickTargets.push(v.mesh);
  for (const c of rosetteCells.values()) {
    c.group.traverse((obj) => {
      if (obj.userData && obj.userData.selectCode !== undefined) clickTargets.push(obj);
    });
  }
  const hits = raycaster.intersectObjects(clickTargets, false);
  if (hits.length > 0) {
    selectCode(hits[0].object.userData.selectCode);
  }
});

document.getElementById("btn-ccw").addEventListener("click", () => stepRing(1));
document.getElementById("btn-cw").addEventListener("click", () => stepRing(-1));
autoBtn.addEventListener("click", () => {
  state.autoOrbit = !state.autoOrbit;
  state.autoAccum = 0;
  autoBtn.setAttribute("aria-pressed", String(state.autoOrbit));
});

for (const btn of codeBtns) {
  btn.addEventListener("click", () => selectCode(parseInt(btn.dataset.code, 2)));
}

window.addEventListener("resize", () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// =========================================================================
// 6. ANIMATION LOOP
// =========================================================================
let lastTime = performance.now();
function animate(now) {
  requestAnimationFrame(animate);
  const dt = Math.max(0, Math.min(0.05, (now - lastTime) * 0.001));
  lastTime = now;
  state.time += dt;

  if (!state.reducedMotion) {
    cubeGroup.rotation.y = -0.56 + Math.sin(state.time * 0.35) * 0.18;
    cubeHalo.lookAt(camera.position);
  }

  if (state.autoOrbit && !state.reducedMotion) {
    state.autoAccum += dt;
    if (state.autoAccum >= 0.85) {
      state.autoAccum = 0;
      stepRing(1);
    }
  }

  if (state.flashTimer > 0) {
    state.flashTimer = Math.max(0, state.flashTimer - dt * 1.15);
    const u = 1 - state.flashTimer;
    for (const w of bitWires) {
      if (w.bead.visible) {
        w.curve.getPointAt(u, w.bead.position);
      }
    }
    if (state.flashTimer === 0) {
      for (const w of bitWires) w.bead.visible = false;
    }
  }

  controls.update();
  renderer.render(scene, camera);
}

syncVisuals();
requestAnimationFrame(animate);
