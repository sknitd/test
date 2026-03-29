/**
 * wigs.js — Procedural 3D Wig Model Generators
 * Creates Three.js Group objects for each wig style.
 * All wigs are normalized to fit a unit head sphere radius ~1.
 */

const WigFactory = (function() {

  // ─── Shared Hair Materials ───────────────────────────────────────────────

  function hairMat(color, { roughness = 0.85, metalness = 0.05, side = THREE.FrontSide, transparent = false, opacity = 1.0 } = {}) {
    return new THREE.MeshStandardMaterial({
      color,
      roughness,
      metalness,
      side,
      transparent,
      opacity,
    });
  }

  // Procedural hair strand texture
  function makeHairTexture(baseColor, strandCount = 80) {
    const size = 256;
    const c = document.createElement('canvas');
    c.width = size; c.height = size;
    const ctx = c.getContext('2d');

    const hex = '#' + baseColor.toString(16).padStart(6, '0');
    ctx.fillStyle = hex;
    ctx.fillRect(0, 0, size, size);

    // Draw fine hair strands
    const r = parseInt(hex.slice(1,3),16);
    const g = parseInt(hex.slice(3,5),16);
    const b = parseInt(hex.slice(5,7),16);

    for (let i = 0; i < strandCount; i++) {
      const x = Math.random() * size;
      const shade = 0.6 + Math.random() * 0.4;
      ctx.strokeStyle = `rgba(${Math.floor(r*shade)},${Math.floor(g*shade)},${Math.floor(b*shade)},0.6)`;
      ctx.lineWidth = 0.5 + Math.random() * 1;
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x + (Math.random()-0.5)*20, size);
      ctx.stroke();
    }

    const tex = new THREE.CanvasTexture(c);
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(3, 3);
    return tex;
  }

  // ─── Helper: Head Cap (upper hemisphere + sides) ─────────────────────────

  function headCap(color, {
    rx = 1.04, ry = 1.0, rz = 1.04,
    phiEnd = Math.PI * 0.65,
    segments = 48
  } = {}) {
    const geo = new THREE.SphereGeometry(1, segments, segments/2, 0, Math.PI*2, 0, phiEnd);
    const mat = hairMat(color);
    mat.map = makeHairTexture(color);
    const mesh = new THREE.Mesh(geo, mat);
    mesh.scale.set(rx, ry, rz);
    return mesh;
  }

  // ─── Helper: Hair strand via tube ────────────────────────────────────────

  function hairStrand(points, color, radius = 0.018) {
    const curve = new THREE.CatmullRomCurve3(points.map(p => new THREE.Vector3(...p)));
    const geo = new THREE.TubeGeometry(curve, 8, radius, 4, false);
    return new THREE.Mesh(geo, hairMat(color, { roughness: 0.75 }));
  }

  // ─── WIG 1: Classic Crew Cut ─────────────────────────────────────────────

  function createCrewCut(color = 0x2c1a08) {
    const group = new THREE.Group();
    group.userData.name = 'Crew Cut';

    // Close-fitting cap
    const cap = headCap(color, { rx:1.03, ry:1.02, rz:1.03, phiEnd: Math.PI*0.58 });
    group.add(cap);

    // Short stubble strands on top
    const strandColor = color;
    for (let i = 0; i < 60; i++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.random() * Math.PI * 0.45;
      const bx = Math.sin(phi)*Math.cos(theta) * 1.03;
      const by = Math.cos(phi) * 1.02;
      const bz = Math.sin(phi)*Math.sin(theta) * 1.03;
      const len = 0.06 + Math.random()*0.04;
      const nx = bx/1.03, ny = by/1.02, nz = bz/1.03;
      const strand = hairStrand([
        [bx, by, bz],
        [bx + nx*len*0.5, by + ny*len*0.5, bz + nz*len*0.5],
        [bx + nx*len, by + ny*len, bz + nz*len]
      ], strandColor, 0.012);
      group.add(strand);
    }

    return group;
  }

  // ─── WIG 2: Afro ─────────────────────────────────────────────────────────

  function createAfro(color = 0x0d0a07) {
    const group = new THREE.Group();
    group.userData.name = 'Afro';

    // Large sphere base
    const geo = new THREE.SphereGeometry(1, 48, 48, 0, Math.PI*2, 0, Math.PI*0.72);
    const mat = hairMat(color, { roughness: 1.0 });
    mat.map = makeHairTexture(color, 120);
    const base = new THREE.Mesh(geo, mat);
    base.scale.set(1.52, 1.45, 1.52);
    base.position.y = 0.08;
    group.add(base);

    // Curly bump clusters
    const bumpColor = new THREE.Color(color).multiplyScalar(1.3).getHex();
    for (let i = 0; i < 80; i++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.random() * Math.PI * 0.68;
      const r = 1.5 + Math.random() * 0.08;
      const x = Math.sin(phi)*Math.cos(theta) * r * 1.52;
      const y = Math.cos(phi) * r * 1.45 + 0.08;
      const z = Math.sin(phi)*Math.sin(theta) * r * 1.52;
      const size = 0.06 + Math.random() * 0.1;
      const bumpGeo = new THREE.SphereGeometry(size, 6, 6);
      const bump = new THREE.Mesh(bumpGeo, hairMat(bumpColor, { roughness: 1.0 }));
      bump.position.set(x, y, z);
      group.add(bump);
    }

    return group;
  }

  // ─── WIG 3: Long Straight ────────────────────────────────────────────────

  function createLongStraight(color = 0x1a0d00) {
    const group = new THREE.Group();
    group.userData.name = 'Long Straight';

    // Head cap
    const cap = headCap(color, { rx:1.04, ry:1.03, rz:1.04, phiEnd: Math.PI*0.62 });
    group.add(cap);

    // Long side panels using layered planes
    const panelMat = hairMat(color, { side: THREE.DoubleSide, roughness: 0.8 });
    panelMat.map = makeHairTexture(color, 100);

    const numPanels = 28;
    for (let i = 0; i < numPanels; i++) {
      const angle = (i / numPanels) * Math.PI * 2;
      const panelWidth = 0.32;
      const panelHeight = 2.2;

      // Build a curved panel using CatmullRomCurve3
      const startX = Math.cos(angle) * 1.02;
      const startZ = Math.sin(angle) * 1.02;
      const endX = Math.cos(angle) * 0.35;
      const endZ = Math.sin(angle) * 0.35;

      // Only add panels below the crown (not on top)
      const isFrontBack = Math.abs(Math.cos(angle)) > 0.6;
      const heightOffset = isFrontBack ? -0.1 : 0.0;

      // Simple rectangular plane for each strand grouping
      const geo = new THREE.PlaneGeometry(panelWidth, panelHeight, 1, 8);
      const mesh = new THREE.Mesh(geo, panelMat);

      // Position at edge of head, pointing down
      mesh.position.set(startX, -0.2 + heightOffset, startZ);
      mesh.rotation.y = -angle;
      mesh.rotation.z = 0;

      // Tilt outward slightly
      const tiltAxis = new THREE.Vector3(Math.sin(angle), 0, -Math.cos(angle));
      mesh.rotateOnAxis(tiltAxis, 0.12);

      // Move down so top aligns with bottom of cap
      mesh.position.y -= panelHeight * 0.5 + 0.1;

      group.add(mesh);
    }

    // Fringe / bangs across the forehead
    for (let i = 0; i < 12; i++) {
      const t = (i / 11) - 0.5; // -0.5 to 0.5
      const x = t * 0.85;
      const z = -Math.sqrt(Math.max(0, 1.04*1.04 - x*x)) * 0.9;
      const strand = hairStrand([
        [x, 0.25, z],
        [x * 0.95, 0.0, z - 0.05],
        [x * 0.9, -0.25, z - 0.08],
        [x * 0.85, -0.45, z - 0.06]
      ], color, 0.022);
      group.add(strand);
    }

    return group;
  }

  // ─── WIG 4: Mohawk ───────────────────────────────────────────────────────

  function createMohawk(color = 0xc0a000) {
    const group = new THREE.Group();
    group.userData.name = 'Mohawk';

    // Shaved-sides cap (skin tone base)
    const sideGeo = new THREE.SphereGeometry(1.01, 48, 48, 0, Math.PI*2, 0, Math.PI*0.60);
    const sideMat = new THREE.MeshStandardMaterial({ color: 0xc68642, roughness: 0.95 });
    group.add(new THREE.Mesh(sideGeo, sideMat));

    // Central mohawk strip
    const stripColor = color;
    const spikeMat = hairMat(stripColor, { roughness: 0.7 });
    spikeMat.map = makeHairTexture(stripColor, 60);

    // Base strip
    const stripGeo = new THREE.BoxGeometry(0.22, 0.12, 1.85);
    const strip = new THREE.Mesh(stripGeo, spikeMat);
    strip.position.y = 1.02;
    strip.position.z = -0.05;
    group.add(strip);

    // Spikes along the mohawk
    const numSpikes = 10;
    for (let i = 0; i < numSpikes; i++) {
      const t = (i / (numSpikes-1)) * 1.6 - 0.8;
      const spikeHeight = 0.25 + Math.sin((i / numSpikes) * Math.PI) * 0.35;
      const spikeGeo = new THREE.ConeGeometry(0.09, spikeHeight, 6);
      const spike = new THREE.Mesh(spikeGeo, spikeMat);
      spike.position.set(0, 1.06 + spikeHeight * 0.5, t);
      group.add(spike);
    }

    return group;
  }

  // ─── WIG 5: Wavy Medium ──────────────────────────────────────────────────

  function createWavyMedium(color = 0x5c2e00) {
    const group = new THREE.Group();
    group.userData.name = 'Wavy Medium';

    // Head cap
    const cap = headCap(color, { rx:1.05, ry:1.04, rz:1.05, phiEnd: Math.PI*0.63 });
    group.add(cap);

    // Wavy hair strands
    const numStrands = 50;
    for (let i = 0; i < numStrands; i++) {
      const angle = (i / numStrands) * Math.PI * 2;
      const baseX = Math.cos(angle) * 1.04;
      const baseZ = Math.sin(angle) * 1.04;

      // Only on upper half and sides (not underneath)
      const startY = -0.1 + Math.random() * 0.3;

      // Create wave pattern
      const wave = Math.sin(i * 0.7) * 0.12;
      const length = 0.9 + Math.random() * 0.4;

      const points = [
        [baseX, startY, baseZ],
        [baseX * 1.05 + wave, startY - length*0.3, baseZ * 1.05],
        [baseX * 1.08 - wave, startY - length*0.6, baseZ * 1.08],
        [baseX * 1.04 + wave*0.5, startY - length, baseZ * 1.04],
      ];

      const strand = hairStrand(points, color, 0.025);
      group.add(strand);
    }

    // Top flowing strands
    for (let i = 0; i < 25; i++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.random() * Math.PI * 0.35;
      const bx = Math.sin(phi)*Math.cos(theta) * 1.04;
      const by = Math.cos(phi) * 1.04;
      const bz = Math.sin(phi)*Math.sin(theta) * 1.04;
      const wave = (Math.random()-0.5) * 0.15;
      const strand = hairStrand([
        [bx, by, bz],
        [bx*(1+0.05), by - 0.2, bz*(1+0.05) + wave],
        [bx*(1+0.08), by - 0.5, bz*(1+0.08)],
      ], color, 0.018);
      group.add(strand);
    }

    return group;
  }

  // ─── WIG 6: Slicked Back ─────────────────────────────────────────────────

  function createSlickedBack(color = 0x0d0d0d) {
    const group = new THREE.Group();
    group.userData.name = 'Slicked Back';

    // Head cap
    const cap = headCap(color, { rx:1.035, ry:1.025, rz:1.035, phiEnd: Math.PI*0.60 });
    // Use glossy material for slicked look
    const glossMat = new THREE.MeshStandardMaterial({
      color,
      roughness: 0.25,
      metalness: 0.15,
      map: makeHairTexture(color, 80)
    });
    cap.material = glossMat;
    group.add(cap);

    // Swept-back strands flowing from front to back
    const numStrands = 40;
    for (let i = 0; i < numStrands; i++) {
      const t = (i / numStrands) * 2 - 1; // -1 to 1 left/right
      const x = t * 0.85;
      const startZ = -Math.sqrt(Math.max(0, 1.035*1.035 - x*x));
      const startY = Math.sqrt(Math.max(0, 1.025*1.025 - x*x - startZ*startZ * 0.1));

      const strand = hairStrand([
        [x, 0.65, startZ * 0.5],
        [x * 0.98, 0.55, 0.1],
        [x * 0.96, 0.2, 0.7],
        [x * 0.9, -0.2, 1.0],
        [x * 0.85, -0.45, 1.03],
      ], color, 0.016);
      group.add(strand);
    }

    return group;
  }

  // ─── WIG 7: Curly / Ringlets ─────────────────────────────────────────────

  function createCurly(color = 0x3d1a00) {
    const group = new THREE.Group();
    group.userData.name = 'Curly';

    // Head cap
    const cap = headCap(color, { rx:1.06, ry:1.05, rz:1.06, phiEnd: Math.PI*0.64 });
    group.add(cap);

    // Helical ringlets around the head
    const numRinglets = 32;
    for (let i = 0; i < numRinglets; i++) {
      const baseAngle = (i / numRinglets) * Math.PI * 2;
      const baseX = Math.cos(baseAngle) * (0.8 + Math.random() * 0.3);
      const baseY = -0.1 + Math.random() * 0.4;
      const baseZ = Math.sin(baseAngle) * (0.8 + Math.random() * 0.3);

      // Create helical coil
      const helixPoints = [];
      const coils = 2 + Math.random() * 1.5;
      const coilRadius = 0.05 + Math.random() * 0.05;
      const coilLength = 0.4 + Math.random() * 0.4;

      for (let j = 0; j <= 20; j++) {
        const t = j / 20;
        const angle = t * Math.PI * 2 * coils;
        const cx = baseX + Math.cos(angle) * coilRadius;
        const cy = baseY - t * coilLength;
        const cz = baseZ + Math.sin(angle) * coilRadius;
        helixPoints.push([cx, cy, cz]);
      }

      const strand = hairStrand(helixPoints, color, 0.018);
      group.add(strand);
    }

    return group;
  }

  // ─── WIG 8: Man Bun ──────────────────────────────────────────────────────

  function createManBun(color = 0x1a0a00) {
    const group = new THREE.Group();
    group.userData.name = 'Man Bun';

    // Tight sides cap
    const cap = headCap(color, { rx:1.03, ry:1.02, rz:1.03, phiEnd: Math.PI*0.62 });
    group.add(cap);

    // Swept-back strands going to top-back
    const numStrands = 35;
    for (let i = 0; i < numStrands; i++) {
      const angle = (i / numStrands) * Math.PI * 2;
      const r = 1.03;
      const startX = Math.cos(angle) * r;
      const startY = 0.0 + Math.random() * 0.3;
      const startZ = Math.sin(angle) * r;

      const strand = hairStrand([
        [startX, startY, startZ],
        [startX * 0.7, startY + 0.3, startZ * 0.7],
        [startX * 0.3, startY + 0.5, startZ * 0.3],
        [0, startY + 0.7, -0.3],
      ], color, 0.014);
      group.add(strand);
    }

    // Bun sphere at back-top
    const bunGeo = new THREE.SphereGeometry(0.22, 20, 20);
    const bunMat = hairMat(color, { roughness: 0.8 });
    bunMat.map = makeHairTexture(color, 60);
    const bun = new THREE.Mesh(bunGeo, bunMat);
    bun.position.set(0, 0.85, -0.45);
    bun.scale.set(1, 0.9, 0.9);
    group.add(bun);

    // Wrap ring around bun
    const ringGeo = new THREE.TorusGeometry(0.2, 0.025, 8, 24);
    const ringMat = new THREE.MeshStandardMaterial({ color: 0x222222, roughness: 0.5 });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.position.set(0, 0.85, -0.45);
    ring.rotation.x = Math.PI / 2;
    group.add(ring);

    return group;
  }

  // ─── WIG REGISTRY ────────────────────────────────────────────────────────

  const registry = [
    { id: 'crew',    label: 'Crew Cut',     style: 'Short & Clean',    factory: createCrewCut,     defaultColor: 0x2c1a08 },
    { id: 'afro',    label: 'Afro',         style: 'Bold & Beautiful', factory: createAfro,        defaultColor: 0x100a04 },
    { id: 'long',    label: 'Long Straight',style: 'Flowing & Elegant',factory: createLongStraight,defaultColor: 0x1a0d00 },
    { id: 'mohawk',  label: 'Mohawk',       style: 'Punk & Edgy',      factory: createMohawk,      defaultColor: 0xc0a000 },
    { id: 'wavy',    label: 'Wavy Medium',  style: 'Natural & Relaxed',factory: createWavyMedium,  defaultColor: 0x5c2e00 },
    { id: 'slicked', label: 'Slicked Back', style: 'Sharp & Polished', factory: createSlickedBack, defaultColor: 0x0d0d0d },
    { id: 'curly',   label: 'Curly',        style: 'Lively & Vibrant', factory: createCurly,       defaultColor: 0x3d1a00 },
    { id: 'manbun',  label: 'Man Bun',      style: 'Modern & Stylish', factory: createManBun,      defaultColor: 0x1a0a00 },
  ];

  // Hair color palette
  const colorPalette = [
    { label: 'Jet Black',    value: 0x0a0805 },
    { label: 'Dark Brown',   value: 0x2c1a08 },
    { label: 'Medium Brown', value: 0x5c3210 },
    { label: 'Auburn',       value: 0x7a2a00 },
    { label: 'Dark Blonde',  value: 0x9a7030 },
    { label: 'Blonde',       value: 0xd4a848 },
    { label: 'Platinum',     value: 0xe8d8b8 },
    { label: 'Silver/Grey',  value: 0x9090a0 },
    { label: 'White',        value: 0xf0f0f0 },
    { label: 'Red',          value: 0x8b1a00 },
    { label: 'Copper',       value: 0xb54a00 },
    { label: 'Purple',       value: 0x4a0070 },
    { label: 'Blue',         value: 0x001080 },
    { label: 'Green',        value: 0x004020 },
    { label: 'Pink',         value: 0xc04080 },
  ];

  // ─── Public API ──────────────────────────────────────────────────────────

  function build(wigId, color) {
    const entry = registry.find(w => w.id === wigId);
    if (!entry) return null;
    const group = entry.factory(color !== undefined ? color : entry.defaultColor);
    return group;
  }

  function rebuildWithColor(wigId, color) {
    return build(wigId, color);
  }

  // Render a wig thumbnail onto a canvas element (2D preview)
  function renderThumbnail(canvas, wigId, color) {
    const ctx = canvas.getContext('2d');
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0,0,w,h);

    const entry = registry.find(e => e.id === wigId);
    if (!entry) return;

    const c = color !== undefined ? color : entry.defaultColor;
    const hex = '#' + c.toString(16).padStart(6, '0');

    // Draw simple silhouette for each wig type
    ctx.fillStyle = '#1a1a24';
    ctx.fillRect(0,0,w,h);

    const cx = w/2, cy = h/2;
    ctx.fillStyle = hex;
    ctx.strokeStyle = hex;

    switch(wigId) {
      case 'crew':
        ctx.beginPath();
        ctx.arc(cx, cy, w*0.38, Math.PI, 0);
        ctx.fill();
        break;
      case 'afro':
        ctx.beginPath();
        ctx.arc(cx, cy - h*0.05, w*0.46, 0, Math.PI*2);
        ctx.fill();
        break;
      case 'long':
        ctx.beginPath();
        ctx.arc(cx, cy - h*0.15, w*0.36, Math.PI, 0);
        ctx.fill();
        ctx.fillRect(cx - w*0.36, cy - h*0.15, w*0.72, h*0.65);
        break;
      case 'mohawk':
        ctx.fillStyle = '#c68642';
        ctx.beginPath();
        ctx.arc(cx, cy, w*0.38, Math.PI, 0);
        ctx.fill();
        ctx.fillStyle = hex;
        ctx.beginPath();
        ctx.moveTo(cx - w*0.08, cy - h*0.12);
        ctx.lineTo(cx, cy - h*0.48);
        ctx.lineTo(cx + w*0.08, cy - h*0.12);
        ctx.fill();
        break;
      case 'wavy': {
        ctx.beginPath();
        ctx.arc(cx, cy - h*0.1, w*0.37, Math.PI, 0);
        ctx.fill();
        // Wavy sides
        for (let side of [-1, 1]) {
          ctx.beginPath();
          const sx = cx + side * w*0.37;
          ctx.moveTo(sx, cy - h*0.1);
          for (let i = 0; i <= 8; i++) {
            const t = i / 8;
            const wx = sx + side * Math.sin(t * Math.PI * 3) * w * 0.08;
            ctx.lineTo(wx, cy - h*0.1 + t * h*0.5);
          }
          ctx.lineWidth = w*0.15;
          ctx.strokeStyle = hex;
          ctx.stroke();
        }
        break;
      }
      case 'slicked': {
        ctx.beginPath();
        ctx.arc(cx, cy, w*0.38, Math.PI, 0);
        ctx.fill();
        // Slicked back lines
        ctx.strokeStyle = new THREE.Color(c).multiplyScalar(1.5).getStyle();
        ctx.lineWidth = 1.5;
        for (let i = -3; i <= 3; i++) {
          ctx.beginPath();
          ctx.moveTo(cx + i*8, cy - h*0.35);
          ctx.bezierCurveTo(cx + i*7, cy - h*0.1, cx + i*5, cy + h*0.1, cx + i*3, cy + h*0.25);
          ctx.stroke();
        }
        break;
      }
      case 'curly': {
        ctx.beginPath();
        ctx.arc(cx, cy - h*0.05, w*0.43, 0, Math.PI*2);
        ctx.fill();
        // Curly texture
        const darkerHex = '#' + new THREE.Color(c).multiplyScalar(0.7).getHexString();
        ctx.strokeStyle = darkerHex;
        ctx.lineWidth = 1.5;
        for (let i = 0; i < 20; i++) {
          const rx = cx + (Math.random()-0.5)*w*0.6;
          const ry = cy + (Math.random()-0.5)*h*0.5;
          const sr = 4 + Math.random()*8;
          ctx.beginPath();
          ctx.arc(rx, ry, sr, 0, Math.PI * 1.8);
          ctx.stroke();
        }
        break;
      }
      case 'manbun':
        ctx.beginPath();
        ctx.arc(cx, cy, w*0.37, Math.PI, 0);
        ctx.fill();
        ctx.beginPath();
        ctx.arc(cx, cy - h*0.38, w*0.14, 0, Math.PI*2);
        ctx.fill();
        break;
    }
  }

  return { registry, colorPalette, build, rebuildWithColor, renderThumbnail };
})();
