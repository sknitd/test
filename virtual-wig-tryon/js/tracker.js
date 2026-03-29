/**
 * tracker.js — MediaPipe Face Mesh integration
 * Detects face, provides image & world landmarks + head pose metrics.
 */

const FaceTracker = (function() {

  let faceMesh = null;
  let camera = null;
  let onResultsCb = null;
  let isReady = false;

  // ─── Init ─────────────────────────────────────────────────────────────────

  function init(videoEl, onResults, onLoaded) {
    onResultsCb = onResults;

    faceMesh = new FaceMesh({
      locateFile: (file) =>
        `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh@0.4.1633559619/${file}`
    });

    faceMesh.setOptions({
      maxNumFaces: 1,
      refineLandmarks: true,      // includes iris, lips refinement
      minDetectionConfidence: 0.5,
      minTrackingConfidence: 0.5,
    });

    faceMesh.onResults((results) => {
      if (onResultsCb) onResultsCb(results);
    });

    // Use MediaPipe Camera helper
    camera = new Camera(videoEl, {
      onFrame: async () => {
        if (faceMesh) await faceMesh.send({ image: videoEl });
      },
      width: 640,
      height: 480,
    });

    camera.start().then(() => {
      isReady = true;
      if (onLoaded) onLoaded();
    }).catch(err => {
      console.error('Camera start failed:', err);
      // Try fallback getUserMedia
      startFallbackCamera(videoEl, onLoaded);
    });
  }

  // Fallback: direct getUserMedia if Camera helper fails
  function startFallbackCamera(videoEl, onLoaded) {
    navigator.mediaDevices.getUserMedia({
      video: { width: 640, height: 480, facingMode: 'user' },
      audio: false
    }).then(stream => {
      videoEl.srcObject = stream;
      videoEl.play();

      const processFrame = async () => {
        if (faceMesh && videoEl.readyState >= 2) {
          await faceMesh.send({ image: videoEl });
        }
        requestAnimationFrame(processFrame);
      };

      videoEl.addEventListener('loadeddata', () => {
        isReady = true;
        if (onLoaded) onLoaded();
        processFrame();
      });
    }).catch(err => {
      console.error('Camera access denied:', err);
      alert('Camera access is required for the wig try-on app. Please allow camera permissions and refresh.');
    });
  }

  function stop() {
    if (camera) camera.stop();
    isReady = false;
  }

  return { init, stop, isReady: () => isReady };

})();
