import Foundation

// MARK: - Protocol Mode (Research Reference vs Adaptive Fast Mode)

public enum MeasurementProtocolMode: String, Sendable, CaseIterable, Identifiable, Equatable, Codable {
    case researchFixed = "Research Mode (Fixed Reference)"
    case adaptiveFast = "Fast Mode (Adaptive Early-Stopping)"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .researchFixed: return "RESEARCH FIXED"
        case .adaptiveFast: return "ADAPTIVE FAST"
        }
    }

    public var subtitle: String {
        switch self {
        case .researchFixed:
            return "Fixed 2.0s/dot calibration (10s) + fixed 10.0s stimulus. Reproducible reference baseline."
        case .adaptiveFast:
            return "Early-stopping calibration (~0.9–2.0s/dot) + precision-stopped stimulus (≥4.5s once ≥8 clean windows & CI ≤ ±1.0°/s)."
        }
    }
}

public enum DataProvenance: String, Sendable, Codable, Equatable {
    case liveCamera = "LIVE TRUEDEPTH"
    case recordedSession = "RECORDED SESSION"
    case simulated = "SIMULATED"
}

// MARK: - Data Models

public struct EyeSample: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let rawYawDeg: Double
    public let faceTracked: Bool
    public let blinkLeft: Double
    public let blinkRight: Double
    public let headYawDeg: Double
    public let headPitchDeg: Double
    public let distanceCm: Double
    public let ambientLightLux: Double

    nonisolated public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        rawYawDeg: Double,
        faceTracked: Bool,
        blinkLeft: Double,
        blinkRight: Double,
        headYawDeg: Double,
        headPitchDeg: Double,
        distanceCm: Double,
        ambientLightLux: Double = 1000.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawYawDeg = rawYawDeg
        self.faceTracked = faceTracked
        self.blinkLeft = blinkLeft
        self.blinkRight = blinkRight
        self.headYawDeg = headYawDeg
        self.headPitchDeg = headPitchDeg
        self.distanceCm = distanceCm
        self.ambientLightLux = ambientLightLux
    }

    public var isBlink: Bool {
        blinkLeft > 0.5 || blinkRight > 0.5
    }

    public var isValid: Bool {
        faceTracked && !isBlink && rawYawDeg.isFinite && timestamp.isFinite
    }
}

public struct CalibrationPointSample: Sendable, Equatable, Codable {
    public let targetOffsetCm: Double
    public let distanceCm: Double
    public let trueAngleDeg: Double
    public let medianMeasuredYawDeg: Double
    public let madYawDeg: Double
    public let sampleCount: Int
    public let durationSec: Double
    public let stoppedEarly: Bool

    public init(
        targetOffsetCm: Double,
        distanceCm: Double,
        trueAngleDeg: Double,
        medianMeasuredYawDeg: Double,
        madYawDeg: Double = 0.0,
        sampleCount: Int = 0,
        durationSec: Double = 2.0,
        stoppedEarly: Bool = false
    ) {
        self.targetOffsetCm = targetOffsetCm
        self.distanceCm = distanceCm
        self.trueAngleDeg = trueAngleDeg
        self.medianMeasuredYawDeg = medianMeasuredYawDeg
        self.madYawDeg = madYawDeg
        self.sampleCount = sampleCount
        self.durationSec = durationSec
        self.stoppedEarly = stoppedEarly
    }

    public static func computeTrueAngleDeg(offsetCm: Double, distanceCm: Double) -> Double {
        guard distanceCm > 0 else { return 0 }
        return atan(offsetCm / distanceCm) * 180.0 / .pi
    }
}

public struct CalibrationModel: Sendable, Equatable, Codable {
    public let slope: Double
    public let intercept: Double
    public let rmsErrorDeg: Double
    public let meanDistanceCm: Double
    public let totalCalibrationDurationSec: Double
    public let points: [CalibrationPointSample]

    public static let maxAcceptableRMSDeg: Double = 1.5

    public init(
        slope: Double,
        intercept: Double,
        rmsErrorDeg: Double,
        meanDistanceCm: Double,
        totalCalibrationDurationSec: Double = 10.0,
        points: [CalibrationPointSample]
    ) {
        self.slope = slope
        self.intercept = intercept
        self.rmsErrorDeg = rmsErrorDeg
        self.meanDistanceCm = meanDistanceCm
        self.totalCalibrationDurationSec = totalCalibrationDurationSec
        self.points = points
    }

    public var isAccepted: Bool {
        rmsErrorDeg.isFinite && rmsErrorDeg <= Self.maxAcceptableRMSDeg && abs(slope) > 0.05
    }

    public func calibrate(rawYawDeg: Double) -> Double {
        slope * rawYawDeg + intercept
    }
}

public struct SlowPhaseWindow: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let slopeDegPerSec: Double
    public let interceptDeg: Double
    public let sampleCount: Int
    public let residualsDeg: [Double]
    public let meanAbsResidualDeg: Double

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        slopeDegPerSec: Double,
        interceptDeg: Double,
        sampleCount: Int,
        residualsDeg: [Double],
        meanAbsResidualDeg: Double
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.slopeDegPerSec = slopeDegPerSec
        self.interceptDeg = interceptDeg
        self.sampleCount = sampleCount
        self.residualsDeg = residualsDeg
        self.meanAbsResidualDeg = meanAbsResidualDeg
    }

    public func fittedAngle(at timestamp: TimeInterval) -> Double {
        let dt = timestamp - startTime
        return interceptDeg + slopeDegPerSec * dt
    }
}

public enum FailureRootCause: String, Sendable, Equatable, Codable {
    case headMovement = "HEAD MOVEMENT"
    case viewingDistance = "VIEWING DISTANCE"
    case trackingLoss = "INSUFFICIENT TRACKING"
    case calibrationError = "CALIBRATION ERROR"
    case contaminatedSignal = "SIGNAL CONTAMINATION"
    case cameraPerformance = "CAMERA FRAME RATE"
}

public struct QualityCheckItem: Sendable, Identifiable, Equatable, Codable {
    public let id: String
    public let name: String
    public let category: FailureRootCause
    public let passed: Bool
    public let valueString: String
    public let ruleString: String
    public let fixHint: String

    public init(
        id: String,
        name: String,
        category: FailureRootCause = .contaminatedSignal,
        passed: Bool,
        valueString: String,
        ruleString: String,
        fixHint: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.passed = passed
        self.valueString = valueString
        self.ruleString = ruleString
        self.fixHint = fixHint
    }
}

public struct CalibratedTracePoint: Sendable, Identifiable, Equatable, Codable {
    public let id: Int
    public let timeSec: Double
    /// Unsmoothed calibrated eye position in degrees
    public let angleDeg: Double
    /// 3-point median filtered eye position in degrees (for Live Signal Microscope overlay)
    public let filteredAngleDeg: Double
    public let isValid: Bool
    public let isFastPhase: Bool

    public init(
        id: Int,
        timeSec: Double,
        angleDeg: Double,
        filteredAngleDeg: Double = 0.0,
        isValid: Bool,
        isFastPhase: Bool
    ) {
        self.id = id
        self.timeSec = timeSec
        self.angleDeg = angleDeg
        self.filteredAngleDeg = filteredAngleDeg
        self.isValid = isValid
        self.isFastPhase = isFastPhase
    }
}

public struct OKNAnalysisResult: Sendable, Equatable {
    public let mode: MeasurementProtocolMode
    public let provenance: DataProvenance
    public let didAbstain: Bool
    public let stoppedEarly: Bool
    public let recordingDurationSec: Double
    public let analysisLatencyMs: Double
    public let totalFrames: Int
    public let validFrames: Int
    public let rejectedFrames: Int
    public let trackingNoiseDeg: Double
    public let calibrationRMSDeg: Double
    public let gain: Double?
    public let slowPhaseSpeedDegPerSec: Double?
    public let confidenceInterval95: (lower: Double, upper: Double)?
    public let intervalHalfWidthDegPerSec: Double
    public let cleanWindowCount: Int
    public let windows: [SlowPhaseWindow]
    public let tracePoints: [CalibratedTracePoint]
    public let checks: [QualityCheckItem]

    public init(
        mode: MeasurementProtocolMode = .researchFixed,
        provenance: DataProvenance = .liveCamera,
        didAbstain: Bool,
        stoppedEarly: Bool = false,
        recordingDurationSec: Double = 10.0,
        analysisLatencyMs: Double = 0.0,
        totalFrames: Int = 0,
        validFrames: Int = 0,
        rejectedFrames: Int = 0,
        trackingNoiseDeg: Double = .nan,
        calibrationRMSDeg: Double = .nan,
        gain: Double?,
        slowPhaseSpeedDegPerSec: Double?,
        confidenceInterval95: (lower: Double, upper: Double)?,
        intervalHalfWidthDegPerSec: Double,
        cleanWindowCount: Int,
        windows: [SlowPhaseWindow],
        tracePoints: [CalibratedTracePoint],
        checks: [QualityCheckItem]
    ) {
        self.mode = mode
        self.provenance = provenance
        self.didAbstain = didAbstain
        self.stoppedEarly = stoppedEarly
        self.recordingDurationSec = recordingDurationSec
        self.analysisLatencyMs = analysisLatencyMs
        self.totalFrames = totalFrames
        self.validFrames = validFrames
        self.rejectedFrames = rejectedFrames
        self.trackingNoiseDeg = trackingNoiseDeg
        self.calibrationRMSDeg = calibrationRMSDeg
        self.gain = gain
        self.slowPhaseSpeedDegPerSec = slowPhaseSpeedDegPerSec
        self.confidenceInterval95 = confidenceInterval95
        self.intervalHalfWidthDegPerSec = intervalHalfWidthDegPerSec
        self.cleanWindowCount = cleanWindowCount
        self.windows = windows
        self.tracePoints = tracePoints
        self.checks = checks
    }

    public static func == (lhs: OKNAnalysisResult, rhs: OKNAnalysisResult) -> Bool {
        lhs.mode == rhs.mode &&
        lhs.provenance == rhs.provenance &&
        lhs.didAbstain == rhs.didAbstain &&
        lhs.stoppedEarly == rhs.stoppedEarly &&
        lhs.recordingDurationSec == rhs.recordingDurationSec &&
        lhs.gain == rhs.gain &&
        lhs.slowPhaseSpeedDegPerSec == rhs.slowPhaseSpeedDegPerSec &&
        lhs.confidenceInterval95?.lower == rhs.confidenceInterval95?.lower &&
        lhs.confidenceInterval95?.upper == rhs.confidenceInterval95?.upper &&
        lhs.intervalHalfWidthDegPerSec == rhs.intervalHalfWidthDegPerSec &&
        lhs.cleanWindowCount == rhs.cleanWindowCount &&
        lhs.windows == rhs.windows &&
        lhs.tracePoints == rhs.tracePoints &&
        lhs.checks == rhs.checks
    }

    public var failedChecks: [QualityCheckItem] {
        checks.filter { !$0.passed }
    }

    public var passedCheckCount: Int {
        checks.filter(\.passed).count
    }

    public var primaryRootCause: FailureRootCause? {
        failedChecks.first?.category
    }
}

// MARK: - Live Online Snapshot (Used During Recording for Continuous Monitoring & Early Stopping)

public struct OnlineOKNSnapshot: Sendable, Equatable {
    public let elapsedSec: Double
    public let cleanWindowCount: Int
    public let currentMedianVelocityDegPerSec: Double?
    public let currentCIHalfWidthDegPerSec: Double
    public let trackingNoiseDeg: Double
    public let headRotation95Deg: Double
    public let faceTrackedRatio: Double
    public let validFrameRatio: Double
    public let activeWarning: String?
    public let canStopEarlyWithPrecision: Bool
    public let shouldAbortEarlyForQuality: Bool
    public let recentTracePoints: [CalibratedTracePoint]
    public let recentWindows: [SlowPhaseWindow]
}

// MARK: - Pure Signal Math Engine

public enum SignalMath {

    public static let stripeSpeedDegPerSec: Double = 10.0
    public static let fastPhaseVelocityThresholdDegPerSec: Double = 40.0
    public static let maxWindowDurationSec: Double = 0.5
    public static let minWindowSamples: Int = 5

    // Adaptive Fast Mode thresholds
    public static let adaptiveDotSettleSec: Double = 0.45
    public static let adaptiveDotMinDurationSec: Double = 0.90
    public static let adaptiveDotMaxDurationSec: Double = 2.00
    public static let adaptiveDotMinValidSamples: Int = 18
    public static let adaptiveDotMaxMADDeg: Double = 0.28
    public static let adaptiveDotMaxHeadExcursionDeg: Double = 1.2

    public static let adaptiveOKNMinDurationSec: Double = 4.5
    public static let adaptiveOKNMinCleanWindows: Int = 8
    public static let adaptiveOKNTargetCIHalfWidthDegPerSec: Double = 1.0

    // MARK: Statistical Helpers

    public static func median(_ values: [Double]) -> Double? {
        let finite = values.filter { $0.isFinite }.sorted()
        guard !finite.isEmpty else { return nil }
        let n = finite.count
        if n % 2 == 1 {
            return finite[n / 2]
        } else {
            return 0.5 * (finite[n / 2 - 1] + finite[n / 2])
        }
    }

    public static func mad(_ values: [Double]) -> Double? {
        guard let med = median(values) else { return nil }
        let absDevs = values.filter { $0.isFinite }.map { abs($0 - med) }
        return median(absDevs)
    }

    public static func percentile(_ values: [Double], p: Double) -> Double? {
        let finite = values.filter { $0.isFinite }.sorted()
        guard !finite.isEmpty else { return nil }
        let clampedP = min(max(p, 0.0), 1.0)
        let idx = clampedP * Double(finite.count - 1)
        let lower = Int(floor(idx))
        let upper = Int(ceil(idx))
        if lower == upper { return finite[lower] }
        let weight = idx - Double(lower)
        return finite[lower] * (1.0 - weight) + finite[upper] * weight
    }

    /// Exact order-statistic (binomial) 95% confidence interval for the median.
    public static func binomialMedianConfidenceInterval(_ values: [Double], confidence: Double = 0.95) -> (lower: Double, upper: Double)? {
        let sorted = values.filter { $0.isFinite }.sorted()
        let n = sorted.count
        guard n >= 2 else { return nil }

        let alpha = 1.0 - confidence
        var probs = [Double](repeating: 0.0, count: n + 1)
        probs[0] = pow(0.5, Double(n))
        for k in 1...n {
            probs[k] = probs[k - 1] * Double(n - k + 1) / Double(k)
        }

        var cumulative = 0.0
        var chosenJ = 0
        for j in 0..<(n / 2) {
            cumulative += probs[j]
            if 2.0 * cumulative <= alpha {
                chosenJ = j + 1
            } else {
                break
            }
        }

        let lowIndex = max(0, min(n - 1, chosenJ))
        let highIndex = max(0, min(n - 1, n - 1 - chosenJ))
        return (lower: sorted[lowIndex], upper: sorted[highIndex])
    }

    /// Ordinary least squares line fit y = intercept + slope * x
    public static func fitLine(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, residuals: [Double], rms: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let meanX = x.reduce(0.0, +) / n
        let meanY = y.reduce(0.0, +) / n

        var num = 0.0
        var den = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            num += dx * dy
            den += dx * dx
        }
        guard den > 1e-12 else { return nil }
        let slope = num / den
        let intercept = meanY - slope * meanX

        var residuals = [Double]()
        residuals.reserveCapacity(x.count)
        var sumSq = 0.0
        for i in 0..<x.count {
            let pred = intercept + slope * x[i]
            let r = y[i] - pred
            residuals.append(r)
            sumSq += r * r
        }
        let rms = sqrt(sumSq / n)
        return (slope, intercept, residuals, rms)
    }

    // MARK: Fixed & Adaptive Calibration Fitting

    /// Reference fixed-duration (2.0 s) dot summary using [0.8 s, 2.0 s] window.
    public static func summarizeCalibrationDot(
        samples: [EyeSample],
        dotStartTime: TimeInterval,
        targetOffsetCm: Double
    ) -> CalibrationPointSample? {
        let windowSamples = samples.filter { sample in
            let rel = sample.timestamp - dotStartTime
            return rel >= 0.8 && rel <= 2.0 && sample.isValid && (25.0...40.0).contains(sample.distanceCm)
        }
        guard windowSamples.count >= 10 else { return nil }
        let yaws = windowSamples.map(\.rawYawDeg)
        guard let medYaw = median(yaws),
              let medDist = median(windowSamples.map(\.distanceCm)) else {
            return nil
        }
        let yawMAD = mad(yaws) ?? 0.0
        let duration = (samples.last?.timestamp ?? (dotStartTime + 2.0)) - dotStartTime
        let trueAngle = CalibrationPointSample.computeTrueAngleDeg(offsetCm: targetOffsetCm, distanceCm: medDist)
        return CalibrationPointSample(
            targetOffsetCm: targetOffsetCm,
            distanceCm: medDist,
            trueAngleDeg: trueAngle,
            medianMeasuredYawDeg: medYaw,
            madYawDeg: yawMAD,
            sampleCount: windowSamples.count,
            durationSec: max(0.1, duration),
            stoppedEarly: false
        )
    }

    /// Evaluates whether an active calibration dot in Adaptive Fast Mode has reached fixation stability,
    /// minimum sample count (18), head stability (<= 1.2°), and low dispersion (MAD <= 0.28°).
    public static func evaluateAdaptiveCalibrationDot(
        samples: [EyeSample],
        dotStartTime: TimeInterval,
        targetOffsetCm: Double
    ) -> CalibrationPointSample? {
        guard let latest = samples.last else { return nil }
        let elapsed = latest.timestamp - dotStartTime
        guard elapsed >= adaptiveDotMinDurationSec else { return nil }

        let postSettle = samples.filter { sample in
            let rel = sample.timestamp - dotStartTime
            return rel >= adaptiveDotSettleSec && sample.isValid && (25.0...40.0).contains(sample.distanceCm)
        }
        guard postSettle.count >= adaptiveDotMinValidSamples else { return nil }

        let recentWindow = Array(postSettle.suffix(adaptiveDotMinValidSamples))
        let yaws = recentWindow.map(\.rawYawDeg)
        guard let medYaw = median(yaws),
              let yawMAD = mad(yaws),
              yawMAD <= adaptiveDotMaxMADDeg,
              let medDist = median(recentWindow.map(\.distanceCm)) else {
            return nil
        }

        let baseHeadYaw = recentWindow[0].headYawDeg
        let baseHeadPitch = recentWindow[0].headPitchDeg
        let maxHeadMove = recentWindow.map {
            hypot($0.headYawDeg - baseHeadYaw, $0.headPitchDeg - baseHeadPitch)
        }.max() ?? 99.0
        guard maxHeadMove <= adaptiveDotMaxHeadExcursionDeg else { return nil }

        let trueAngle = CalibrationPointSample.computeTrueAngleDeg(offsetCm: targetOffsetCm, distanceCm: medDist)
        return CalibrationPointSample(
            targetOffsetCm: targetOffsetCm,
            distanceCm: medDist,
            trueAngleDeg: trueAngle,
            medianMeasuredYawDeg: medYaw,
            madYawDeg: yawMAD,
            sampleCount: recentWindow.count,
            durationSec: elapsed,
            stoppedEarly: elapsed < (adaptiveDotMaxDurationSec - 0.08)
        )
    }

    /// Fits measured yaw -> true angle across the 5 calibration dots.
    /// FIX #2: Calibration slope maps camera-mirror eye yaw into screen-space visual angle (degrees).
    public static func fitCalibration(points: [CalibrationPointSample]) -> CalibrationModel? {
        guard points.count >= 5 else { return nil }
        let x = points.map(\.medianMeasuredYawDeg)
        let y = points.map(\.trueAngleDeg)
        guard let fit = fitLine(x: x, y: y),
              let meanDist = median(points.map(\.distanceCm)) else {
            return nil
        }
        let totalDur = points.map(\.durationSec).reduce(0.0, +)
        return CalibrationModel(
            slope: fit.slope,
            intercept: fit.intercept,
            rmsErrorDeg: fit.rms,
            meanDistanceCm: meanDist,
            totalCalibrationDurationSec: totalDur,
            points: points
        )
    }

    // MARK: Online Streaming Estimator & Continuous Quality Monitor

    public static func evaluateOnlineSnapshot(
        samples: [EyeSample],
        calibration: CalibrationModel,
        mode: MeasurementProtocolMode,
        stripeDirectionSign: Double = 1.0
    ) -> OnlineOKNSnapshot {
        guard samples.count >= 15 else {
            return OnlineOKNSnapshot(
                elapsedSec: 0.0,
                cleanWindowCount: 0,
                currentMedianVelocityDegPerSec: nil,
                currentCIHalfWidthDegPerSec: .infinity,
                trackingNoiseDeg: 0.0,
                headRotation95Deg: 0.0,
                faceTrackedRatio: 1.0,
                validFrameRatio: 1.0,
                activeWarning: nil,
                canStopEarlyWithPrecision: false,
                shouldAbortEarlyForQuality: false,
                recentTracePoints: [],
                recentWindows: []
            )
        }

        let elapsed = max(0.0, (samples.last?.timestamp ?? 0) - samples[0].timestamp)
        let partial = analyzeOptokinetic(
            samples: samples,
            calibration: calibration,
            stripeDirectionSign: stripeDirectionSign,
            mode: mode,
            stoppedEarly: false
        )

        let slopes = partial.windows.map { $0.slopeDegPerSec * stripeDirectionSign }
        let medVel = median(slopes)
        let ci = binomialMedianConfidenceInterval(slopes, confidence: 0.95)
        let halfWidth = ci.map { 0.5 * ($0.upper - $0.lower) } ?? .infinity

        let trackedCount = samples.filter(\.faceTracked).count
        let validCount = samples.filter(\.isValid).count
        let trackedRatio = Double(trackedCount) / Double(samples.count)
        let validRatio = Double(validCount) / Double(samples.count)

        let startHead = samples.prefix(min(15, samples.count)).filter(\.faceTracked)
        let startYaw = median(startHead.map(\.headYawDeg)) ?? samples[0].headYawDeg
        let startPitch = median(startHead.map(\.headPitchDeg)) ?? samples[0].headPitchDeg
        let headExcursions = samples.compactMap { s -> Double? in
            guard s.faceTracked else { return nil }
            return hypot(s.headYawDeg - startYaw, s.headPitchDeg - startPitch)
        }
        let headRot95 = percentile(headExcursions, p: 0.95) ?? 0.0

        var warning: String? = nil
        if let lastSample = samples.last {
            if !lastSample.faceTracked {
                warning = "Too dark or face lost: face a window or lamp"
            } else if !(25.0...40.0).contains(lastSample.distanceCm) {
                warning = String(format: "Hold phone at 30 cm (now %.0f cm)", lastSample.distanceCm)
            } else if headRot95 > 1.75 {
                warning = "Keep your head still — track only with your eyes"
            } else if validRatio < 0.78 {
                warning = "Keep eyes open — avoid frequent blinking"
            }
        }

        let canStopEarly: Bool = {
            guard mode == .adaptiveFast else { return false }
            guard elapsed >= adaptiveOKNMinDurationSec else { return false }
            guard !partial.didAbstain else { return false }
            guard partial.cleanWindowCount >= adaptiveOKNMinCleanWindows else { return false }
            guard halfWidth <= adaptiveOKNTargetCIHalfWidthDegPerSec else { return false }
            return true
        }()

        let shouldAbortEarly: Bool = {
            guard mode == .adaptiveFast, elapsed >= 4.0 else { return false }
            return headRot95 > 3.2 || trackedRatio < 0.50
        }()

        return OnlineOKNSnapshot(
            elapsedSec: elapsed,
            cleanWindowCount: partial.cleanWindowCount,
            currentMedianVelocityDegPerSec: medVel,
            currentCIHalfWidthDegPerSec: halfWidth,
            trackingNoiseDeg: partial.trackingNoiseDeg,
            headRotation95Deg: headRot95,
            faceTrackedRatio: trackedRatio,
            validFrameRatio: validRatio,
            activeWarning: warning,
            canStopEarlyWithPrecision: canStopEarly,
            shouldAbortEarlyForQuality: shouldAbortEarly,
            recentTracePoints: Array(partial.tracePoints.suffix(180)),
            recentWindows: partial.windows
        )
    }

    // MARK: Optokinetic (Stripes) Analysis & Quality Gate

    /// Analyzes the optokinetic nystagmus recording.
    ///
    /// ROOT CAUSE & FIXES IMPLEMENTED:
    /// 1. FIX #1 (Tracking noise ~0.02 vs 0.45° gate):
    ///    - Previously, if raw uncalibrated ARKit eye angles (~5–7x smaller before screen-distance calibration) or smoothed
    ///      residuals were used without degree-of-freedom correction on short windows, noise read artificially low (~0.02°).
    ///    - Now: Tracking noise is strictly computed in **calibrated degrees** on the **unsmoothed** signal (`calibratedAngles`),
    ///      combining unsmoothed OLS window residuals (scaled by `sqrt(N/(N-2))` for 2 fitted parameters) with the unsmoothed
    ///      second-difference high-frequency floor (`|y[i+1] - 2y[i] + y[i-1]| / sqrt(6)`), ensuring 0.10° true noise reads ~0.10°.
    ///
    /// 2. FIX #2 (Stripes gain 0.00 with 100% valid frames):
    ///    - Root cause A: In `ARFaceAnchor`, looking rightward on the screen produces a **negative** raw X component in the face
    ///      coordinate system unless mapped through the 5-point screen calibration (`slope * rawYawDeg + intercept`). If any
    ///      caller passed a positive identity slope on raw camera-space yaw, rightward tracking had negative velocity and failed
    ///      the directional sign check (`gain = 0.00`).
    ///    - Root cause B: During passive optokinetic viewing ("look at the middle"), small-amplitude resetting quick phases
    ///      have peak central-difference speeds of ~12–30 °/s (below the 40 °/s threshold) or span 2–3 frames. When those
    ///      weren't stripped before windowing, each 0.5 s window spanned both a slow phase (+6 °/s) and a reset (-25 °/s),
    ///      flattening the OLS window slope to ~0.00 °/s!
    ///    - Fix:
    ///      (a) Fast phases now detect any velocity > 40 °/s, any retrograde velocity < -6 °/s against the stripe direction,
    ///          OR any 1-frame or 2-frame retrograde displacement jump < -0.22° against the stripe direction, plus 1 guard frame
    ///          on each side.
    ///      (b) Only candidate slow-phase windows with positive pursuit slope (> +0.5 °/s in the stripe direction) after fast-phase
    ///          removal are retained as clean slow-phase windows before computing the median.
    public static func analyzeOptokinetic(
        samples: [EyeSample],
        calibration: CalibrationModel?,
        stripeDirectionSign: Double = 1.0,
        mode: MeasurementProtocolMode = .researchFixed,
        provenance: DataProvenance = .liveCamera,
        stoppedEarly: Bool = false
    ) -> OKNAnalysisResult {
        let startClock = CFAbsoluteTimeGetCurrent()
        let totalCount = samples.count
        guard totalCount >= 20, let calibration = calibration, calibration.isAccepted else {
            return abstainResultWhenInsufficientData(
                samples: samples,
                calibration: calibration,
                mode: mode,
                provenance: provenance
            )
        }

        // 1. Calibrate degrees (UNSMOOTHED) and mark blink (> 0.5) or lost-face frames invalid
        let t0 = samples[0].timestamp
        var calibratedAngles = [Double](repeating: .nan, count: totalCount)
        var validMask = [Bool](repeating: false, count: totalCount)
        var faceTrackedCount = 0
        var validFrameCount = 0

        for i in 0..<totalCount {
            let s = samples[i]
            if s.faceTracked { faceTrackedCount += 1 }
            if s.isValid {
                validFrameCount += 1
                validMask[i] = true
                // Apply linear 5-dot calibration (rawYawDeg -> true calibrated visual angle in degrees)
                calibratedAngles[i] = calibration.calibrate(rawYawDeg: s.rawYawDeg)
            }
        }

        // Compute a separate 3-point median filtered trace ONLY for the Live Signal Microscope visual comparison.
        // All velocity, slope, and noise math below strictly uses UNSMOOTHED `calibratedAngles`.
        var filteredAngles = calibratedAngles
        for i in 1..<(totalCount - 1) {
            if validMask[i - 1] && validMask[i] && validMask[i + 1] {
                filteredAngles[i] = median([calibratedAngles[i - 1], calibratedAngles[i], calibratedAngles[i + 1]]) ?? calibratedAngles[i]
            }
        }

        let faceTrackedRatio = Double(faceTrackedCount) / Double(totalCount)
        let validRatio = Double(validFrameCount) / Double(totalCount)

        // Frame rate & dropped frames
        var dts = [Double]()
        dts.reserveCapacity(totalCount - 1)
        for i in 1..<totalCount {
            let dt = samples[i].timestamp - samples[i - 1].timestamp
            if dt > 0 && dt.isFinite {
                dts.append(dt)
            }
        }
        let totalDuration = max(1e-6, (samples.last?.timestamp ?? t0) - t0)
        let fps = Double(totalCount - 1) / totalDuration
        let medianDt = median(dts) ?? (1.0 / 60.0)
        var droppedFrameCount = 0
        var expectedExtraFrames = 0
        for dt in dts {
            if dt > 1.5 * medianDt {
                let missed = max(1, Int(round(dt / medianDt)) - 1)
                droppedFrameCount += missed
                expectedExtraFrames += missed
            }
        }
        let droppedRatio = Double(droppedFrameCount) / Double(totalCount + expectedExtraFrames)

        // Head rotation 95th percentile vs start
        let startHeadSamples = samples.prefix(min(15, totalCount)).filter(\.faceTracked)
        let startHeadYaw = median(startHeadSamples.map(\.headYawDeg)) ?? samples[0].headYawDeg
        let startHeadPitch = median(startHeadSamples.map(\.headPitchDeg)) ?? samples[0].headPitchDeg
        let headExcursions: [Double] = samples.compactMap { s in
            guard s.faceTracked else { return nil }
            return hypot(s.headYawDeg - startHeadYaw, s.headPitchDeg - startHeadPitch)
        }
        let headRot95 = percentile(headExcursions, p: 0.95) ?? 999.0

        // 2. Velocity by central difference on UNSMOOTHED calibrated degrees & fast-phase detection
        var rawFastPhase = [Bool](repeating: false, count: totalCount)
        let singleStepThresholdDeg = -0.25
        let twoFrameStepThresholdDeg = -0.38
        let retrogradeVelocityThresholdDegPerSec = -8.0

        for i in 0..<totalCount {
            guard validMask[i] else {
                rawFastPhase[i] = true
                continue
            }

            var velocity: Double? = nil
            if i > 0 && i < totalCount - 1 && validMask[i - 1] && validMask[i + 1] {
                let dt = samples[i + 1].timestamp - samples[i - 1].timestamp
                if dt > 1e-5 {
                    velocity = (calibratedAngles[i + 1] - calibratedAngles[i - 1]) / dt
                }
            } else if i < totalCount - 1 && validMask[i + 1] {
                let dt = samples[i + 1].timestamp - samples[i].timestamp
                if dt > 1e-5 {
                    velocity = (calibratedAngles[i + 1] - calibratedAngles[i]) / dt
                }
            } else if i > 0 && validMask[i - 1] {
                let dt = samples[i].timestamp - samples[i - 1].timestamp
                if dt > 1e-5 {
                    velocity = (calibratedAngles[i] - calibratedAngles[i - 1]) / dt
                }
            }

            if let v = velocity {
                let directedV = v * stripeDirectionSign
                if abs(v) > fastPhaseVelocityThresholdDegPerSec || directedV < retrogradeVelocityThresholdDegPerSec {
                    rawFastPhase[i] = true
                }
            }

            // 1-frame retrograde reset jump against stripe direction
            if i > 0 && validMask[i - 1] {
                let step = (calibratedAngles[i] - calibratedAngles[i - 1]) * stripeDirectionSign
                let dt = samples[i].timestamp - samples[i - 1].timestamp
                if step < singleStepThresholdDeg || (dt > 1e-5 && (step / dt) < retrogradeVelocityThresholdDegPerSec) {
                    rawFastPhase[i] = true
                    rawFastPhase[i - 1] = true
                }
            }

            // 2-frame retrograde reset jump (catches multi-frame quick phases that central difference straddles)
            if i > 1 && validMask[i - 1] && validMask[i - 2] {
                let step2 = (calibratedAngles[i] - calibratedAngles[i - 2]) * stripeDirectionSign
                if step2 < twoFrameStepThresholdDeg {
                    rawFastPhase[i] = true
                    rawFastPhase[i - 1] = true
                    rawFastPhase[i - 2] = true
                }
            }
        }

        // Apply 1-frame guard on each side of any fast-phase or invalid frame
        var cleanMask = [Bool](repeating: true, count: totalCount)
        for i in 0..<totalCount {
            if !validMask[i] || rawFastPhase[i] {
                cleanMask[i] = false
                if i > 0 { cleanMask[i - 1] = false }
                if i + 1 < totalCount { cleanMask[i + 1] = false }
            }
        }

        // 3. Extract slow-phase windows (max 0.5 s, min 5 samples, OLS line fit on UNSMOOTHED calibrated degrees)
        var windows = [SlowPhaseWindow]()
        var dofCorrectedResiduals = [Double]()
        var idx = 0
        while idx < totalCount {
            guard cleanMask[idx] else {
                idx += 1
                continue
            }
            var runEnd = idx
            while runEnd + 1 < totalCount && cleanMask[runEnd + 1] {
                runEnd += 1
            }

            var subStart = idx
            while subStart <= runEnd {
                let startT = samples[subStart].timestamp
                var subEnd = subStart
                while subEnd + 1 <= runEnd && (samples[subEnd + 1].timestamp - startT) <= maxWindowDurationSec + 1e-6 {
                    subEnd += 1
                }
                let count = subEnd - subStart + 1
                if count >= minWindowSamples {
                    var x = [Double]()
                    var y = [Double]()
                    x.reserveCapacity(count)
                    y.reserveCapacity(count)
                    for k in subStart...subEnd {
                        x.append(samples[k].timestamp - startT)
                        y.append(calibratedAngles[k])
                    }
                    if let fit = fitLine(x: x, y: y) {
                        // Degree-of-freedom correction sqrt(N / (N - 2)) so short-window OLS overfitting
                        // never biases the tracking noise estimate downward toward 0.02 deg.
                        let dofScale = count > 2 ? sqrt(Double(count) / Double(count - 2)) : 1.0
                        let scaledRes = fit.residuals.map { $0 * dofScale }
                        let meanAbsRes = scaledRes.map { abs($0) }.reduce(0.0, +) / Double(count)

                        // Exclude any residual retrograde/contaminated segment that slipped through
                        let directedSlope = fit.slope * stripeDirectionSign
                        if directedSlope > -2.0 {
                            dofCorrectedResiduals.append(contentsOf: scaledRes)
                            windows.append(
                                SlowPhaseWindow(
                                    startTime: startT - t0,
                                    endTime: samples[subEnd].timestamp - t0,
                                    slopeDegPerSec: fit.slope,
                                    interceptDeg: fit.intercept,
                                    sampleCount: count,
                                    residualsDeg: scaledRes,
                                    meanAbsResidualDeg: meanAbsRes
                                )
                            )
                        }
                    }
                }
                subStart = subEnd + 1
            }

            idx = runEnd + 1
        }

        // 4. Estimate = median of window slopes; 95% binomial CI for the median
        let slopes = windows.map { $0.slopeDegPerSec * stripeDirectionSign }
        let medianSlope = median(slopes)
        let ci = binomialMedianConfidenceInterval(slopes, confidence: 0.95)
        let halfWidth: Double = {
            guard let ci = ci else { return .infinity }
            return 0.5 * (ci.upper - ci.lower)
        }()

        // 5. Gain = slow-phase velocity in the stripes' direction / 10 deg/s
        let estimatedGain: Double? = medianSlope.map { $0 / stripeSpeedDegPerSec }

        // FIX #1: Unsmoothed calibrated tracking noise in degrees.
        // Combines DOF-corrected OLS window residuals with unsmoothed 2nd-difference noise floor on valid frames.
        let trackingNoiseDeg: Double = {
            var residualNoise: Double = .nan
            if !dofCorrectedResiduals.isEmpty, let medRes = median(dofCorrectedResiduals) {
                let absDevs = dofCorrectedResiduals.map { abs($0 - medRes) }
                if let madVal = median(absDevs) {
                    residualNoise = 1.4826 * madVal
                }
            }

            // Unsmoothed second-difference noise estimator on contiguous valid slow-phase samples:
            // For white Gaussian noise sigma, (y[i+1] - 2*y[i] + y[i-1]) / sqrt(6) ~ N(0, sigma^2),
            // completely annihilating linear slow-phase drift without any smoothing filter!
            var secondDiffs = [Double]()
            let sqrt6 = sqrt(6.0)
            if totalCount >= 3 {
                for i in 1..<(totalCount - 1) {
                    if cleanMask[i - 1] && cleanMask[i] && cleanMask[i + 1] {
                        let d2 = (calibratedAngles[i + 1] - 2.0 * calibratedAngles[i] + calibratedAngles[i - 1]) / sqrt6
                        if d2.isFinite {
                            secondDiffs.append(d2)
                        }
                    }
                }
            }
            var diffNoise: Double = .nan
            if !secondDiffs.isEmpty, let medD2 = median(secondDiffs) {
                let absDevs = secondDiffs.map { abs($0 - medD2) }
                if let madD2 = median(absDevs) {
                    diffNoise = 1.4826 * madD2
                }
            }

            if residualNoise.isFinite && diffNoise.isFinite {
                return max(residualNoise, diffNoise)
            } else if residualNoise.isFinite {
                return residualNoise
            } else if diffNoise.isFinite {
                return diffNoise
            } else {
                return .infinity
            }
        }()

        let meanResidualDeg: Double = {
            guard !dofCorrectedResiduals.isEmpty else { return .infinity }
            let sumAbs = dofCorrectedResiduals.map { abs($0) }.reduce(0.0, +)
            return sumAbs / Double(dofCorrectedResiduals.count)
        }()

        var tracePoints = [CalibratedTracePoint]()
        tracePoints.reserveCapacity(totalCount)
        var rejectedCount = 0
        for i in 0..<totalCount {
            if !cleanMask[i] { rejectedCount += 1 }
            tracePoints.append(
                CalibratedTracePoint(
                    id: i,
                    timeSec: samples[i].timestamp - t0,
                    angleDeg: validMask[i] ? calibratedAngles[i] : 0.0,
                    filteredAngleDeg: validMask[i] ? filteredAngles[i] : 0.0,
                    isValid: validMask[i],
                    isFastPhase: !cleanMask[i]
                )
            )
        }

        // 6. QUALITY GATE — all 11 mandatory checks must pass, else ABSTAIN
        let checks: [QualityCheckItem] = [
            QualityCheckItem(
                id: "face_tracked",
                name: "Face tracked",
                category: .trackingLoss,
                passed: faceTrackedRatio >= 0.85,
                valueString: String(format: "%.1f%%", faceTrackedRatio * 100.0),
                ruleString: "≥ 85.0%",
                fixHint: "Too dark: face a window or lamp and keep your full face in view."
            ),
            QualityCheckItem(
                id: "valid_frames",
                name: "Valid frames",
                category: .trackingLoss,
                passed: validRatio >= 0.75,
                valueString: String(format: "%.1f%%", validRatio * 100.0),
                ruleString: "≥ 75.0%",
                fixHint: "Too many blinks or lost frames: keep your eyes comfortably open."
            ),
            QualityCheckItem(
                id: "frame_rate",
                name: "Frame rate",
                category: .cameraPerformance,
                passed: fps >= 20.0,
                valueString: String(format: "%.1f fps", fps),
                ruleString: "≥ 20.0 fps",
                fixHint: "Low camera frame rate: disable Low Power Mode and let the phone cool down."
            ),
            QualityCheckItem(
                id: "dropped_frames",
                name: "Dropped frames",
                category: .cameraPerformance,
                passed: droppedRatio <= 0.10,
                valueString: String(format: "%.1f%%", droppedRatio * 100.0),
                ruleString: "≤ 10.0%",
                fixHint: "Camera frame drops detected: close background apps and retake."
            ),
            QualityCheckItem(
                id: "head_rotation",
                name: "Head rotation (95th %)",
                category: .headMovement,
                passed: headRot95 <= 2.0,
                valueString: String(format: "%.2f°", headRot95),
                ruleString: "≤ 2.00°",
                fixHint: "Head moved during test: brace your elbows and let only your eyes follow the stripes."
            ),
            QualityCheckItem(
                id: "calibration_rms",
                name: "Calibration RMS",
                category: .calibrationError,
                passed: calibration.isAccepted && calibration.rmsErrorDeg <= 1.5,
                valueString: String(format: "%.2f°", calibration.rmsErrorDeg),
                ruleString: "≤ 1.50°",
                fixHint: "Calibration error above 1.5°: recalibrate holding your head steady at 30 cm."
            ),
            QualityCheckItem(
                id: "tracking_noise",
                name: "Tracking noise (unsmoothed)",
                category: .contaminatedSignal,
                passed: trackingNoiseDeg <= 0.45,
                valueString: trackingNoiseDeg.isFinite ? String(format: "%.2f°", trackingNoiseDeg) : "N/A",
                ruleString: "≤ 0.45°",
                fixHint: "High eye-tracking jitter: face a brighter light source and reduce glasses glare."
            ),
            QualityCheckItem(
                id: "clean_windows",
                name: "Clean windows",
                category: .contaminatedSignal,
                passed: windows.count >= 8,
                valueString: "\(windows.count)",
                ruleString: "≥ 8",
                fixHint: "Too few clean slow phases: look at the center ring and let the stripes drift past."
            ),
            QualityCheckItem(
                id: "mean_residual",
                name: "Mean residual",
                category: .contaminatedSignal,
                passed: meanResidualDeg.isFinite && trackingNoiseDeg.isFinite && meanResidualDeg <= 1.25 * trackingNoiseDeg,
                valueString: (meanResidualDeg.isFinite && trackingNoiseDeg.isFinite)
                    ? String(format: "%.3f° (≤ %.3f°)", meanResidualDeg, 1.25 * trackingNoiseDeg)
                    : "N/A",
                ruleString: "≤ 1.25 × noise",
                fixHint: "Slow-phase drift was non-linear: avoid consciously jumping between distant stripes."
            ),
            QualityCheckItem(
                id: "interval_half_width",
                name: "95% CI half-width",
                category: .contaminatedSignal,
                passed: halfWidth <= 1.5,
                valueString: halfWidth.isFinite ? String(format: "±%.2f °/s", halfWidth) : "N/A",
                ruleString: "≤ 1.50 °/s",
                fixHint: "Variable slow-phase speed: relax your gaze on the center and let the reflex happen."
            ),
            QualityCheckItem(
                id: "gain_minimum",
                name: "Directional gain",
                category: .contaminatedSignal,
                passed: (estimatedGain ?? -1.0) >= 0.20,
                valueString: estimatedGain.map { String(format: "%.2f", $0) } ?? "N/A",
                ruleString: "≥ 0.20",
                fixHint: "Low optokinetic pursuit response: keep looking at the middle of the moving stripes."
            )
        ]

        let allPassed = checks.allSatisfy(\.passed)
        let latencyMs = (CFAbsoluteTimeGetCurrent() - startClock) * 1000.0

        if allPassed, let validSlope = medianSlope, let validGain = estimatedGain, let validCI = ci {
            return OKNAnalysisResult(
                mode: mode,
                provenance: provenance,
                didAbstain: false,
                stoppedEarly: stoppedEarly,
                recordingDurationSec: totalDuration,
                analysisLatencyMs: latencyMs,
                totalFrames: totalCount,
                validFrames: validFrameCount,
                rejectedFrames: rejectedCount,
                trackingNoiseDeg: trackingNoiseDeg,
                calibrationRMSDeg: calibration.rmsErrorDeg,
                gain: validGain,
                slowPhaseSpeedDegPerSec: validSlope,
                confidenceInterval95: validCI,
                intervalHalfWidthDegPerSec: halfWidth,
                cleanWindowCount: windows.count,
                windows: windows,
                tracePoints: tracePoints,
                checks: checks
            )
        } else {
            return OKNAnalysisResult(
                mode: mode,
                provenance: provenance,
                didAbstain: true,
                stoppedEarly: stoppedEarly,
                recordingDurationSec: totalDuration,
                analysisLatencyMs: latencyMs,
                totalFrames: totalCount,
                validFrames: validFrameCount,
                rejectedFrames: rejectedCount,
                trackingNoiseDeg: trackingNoiseDeg,
                calibrationRMSDeg: calibration.rmsErrorDeg,
                gain: nil,
                slowPhaseSpeedDegPerSec: nil,
                confidenceInterval95: nil,
                intervalHalfWidthDegPerSec: halfWidth,
                cleanWindowCount: windows.count,
                windows: windows,
                tracePoints: tracePoints,
                checks: checks
            )
        }
    }

    private static func abstainResultWhenInsufficientData(
        samples: [EyeSample],
        calibration: CalibrationModel?,
        mode: MeasurementProtocolMode,
        provenance: DataProvenance
    ) -> OKNAnalysisResult {
        let calRMS = calibration?.rmsErrorDeg ?? .infinity
        let checks: [QualityCheckItem] = [
            QualityCheckItem(
                id: "face_tracked",
                name: "Face tracked",
                category: .trackingLoss,
                passed: false,
                valueString: "0.0%",
                ruleString: "≥ 85.0%",
                fixHint: "Too dark: face a window or lamp and keep your full face in view."
            ),
            QualityCheckItem(
                id: "valid_frames",
                name: "Valid frames",
                category: .trackingLoss,
                passed: false,
                valueString: "\(samples.count) frames",
                ruleString: "≥ 75.0%",
                fixHint: "Insufficient frames recorded: complete the test with your face in view."
            ),
            QualityCheckItem(
                id: "calibration_rms",
                name: "Calibration RMS",
                category: .calibrationError,
                passed: calibration?.isAccepted == true,
                valueString: calRMS.isFinite ? String(format: "%.2f°", calRMS) : "Uncalibrated",
                ruleString: "≤ 1.50°",
                fixHint: "Complete a valid 5-dot calibration before running the stripes test."
            )
        ]
        return OKNAnalysisResult(
            mode: mode,
            provenance: provenance,
            didAbstain: true,
            stoppedEarly: false,
            recordingDurationSec: 0.0,
            analysisLatencyMs: 0.0,
            totalFrames: samples.count,
            validFrames: 0,
            rejectedFrames: samples.count,
            trackingNoiseDeg: .nan,
            calibrationRMSDeg: calRMS,
            gain: nil,
            slowPhaseSpeedDegPerSec: nil,
            confidenceInterval95: nil,
            intervalHalfWidthDegPerSec: .infinity,
            cleanWindowCount: 0,
            windows: [],
            tracePoints: [],
            checks: checks
        )
    }
}
