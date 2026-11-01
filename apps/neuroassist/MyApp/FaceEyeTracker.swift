import Foundation
import ARKit
import CoreMotion
import Observation
import simd

/// Dedicated serial background pipeline that stores recorded samples off the MainActor
/// and off ARKit's callback thread.
actor EyeSampleBufferActor {
    private var samples: [EyeSample] = []

    func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    func append(_ sample: EyeSample) {
        samples.append(sample)
    }

    func finish() -> [EyeSample] {
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }
}

/// Captures per-frame eye-movement scalars from ARFaceTrackingConfiguration + CoreMotion automotive status.
/// - Never records, saves, or accesses `frame.capturedImage` pixel buffers.
/// - Exposes normalized 2D iris & eye-corner positions for the Ready Check lock-on rings.
/// - Exposes real-time ARKit FPS, frame drops, ambient light lux, and thermal state for the Performance HUD.
@MainActor
@Observable
final class FaceEyeTracker: NSObject, ARSessionDelegate {

    private(set) var isTrueDepthSupported: Bool = ARFaceTrackingConfiguration.isSupported
    private(set) var isRunning: Bool = false
    private(set) var cameraPermissionDenied: Bool = false

    // Live telemetry (throttled ~20 Hz for calm UI rendering while recording stays full 60 Hz)
    private(set) var faceTracked: Bool = false
    private(set) var currentYawDeg: Double = 0.0
    var currentRawYawDeg: Double { currentYawDeg }
    private(set) var blinkLeft: Double = 0.0
    private(set) var blinkRight: Double = 0.0
    public var isBlink: Bool {
        (blinkLeft > 0.65 && blinkRight > 0.65) || blinkLeft > 0.80 || blinkRight > 0.80
    }
    private(set) var headYawDeg: Double = 0.0
    private(set) var headPitchDeg: Double = 0.0
    private(set) var distanceCm: Double = 0.0
    private(set) var ambientLightLux: Double = 1000.0
    private(set) var fps: Double = 0.0
    var frameRateFps: Double { fps }
    private(set) var droppedFrameCount: Int = 0
    private(set) var validSamplePercentage: Double = 100.0
    private(set) var rejectionReasonCounts: [EyeSample.FrameValidityReason: Int] = [:]
    private(set) var primaryRejectionReason: String? = nil
    private(set) var renderLatencyMs: Double = 1.2
    private(set) var signalProcessingLatencyMs: Double = 0.4
    private(set) var isHeadSteady: Bool = false
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    // Normalized 2D positions in the face guide oval [-1...+1] for iris lock rings & eye corner dots
    private(set) var leftIrisNormalized: CGPoint = CGPoint(x: -0.28, y: -0.08)
    private(set) var rightIrisNormalized: CGPoint = CGPoint(x: 0.28, y: -0.08)
    private(set) var leftEyeCornersNormalized: [CGPoint] = [CGPoint(x: -0.40, y: -0.08), CGPoint(x: -0.16, y: -0.08)]
    private(set) var rightEyeCornersNormalized: [CGPoint] = [CGPoint(x: 0.16, y: -0.08), CGPoint(x: 0.40, y: -0.08)]
    private(set) var irisLocked: Bool = false

    // CoreMotion driving lock ("Paused while you're moving")
    private(set) var isDrivingDetected: Bool = false
    @ObservationIgnored private let activityManager = CMMotionActivityManager()

    // Rolling 5-second buffer for Live Check chart
    private(set) var recentSamples: [EyeSample] = []

    // Active recording buffer for Calibration / Stripes test
    private(set) var isRecording: Bool = false
    private let bufferActor = EyeSampleBufferActor()
    private var activeRecordingMirror: [EyeSample] = []

    @ObservationIgnored private let arSession = ARSession()
    @ObservationIgnored private let acquisitionQueue = DispatchQueue(
        label: "com.neuroassist.arkit.acquisition",
        qos: .userInteractive
    )
    @ObservationIgnored nonisolated(unsafe) private var lastUIUpdateTimestamp: TimeInterval = 0.0
    private var recentTimestamps: [TimeInterval] = []

    override init() {
        super.init()
        arSession.delegate = self
        arSession.delegateQueue = acquisitionQueue
        startAutomotiveMonitoring()
    }

    private func startAutomotiveMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            // Only lock when CoreMotion reports high-confidence automotive motion
            let movingInVehicle = activity.automotive && !activity.stationary && activity.confidence == .high
            if self.isDrivingDetected != movingInVehicle {
                self.isDrivingDetected = movingInVehicle
            }
        }
    }

    func start() {
        isTrueDepthSupported = ARFaceTrackingConfiguration.isSupported
        thermalState = ProcessInfo.processInfo.thermalState
        guard isTrueDepthSupported else { return }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            launchARSession()
        case .notDetermined:
            Task { @MainActor [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted {
                    self.cameraPermissionDenied = false
                    self.launchARSession()
                } else {
                    self.cameraPermissionDenied = true
                }
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
        @unknown default:
            break
        }
    }

    private func launchARSession() {
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        arSession.pause()
        isRunning = false
        isRecording = false
    }

    func beginRecording() {
        activeRecordingMirror.removeAll(keepingCapacity: true)
        droppedFrameCount = 0
        isRecording = true
        Task {
            await bufferActor.reset()
        }
    }

    func currentRecordingSnapshot() -> [EyeSample] {
        activeRecordingMirror
    }

    func updateProcessingLatencyMs(_ ms: Double) {
        signalProcessingLatencyMs = ms
    }

    func finishRecording() -> [EyeSample] {
        isRecording = false
        let captured = activeRecordingMirror
        activeRecordingMirror.removeAll(keepingCapacity: true)
        Task {
            _ = await bufferActor.finish()
        }
        return captured
    }

    // MARK: - ARSessionDelegate (Dedicated Serial Acquisition Queue)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let callbackStart = CFAbsoluteTimeGetCurrent()
        let timestamp = frame.timestamp
        let ambientLux = Double(frame.lightEstimate?.ambientIntensity ?? 1000.0)
        let faceAnchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first

        let sample: EyeSample
        var lIris = CGPoint(x: -0.28, y: -0.08)
        var rIris = CGPoint(x: 0.28, y: -0.08)

        if let face = faceAnchor, face.isTracked {
            let leftYaw = Self.horizontalYawDegrees(from: face.leftEyeTransform)
            let rightYaw = Self.horizontalYawDegrees(from: face.rightEyeTransform)
            let avgEyeYaw = 0.5 * (leftYaw + rightYaw)

            let bLeft = face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0.0
            let bRight = face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0.0

            let (hYaw, hPitch) = Self.headYawAndPitchDegrees(from: face.transform)

            let camPos = simd_make_float3(frame.camera.transform.columns.3)
            let facePos = simd_make_float3(face.transform.columns.3)
            let distMeters = simd_distance(camPos, facePos)
            let distCm = Double(distMeters) * 100.0

            // Normalized iris offset inside face guide oval from head + eye transforms
            let normHeadX = max(-0.45, min(0.45, hYaw / 25.0))
            let normHeadY = max(-0.35, min(0.35, -hPitch / 25.0))
            let normEyeShift = max(-0.12, min(0.12, avgEyeYaw / 35.0))
            lIris = CGPoint(x: -0.27 + normHeadX + normEyeShift, y: -0.08 + normHeadY)
            rIris = CGPoint(x: 0.27 + normHeadX + normEyeShift, y: -0.08 + normHeadY)

            sample = EyeSample(
                timestamp: timestamp,
                rawYawDeg: avgEyeYaw,
                faceTracked: true,
                blinkLeft: bLeft,
                blinkRight: bRight,
                headYawDeg: hYaw,
                headPitchDeg: hPitch,
                distanceCm: distCm,
                ambientLightLux: ambientLux
            )
        } else {
            sample = EyeSample(
                timestamp: timestamp,
                rawYawDeg: 0.0,
                faceTracked: false,
                blinkLeft: 1.0,
                blinkRight: 1.0,
                headYawDeg: 0.0,
                headPitchDeg: 0.0,
                distanceCm: 0.0,
                ambientLightLux: ambientLux
            )
        }

        let shouldRefreshUI = (timestamp - lastUIUpdateTimestamp) >= 0.048
        if shouldRefreshUI {
            lastUIUpdateTimestamp = timestamp
        }

        let buffer = bufferActor
        Task {
            await buffer.append(sample)
        }

        let callbackMs = (CFAbsoluteTimeGetCurrent() - callbackStart) * 1000.0
        let capturedLIris = lIris
        let capturedRIris = rIris

        Task { @MainActor [weak self] in
            self?.ingestSample(
                sample,
                leftIris: capturedLIris,
                rightIris: capturedRIris,
                callbackLatencyMs: callbackMs,
                refreshLiveChart: shouldRefreshUI
            )
        }
    }

    private func ingestSample(
        _ sample: EyeSample,
        leftIris: CGPoint,
        rightIris: CGPoint,
        callbackLatencyMs: Double,
        refreshLiveChart: Bool
    ) {
        if let prevT = recentTimestamps.last {
            let dt = sample.timestamp - prevT
            if dt > (1.5 / 60.0) && dt < 1.0 {
                droppedFrameCount += max(1, Int(round(dt * 60.0)) - 1)
            }
        }
        recentTimestamps.append(sample.timestamp)
        let fpsCutoff = sample.timestamp - 1.5
        if let firstValidIdx = recentTimestamps.firstIndex(where: { $0 >= fpsCutoff }), firstValidIdx > 0 {
            recentTimestamps.removeFirst(firstValidIdx)
        }
        if recentTimestamps.count >= 2,
           let firstT = recentTimestamps.first,
           let lastT = recentTimestamps.last,
           lastT > firstT {
            fps = Double(recentTimestamps.count - 1) / (lastT - firstT)
        }

        if isRecording {
            activeRecordingMirror.append(sample)
        }

        // Maintain full 60 Hz rolling 5-second window for true gaze sampling statistics
        recentSamples.append(sample)
        let fiveSecCutoff = sample.timestamp - 5.0
        if let idx = recentSamples.firstIndex(where: { $0.timestamp >= fiveSecCutoff }), idx > 0 {
            recentSamples.removeFirst(idx)
        }

        if !recentSamples.isEmpty {
            var counts: [EyeSample.FrameValidityReason: Int] = [:]
            var validCount = 0
            for s in recentSamples {
                let reason = s.validityReason
                counts[reason, default: 0] += 1
                if reason == .valid { validCount += 1 }
            }
            rejectionReasonCounts = counts
            validSamplePercentage = (Double(validCount) / Double(recentSamples.count)) * 100.0
            let invalidCounts = counts.filter { $0.key != .valid }.sorted { $0.value > $1.value }
            primaryRejectionReason = invalidCounts.first?.key.humanDescription
        }

        guard refreshLiveChart else { return }
        let uiStart = CFAbsoluteTimeGetCurrent()

        let wasLocked = irisLocked
        faceTracked = sample.faceTracked
        currentYawDeg = sample.rawYawDeg
        blinkLeft = sample.blinkLeft
        blinkRight = sample.blinkRight
        headYawDeg = sample.headYawDeg
        headPitchDeg = sample.headPitchDeg
        distanceCm = sample.distanceCm
        ambientLightLux = sample.ambientLightLux
        thermalState = ProcessInfo.processInfo.thermalState

        leftIrisNormalized = leftIris
        rightIrisNormalized = rightIris
        leftEyeCornersNormalized = [
            CGPoint(x: leftIris.x - 0.11, y: leftIris.y + 0.01),
            CGPoint(x: leftIris.x + 0.11, y: leftIris.y + 0.01)
        ]
        rightEyeCornersNormalized = [
            CGPoint(x: rightIris.x - 0.11, y: rightIris.y + 0.01),
            CGPoint(x: rightIris.x + 0.11, y: rightIris.y + 0.01)
        ]

        let nowLocked = sample.faceTracked && !sample.isBlink
        irisLocked = nowLocked
        if nowLocked && !wasLocked {
            NeuroHaptics.selection()
        }

        let oneSecCutoff = sample.timestamp - 1.0
        let windowHead = recentSamples.filter { $0.timestamp >= oneSecCutoff && $0.faceTracked }
        if windowHead.count >= 5, let base = windowHead.first {
            let maxMove = windowHead.map {
                hypot($0.headYawDeg - base.headYawDeg, $0.headPitchDeg - base.headPitchDeg)
            }.max() ?? 99.0
            isHeadSteady = maxMove <= 1.5
        } else {
            isHeadSteady = false
        }

        renderLatencyMs = callbackLatencyMs + (CFAbsoluteTimeGetCurrent() - uiStart) * 1000.0
    }

    // MARK: - Pure Transform Math

    /// FIX #2: Computes horizontal eye yaw in degrees in the screen's visual direction
    /// (looking rightward on the screen = positive yaw angle).
    nonisolated private static func horizontalYawDegrees(from eyeTransform: simd_float4x4) -> Double {
        let forward = eyeTransform.columns.2
        // In ARFaceAnchor, +X is toward the subject's left (screen right when facing front camera),
        // and +Z points out of the face toward the screen. Negating X or calibrating ensures
        // rightward screen pursuit is positive.
        let yawRad = atan2(Double(-forward.x), Double(forward.z))
        return yawRad * 180.0 / .pi
    }

    nonisolated private static func headYawAndPitchDegrees(from faceTransform: simd_float4x4) -> (yaw: Double, pitch: Double) {
        let forward = faceTransform.columns.2
        let fx = Double(forward.x)
        let fy = Double(forward.y)
        let fz = Double(forward.z)
        let yaw = atan2(fx, -fz) * 180.0 / .pi
        let pitch = atan2(fy, sqrt(fx * fx + fz * fz)) * 180.0 / .pi
        return (yaw, pitch)
    }
}
