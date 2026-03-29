/**
 * renderer.js — Three.js scene, lighting, and wig rendering
 */

const WigRenderer = (function() {

  let scene, camera, renderer, wigGroup = null;
  let ambientLight, dirLight, fillLight, rimLight;
  let containerEl, canvasEl;
  let videoWidth = 640, videoHeight = 480;

  // ─── Init ─────────────────────────────────────────────────────────────────

  function init(canvas, videoEl) {
    canvasEl = canvas;
    videoWidth = videoEl.videoWidth || 640;
    videoHeight = videoEl.videoHeight || 480;

    // Three.js renderer — transparent so video shows through
    renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.setClearColor(0x000000, 0);
    resize(videoEl.clientWidth || videoWidth, videoEl.clientHeight || videoHeight);

    // Orthographic camera matching video aspect
    setupCamera();

    // Scene
    scene = new THREE.Scene();
    setupLights();

    return renderer;
  }

  function setupCamera() {
    const aspect = canvasEl.width / canvasEl.height;
    // Frustum covers [−aspect/2 .. +aspect/2] × [−0.5 .. +0.5]
    camera = new THREE.OrthographicCamera(
      -aspect / 2, aspect / 2,
       0.5, -0.5,
       0.1, 100
    );
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
  }

  function resize(w, h) {
    renderer.setSize(w, h, false);
    if (camera) {
      const aspect = w / h;
      camera.left   = -aspect / 2;
      camera.right  =  aspect / 2;
      camera.top    =  0.5;
      camera.bottom = -0.5;
      camera.updateProjectionMatrix();
    }
  }

  function setupLights() {
    // Ambient
    ambientLight = new THREE.AmbientLight(0xffffff, 0.45);
    scene.add(ambientLight);

    // Key light (front-top)
    dirLight = new THREE.DirectionalLight(0xfff8f0, 1.1);
    dirLight.position.set(0.5, 1.5, 2);
    dirLight.castShadow = true;
    scene.add(dirLight);

    // Fill light (left)
    fillLight = new THREE.DirectionalLight(0xd0e8ff, 0.45);
    fillLight.position.set(-2, 0.5, 1);
    scene.add(fillLight);

    // Rim light (back)
    rimLight = new THREE.DirectionalLight(0xffeedd, 0.35);
    rimLight.position.set(0, 0.5, -2);
    scene.add(rimLight);
  }

  // ─── Coordinate Mapping ───────────────────────────────────────────────────

  /**
   * Convert MediaPipe normalized [0..1] image coords to Three.js world coords.
   * Note: video is mirrored (scaleX -1) on the display, but MediaPipe gives
   * un-mirrored coords — we mirror the X here to match the display.
   */
  function mpToWorld(mpX, mpY) {
    const aspect = canvasEl.width / canvasEl.height;
    // Mirror X to match CSS scaleX(-1)
    const wx = -(mpX - 0.5) * aspect;
    const wy = -(mpY - 0.5);
    return { x: wx, y: wy };
  }

  // ─── Head Pose from World Landmarks ──────────────────────────────────────

  /**
   * Compute head orientation quaternion from MediaPipe world landmarks.
   * Uses forehead→chin as Y-axis, and ear→ear as X-axis.
   */
  function computeHeadPose(worldLandmarks) {
    if (!worldLandmarks || worldLandmarks.length < 468) return new THREE.Quaternion();

    const lm = worldLandmarks;

    // Key anatomical points
    const forehead = new THREE.Vector3(lm[10].x, lm[10].y, lm[10].z);
    const chin     = new THREE.Vector3(lm[152].x, lm[152].y, lm[152].z);
    const leftEar  = new THREE.Vector3(lm[234].x, lm[234].y, lm[234].z);
    const rightEar = new THREE.Vector3(lm[454].x, lm[454].y, lm[454].z);

    // Up vector: chin → forehead (flip Y because MediaPipe Y is inverted)
    const up = new THREE.Vector3()
      .subVectors(forehead, chin)
      .normalize();
    up.y = -up.y; // Flip to match Three.js convention

    // Right vector: left ear → right ear (mirror for display)
    const right = new THREE.Vector3()
      .subVectors(rightEar, leftEar)
      .normalize();
    right.x = -right.x; // Mirror X

    // Forward = up × right (then renormalize)
    const forward = new THREE.Vector3().crossVectors(up, right).normalize();

    // Re-orthogonalise right
    right.crossVectors(forward, up).normalize();

    // Build rotation matrix from basis
    const mat = new THREE.Matrix4().makeBasis(right, up, forward);
    const quat = new THREE.Quaternion().setFromRotationMatrix(mat);
    return quat;
  }

  // ─── Face metrics from image landmarks ───────────────────────────────────

  function getFaceMetrics(imageLandmarks) {
    let minX = 1, maxX = 0, minY = 1, maxY = 0;
    let sumX = 0, sumY = 0;

    for (const lm of imageLandmarks) {
      if (lm.x < minX) minX = lm.x;
      if (lm.x > maxX) maxX = lm.x;
      if (lm.y < minY) minY = lm.y;
      if (lm.y > maxY) maxY = lm.y;
      sumX += lm.x;
      sumY += lm.y;
    }

    const n = imageLandmarks.length;
    return {
      centerX: sumX / n,
      centerY: sumY / n,
      faceWidth: maxX - minX,
      faceHeight: maxY - minY,
      minX, maxX, minY, maxY
    };
  }

  // ─── Update Wig Transform ─────────────────────────────────────────────────

  let smoothPos = new THREE.Vector3(0, 0, 0);
  let smoothQuat = new THREE.Quaternion();
  let smoothScale = 1.0;
  const SMOOTH = 0.35; // Lerp factor (higher = snappier)

  function updateWigTransform(imageLandmarks, worldLandmarks) {
    if (!wigGroup) return;

    const metrics = getFaceMetrics(imageLandmarks);
    const quat = computeHeadPose(worldLandmarks);
    const aspect = canvasEl.width / canvasEl.height;

    // ── Position: place wig at top of head (above forehead landmark) ──
    const foreheadLm = imageLandmarks[10]; // forehead top
    const { x: wx, y: wy } = mpToWorld(foreheadLm.x, foreheadLm.y);

    // Target world position — wig group origin sits at crown of head
    // We offset upward a bit based on head height
    const headHeightWorld = metrics.faceHeight * aspect * 0.5;
    const targetPos = new THREE.Vector3(
      wx,
      wy + headHeightWorld * 0.08, // slight upward nudge above forehead
      0
    );

    // ── Scale: use face width ──
    const targetScale = metrics.faceWidth * aspect * 1.02;

    // ── Smooth interpolation ──
    smoothPos.lerp(targetPos, SMOOTH);
    smoothQuat.slerp(quat, SMOOTH);
    smoothScale += (targetScale - smoothScale) * SMOOTH;

    wigGroup.position.copy(smoothPos);
    wigGroup.quaternion.copy(smoothQuat);
    wigGroup.scale.setScalar(smoothScale);
  }

  // ─── Wig Management ───────────────────────────────────────────────────────

  function setWig(group) {
    if (wigGroup) scene.remove(wigGroup);
    wigGroup = group;
    if (group) scene.add(group);
  }

  // ─── Render Loop ─────────────────────────────────────────────────────────

  function render() {
    if (renderer && scene && camera) {
      renderer.render(scene, camera);
    }
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  return {
    init,
    resize,
    setWig,
    updateWigTransform,
    render,
    getScene: () => scene,
    getRenderer: () => renderer,
  };

})();
