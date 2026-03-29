/**
 * app.js — Main application: connects tracker, renderer, and UI
 */

(function() {
  'use strict';

  // ─── State ───────────────────────────────────────────────────────────────

  let currentWigId   = 'crew';
  let currentColor   = null; // null = use wig default
  let faceDetected   = false;
  let showMesh       = false;
  let frameCount     = 0;
  let fps            = 0;
  let lastFpsTime    = performance.now();
  let headYaw        = 0, headPitch = 0, headRoll = 0;
  let isInitialized  = false;

  // ─── DOM References ──────────────────────────────────────────────────────

  const videoEl      = document.getElementById('video');
  const wigCanvas    = document.getElementById('wig-canvas');
  const debugCanvas  = document.getElementById('debug-canvas');
  const loadingEl    = document.getElementById('loading-overlay');
  const noFaceEl     = document.getElementById('no-face-overlay');
  const wigGrid      = document.getElementById('wig-grid');
  const colorGrid    = document.getElementById('color-grid');
  const statsYaw     = document.getElementById('stat-yaw');
  const statsPitch   = document.getElementById('stat-pitch');
  const statsRoll    = document.getElementById('stat-roll');
  const statsFps     = document.getElementById('stat-fps');
  const captureBtn   = document.getElementById('capture-btn');
  const meshBtn      = document.getElementById('mesh-btn');
  const captureOut   = document.getElementById('capture-output');
  const captureImg   = document.getElementById('capture-img');
  const captureClose = document.getElementById('capture-close');
  const captureDown  = document.getElementById('capture-download');
  const captureFlash = document.getElementById('capture-flash');
  const instrEl      = document.getElementById('instructions');
  const gaugeYaw     = document.getElementById('gauge-yaw-fill');
  const gaugePitch   = document.getElementById('gauge-pitch-fill');
  const gaugeRoll    = document.getElementById('gauge-roll-fill');
  const gaugeYawVal  = document.getElementById('gauge-yaw-val');
  const gaugePitchVal= document.getElementById('gauge-pitch-val');
  const gaugeRollVal = document.getElementById('gauge-roll-val');

  // ─── Build UI ────────────────────────────────────────────────────────────

  function buildWigGrid() {
    wigGrid.innerHTML = '';
    WigFactory.registry.forEach(entry => {
      const card = document.createElement('div');
      card.className = 'wig-card' + (entry.id === currentWigId ? ' active' : '');
      card.dataset.id = entry.id;

      const previewWrap = document.createElement('div');
      previewWrap.className = 'wig-preview';

      const thumbCanvas = document.createElement('canvas');
      thumbCanvas.width = 64;
      thumbCanvas.height = 64;
      WigFactory.renderThumbnail(thumbCanvas, entry.id, entry.defaultColor);
      previewWrap.appendChild(thumbCanvas);

      const name = document.createElement('span');
      name.className = 'wig-name';
      name.textContent = entry.label;

      const style = document.createElement('span');
      style.className = 'wig-style';
      style.textContent = entry.style;

      card.appendChild(previewWrap);
      card.appendChild(name);
      card.appendChild(style);

      card.addEventListener('click', () => selectWig(entry.id));
      wigGrid.appendChild(card);
    });
  }

  function buildColorGrid() {
    colorGrid.innerHTML = '';
    WigFactory.colorPalette.forEach(({ label, value }) => {
      const swatch = document.createElement('div');
      swatch.className = 'color-swatch';
      swatch.title = label;
      swatch.style.background = '#' + value.toString(16).padStart(6, '0');
      swatch.addEventListener('click', () => selectColor(value, swatch));
      colorGrid.appendChild(swatch);
    });
  }

  // ─── Wig / Color Selection ────────────────────────────────────────────────

  function selectWig(id) {
    currentWigId = id;

    // Update active card
    wigGrid.querySelectorAll('.wig-card').forEach(c => {
      c.classList.toggle('active', c.dataset.id === id);
    });

    // Rebuild wig
    loadWig();
  }

  function selectColor(value, swatchEl) {
    currentColor = value;

    // Update active swatch
    colorGrid.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('active'));
    swatchEl.classList.add('active');

    // Update wig thumbnails with new color
    wigGrid.querySelectorAll('.wig-card').forEach(card => {
      const canvas = card.querySelector('canvas');
      if (canvas) WigFactory.renderThumbnail(canvas, card.dataset.id, value);
    });

    loadWig();
  }

  function loadWig() {
    const color = currentColor !== null ? currentColor :
      WigFactory.registry.find(e => e.id === currentWigId)?.defaultColor;
    const group = WigFactory.build(currentWigId, color);
    WigRenderer.setWig(group);
  }

  // ─── Face Tracking Callback ───────────────────────────────────────────────

  function onFaceResults(results) {
    frameCount++;

    // FPS
    const now = performance.now();
    if (now - lastFpsTime >= 1000) {
      fps = Math.round(frameCount * 1000 / (now - lastFpsTime));
      frameCount = 0;
      lastFpsTime = now;
      if (statsFps) statsFps.textContent = fps;
    }

    const hasLandmarks = results.multiFaceLandmarks && results.multiFaceLandmarks.length > 0;

    if (hasLandmarks) {
      faceDetected = true;
      noFaceEl?.classList.remove('visible');

      const imgLandmarks   = results.multiFaceLandmarks[0];
      const worldLandmarks = results.multiFaceWorldLandmarks?.[0];

      if (worldLandmarks) {
        WigRenderer.updateWigTransform(imgLandmarks, worldLandmarks);
        updatePoseStats(worldLandmarks);
      }

      if (showMesh) drawDebugMesh(imgLandmarks);

    } else {
      faceDetected = false;
      noFaceEl?.classList.add('visible');
    }

    // Render wig
    WigRenderer.render();
  }

  // ─── Pose stats ──────────────────────────────────────────────────────────

  function updatePoseStats(worldLandmarks) {
    const lm = worldLandmarks;
    if (!lm || lm.length < 468) return;

    const forehead = { x:lm[10].x, y:-lm[10].y, z:lm[10].z };
    const chin     = { x:lm[152].x, y:-lm[152].y, z:lm[152].z };
    const leftEar  = { x:lm[234].x, y:-lm[234].y, z:lm[234].z };
    const rightEar = { x:lm[454].x, y:-lm[454].y, z:lm[454].z };

    // Yaw: left-right rotation → based on ear Z difference
    headYaw   = Math.atan2(rightEar.z - leftEar.z, 0.1) * (180/Math.PI);
    // Pitch: up-down → based on forehead-chin Z difference
    headPitch = Math.atan2(forehead.z - chin.z, 0.2) * (180/Math.PI);
    // Roll: tilt → based on ear Y difference
    headRoll  = Math.atan2(rightEar.y - leftEar.y, 0.2) * (180/Math.PI);

    if (statsYaw)   statsYaw.textContent   = headYaw.toFixed(0)   + '°';
    if (statsPitch) statsPitch.textContent = headPitch.toFixed(0) + '°';
    if (statsRoll)  statsRoll.textContent  = headRoll.toFixed(0)  + '°';

    // Gauges (map ±90° to 0–100%)
    const yawPct   = Math.min(100, Math.abs(headYaw)   / 90 * 100);
    const pitchPct = Math.min(100, Math.abs(headPitch) / 90 * 100);
    const rollPct  = Math.min(100, Math.abs(headRoll)  / 45 * 100);

    if (gaugeYaw)   { gaugeYaw.style.width   = yawPct   + '%'; }
    if (gaugePitch) { gaugePitch.style.width = pitchPct + '%'; }
    if (gaugeRoll)  { gaugeRoll.style.width  = rollPct  + '%'; }
    if (gaugeYawVal)   gaugeYawVal.textContent   = headYaw.toFixed(0)   + '°';
    if (gaugePitchVal) gaugePitchVal.textContent = headPitch.toFixed(0) + '°';
    if (gaugeRollVal)  gaugeRollVal.textContent  = headRoll.toFixed(0)  + '°';
  }

  // ─── Debug Mesh ──────────────────────────────────────────────────────────

  function drawDebugMesh(landmarks) {
    const ctx = debugCanvas.getContext('2d');
    const w = debugCanvas.width, h = debugCanvas.height;
    ctx.clearRect(0, 0, w, h);

    // Draw face mesh dots
    ctx.fillStyle = 'rgba(168, 85, 247, 0.5)';
    for (const lm of landmarks) {
      // Mirror X to match display
      const x = (1 - lm.x) * w;
      const y = lm.y * h;
      ctx.beginPath();
      ctx.arc(x, y, 1.5, 0, Math.PI*2);
      ctx.fill();
    }

    // Draw key axes
    const nose  = landmarks[1];
    const left  = landmarks[234];
    const right = landmarks[454];
    const top   = landmarks[10];
    const bot   = landmarks[152];

    const px = x => (1 - x) * w;
    const py = y => y * h;

    ctx.strokeStyle = 'rgba(255, 80, 80, 0.8)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(px(left.x), py(left.y));
    ctx.lineTo(px(right.x), py(right.y));
    ctx.stroke();

    ctx.strokeStyle = 'rgba(80, 255, 80, 0.8)';
    ctx.beginPath();
    ctx.moveTo(px(top.x), py(top.y));
    ctx.lineTo(px(bot.x), py(bot.y));
    ctx.stroke();
  }

  // ─── Capture ─────────────────────────────────────────────────────────────

  function capturePhoto() {
    // Flash
    captureFlash?.classList.add('flash');
    setTimeout(() => captureFlash?.classList.remove('flash'), 200);

    // Composite video + wig onto a temp canvas
    const tmpCanvas = document.createElement('canvas');
    tmpCanvas.width  = videoEl.videoWidth  || 640;
    tmpCanvas.height = videoEl.videoHeight || 480;
    const ctx = tmpCanvas.getContext('2d');

    // Draw mirrored video
    ctx.save();
    ctx.translate(tmpCanvas.width, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(videoEl, 0, 0, tmpCanvas.width, tmpCanvas.height);
    ctx.restore();

    // Draw wig canvas on top (also mirrored)
    ctx.save();
    ctx.translate(tmpCanvas.width, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(wigCanvas, 0, 0, tmpCanvas.width, tmpCanvas.height);
    ctx.restore();

    const dataUrl = tmpCanvas.toDataURL('image/png');
    if (captureImg)  captureImg.src = dataUrl;
    if (captureDown) captureDown.href = dataUrl;
    captureOut?.classList.add('visible');
  }

  // ─── Resize Handling ─────────────────────────────────────────────────────

  function onResize() {
    const container = document.getElementById('camera-section');
    if (!container) return;
    const w = container.clientWidth;
    const h = container.clientHeight;

    wigCanvas.width    = w;
    wigCanvas.height   = h;
    debugCanvas.width  = w;
    debugCanvas.height = h;

    WigRenderer.resize(w, h);
  }

  // ─── Boot ─────────────────────────────────────────────────────────────────

  function boot() {
    buildWigGrid();
    buildColorGrid();

    // Initial wig load
    loadWig();

    // Size canvases
    onResize();
    window.addEventListener('resize', onResize);

    // Fade out instructions after 6s
    setTimeout(() => instrEl?.classList.add('fade-out'), 6000);

    // Buttons
    captureBtn?.addEventListener('click', capturePhoto);

    meshBtn?.addEventListener('click', () => {
      showMesh = !showMesh;
      meshBtn.classList.toggle('active', showMesh);
      meshBtn.textContent = showMesh ? 'Hide Mesh' : 'Show Mesh';
      debugCanvas.classList.toggle('visible', showMesh);
    });

    captureClose?.addEventListener('click', () => captureOut?.classList.remove('visible'));
    captureDown?.addEventListener('click', () => {
      captureDown.download = `wig-tryon-${Date.now()}.png`;
    });

    // Init Three.js renderer
    WigRenderer.init(wigCanvas, videoEl);
    onResize();

    // Init face tracker
    FaceTracker.init(videoEl, onFaceResults, () => {
      // Model loaded — hide loading overlay
      loadingEl?.classList.add('hidden');
      isInitialized = true;

      // Start render loop for when no face is detected (still render wig)
      requestAnimationFrame(idleRender);
    });
  }

  // Keep rendering even without face (so wig stays visible after face lost)
  function idleRender() {
    requestAnimationFrame(idleRender);
  }

  // Wait for DOM
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

})();
