/**
 * Quality-gate thresholds and processing parameters.
 * These are engineering defaults chosen for a 30 fps webcam. They have NOT been
 * validated against clinical data, and they are shown to users as-is.
 */
export const GATE = {
  /** Minimum fraction of frames with a tracked, open eye. */
  minValid: 0.75,
  /** Minimum measured frame rate (Hz). Fast phases cannot be resolved below this. */
  minFps: 20,
  /** Maximum frame-to-frame tracking noise (degrees, robust sigma from second differences). */
  maxNoise: 0.45,
  /** Minimum number of clean slow-phase windows before a statistic is reported. */
  minChunks: 8,
  /** Maximum 95% interval half-width (deg/s). */
  maxCI: 1.5,
  /**
   * Maximum ratio of slow-phase fit residual RMS to the frame-to-frame noise estimate.
   * Above this the trace does not look like straight slow phases plus noise (for example,
   * fast phases were missed or the slow phase is curved), so no velocity is reported.
   * Chosen on simulated tuning sets (seeds 7 and 2024); results are reported on held-out seed 99.
   */
  maxResidualRatio: 1.25,
  /** Live only: maximum head rotation (95th percentile, degrees) relative to the start of the recording. */
  maxHeadRotation: 2,
  /** Live only: minimum fraction of frames in which a face was detected. */
  minTracking: 0.85,
  /** Live only: allowed mean brightness range of the eye region frame (0-255). */
  minBrightness: 60,
  maxBrightness: 200,
  /** Live only: maximum RMS error of the 3-point calibration fit (degrees). */
  maxCalRms: 1.5,
  /** Live only: maximum fraction of frames dropped by the browser (gaps > 2.5 frame intervals). */
  maxDropped: 0.1,
} as const;

export const PROCESSING = {
  /** Median filter window (frames) applied before saccade detection and line fitting. Odd. 1 disables. */
  smoothWindow: 3,
  /**
   * Fast-phase (saccade) detection: a frame-to-frame velocity that differs from the local median
   * velocity (window localMedianSec) by more than max(minFastPhaseDev, fastPhaseK * sqrt(2) * noise * fps).
   */
  minFastPhaseDev: 15,
  fastPhaseK: 3,
  localMedianSec: 0.5,
  /** Samples dropped on each side of a detected fast phase (it may start or end between frames). */
  fastPhaseGuard: 1,
  /** Slow-phase fit window: at most this many seconds, at least minWindowSec and 4 frames. */
  maxWindowSec: 0.5,
  minWindowSec: 0.12,
  /** An eye is counted as blinking when lid gap / eye width is below this. */
  blinkOpenRatio: 0.14,
} as const;
