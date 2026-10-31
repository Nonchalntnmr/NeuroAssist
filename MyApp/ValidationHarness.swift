import Foundation

// MARK: - Protocol Validation Harness (Pure Swift, Zero UIKit/ARKit Dependencies)

public struct ValidationTrialComparison: Sendable, Identifiable, Equatable {
    public let id: Int
    public let scenarioName: String
    public let trueVelocityDegPerSec: Double
    public let noiseSigmaDeg: Double
    public let expectedToPass: Bool

    public let fixedDurationSec: Double
    public let adaptiveDurationSec: Double
    public let fixedCalibrationSec: Double
    public let adaptiveCalibrationSec: Double

    public let fixedDidAbstain: Bool
    public let adaptiveDidAbstain: Bool
    public let fixedVelocityEstimate: Double?
    public let adaptiveVelocityEstimate: Double?
    public let fixedAnalysisLatencyMs: Double
    public let adaptiveAnalysisLatencyMs: Double

    public var fixedAbsoluteErrorDegPerSec: Double? {
        guard let v = fixedVelocityEstimate else { return nil }
        return abs(v - trueVelocityDegPerSec)
    }

    public var adaptiveAbsoluteErrorDegPerSec: Double? {
        guard let v = adaptiveVelocityEstimate else { return nil }
        return abs(v - trueVelocityDegPerSec)
    }

    public var modeAgreementOnGate: Bool {
        fixedDidAbstain == adaptiveDidAbstain
    }

    public var velocityDifferenceBetweenModes: Double? {
        guard let fv = fixedVelocityEstimate, let av = adaptiveVelocityEstimate else { return nil }
        return av - fv
    }
}

public struct ValidationBenchmarkReport: Sendable, Equatable {
    public let trials: [ValidationTrialComparison]
    public let meanFixedCalibrationSec: Double
    public let meanAdaptiveCalibrationSec: Double
    public let meanFixedStimulusSec: Double
    public let meanAdaptiveStimulusSec: Double
    public let meanFixedTotalSec: Double
    public let meanAdaptiveTotalSec: Double
    public let timeReductionPercent: Double

    public let fixedMeanAbsErrorDegPerSec: Double
    public let adaptiveMeanAbsErrorDegPerSec: Double
    public let fixedBiasDegPerSec: Double
    public let adaptiveBiasDegPerSec: Double
    public let maxModeDiscrepancyDegPerSec: Double

    public let falseAcceptanceRate: Double
    public let falseAbstentionRate: Double
    public let gateAgreementRate: Double
    public let meanAnalysisLatencyMs: Double
}

public enum ValidationHarness {

    private struct DeterministicRNG {
        var state: UInt64

        mutating func nextUniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let upper = state >> 11
            return Double(upper) / Double(1 << 53)
        }

        mutating func nextGaussian(sigma: Double) -> Double {
            let u1 = max(1e-12, nextUniform())
            let u2 = nextUniform()
            return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2) * sigma
        }
    }

    /// Replays a 5-dot synthetic calibration stream through both Fixed Reference Mode (2.0s/dot = 10.0s)
    /// and Adaptive Fast Mode (early stopping once fixation stability is met).
    public static func replayCalibrationComparison(
        noiseSigmaDeg: Double = 0.08,
        fps: Double = 60.0,
        seed: UInt64 = 0x1234_5678_9ABC_DEF0
    ) -> (fixed: CalibrationModel, adaptive: CalibrationModel) {
        var rng = DeterministicRNG(state: seed)
        let offsetsCm: [Double] = [0.0, -2.6, 2.6, -5.2, 5.2]
        let distanceCm = 30.0
        let totalFramesPerDot = Int(2.0 * fps)

        var fixedPoints: [CalibrationPointSample] = []
        var adaptivePoints: [CalibrationPointSample] = []

        for (dotIdx, offsetCm) in offsetsCm.enumerated() {
            let trueAngle = CalibrationPointSample.computeTrueAngleDeg(offsetCm: offsetCm, distanceCm: distanceCm)
            let dotStart = Double(dotIdx) * 2.0
            var dotSamples: [EyeSample] = []
            dotSamples.reserveCapacity(totalFramesPerDot)
            var adaptiveCaptured: CalibrationPointSample? = nil

            for f in 0..<totalFramesPerDot {
                let relT = Double(f) / fps
                let t = dotStart + relT
                // Simulate 0.25s initial saccade settling, then stable fixation
                let settleTransient = relT < 0.25 ? (1.0 - relT / 0.25) * 2.5 : 0.0
                let rawYaw = trueAngle + settleTransient + rng.nextGaussian(sigma: noiseSigmaDeg)
                let sample = EyeSample(
                    timestamp: t,
                    rawYawDeg: rawYaw,
                    faceTracked: true,
                    blinkLeft: 0.04,
                    blinkRight: 0.04,
                    headYawDeg: 0.08,
                    headPitchDeg: -0.05,
                    distanceCm: distanceCm
                )
                dotSamples.append(sample)

                if adaptiveCaptured == nil {
                    adaptiveCaptured = SignalMath.evaluateAdaptiveCalibrationDot(
                        samples: dotSamples,
                        dotStartTime: dotStart,
                        targetOffsetCm: offsetCm
                    )
                }
            }

            let fixedPt = SignalMath.summarizeCalibrationDot(
                samples: dotSamples,
                dotStartTime: dotStart,
                targetOffsetCm: offsetCm
            )!
            fixedPoints.append(fixedPt)
            adaptivePoints.append(adaptiveCaptured ?? fixedPt)
        }

        let fixedModel = SignalMath.fitCalibration(points: fixedPoints)!
        let adaptiveModel = SignalMath.fitCalibration(points: adaptivePoints)!
        return (fixedModel, adaptiveModel)
    }

    /// Replays a 10-second timestamped trace through both Fixed Reference Mode (full 10s)
    /// and Adaptive Fast Mode (online streaming evaluation every 0.25s with precision stopping).
    public static func replayTraceBothModes(
        samples: [EyeSample],
        fixedCalibration: CalibrationModel,
        adaptiveCalibration: CalibrationModel
    ) -> (fixedResult: OKNAnalysisResult, adaptiveResult: OKNAnalysisResult) {
        let fixedResult = SignalMath.analyzeOptokinetic(
            samples: samples,
            calibration: fixedCalibration,
            stripeDirectionSign: 1.0,
            mode: .researchFixed,
            stoppedEarly: false
        )

        // Simulate online 4 Hz evaluation during recording in Adaptive Fast Mode
        var cutoffIndex = samples.count
        var didStopEarly = false
        let t0 = samples.first?.timestamp ?? 0.0
        var nextEvalTime = 4.5

        for i in 0..<samples.count {
            let elapsed = samples[i].timestamp - t0
            if elapsed >= nextEvalTime {
                nextEvalTime += 0.25
                let prefix = Array(samples[0...i])
                let snapshot = SignalMath.evaluateOnlineSnapshot(
                    samples: prefix,
                    calibration: adaptiveCalibration,
                    mode: .adaptiveFast,
                    stripeDirectionSign: 1.0
                )
                if snapshot.canStopEarlyWithPrecision || snapshot.shouldAbortEarlyForQuality {
                    cutoffIndex = i + 1
                    didStopEarly = true
                    break
                }
            }
        }

        let adaptiveSlice = Array(samples.prefix(cutoffIndex))
        let adaptiveResult = SignalMath.analyzeOptokinetic(
            samples: adaptiveSlice,
            calibration: adaptiveCalibration,
            stripeDirectionSign: 1.0,
            mode: .adaptiveFast,
            stoppedEarly: didStopEarly
        )

        return (fixedResult, adaptiveResult)
    }

    /// Runs a suite of synthetic optokinetic & contaminated traces comparing Research Fixed Mode vs Adaptive Fast Mode.
    public static func runSuite() -> ValidationBenchmarkReport {
        struct Scenario {
            let name: String
            let trueVelocity: Double
            let noiseSigma: Double
            let headExcursionDeg: Double
            let blinkRate: Double
            let expectedPass: Bool
        }

        let scenarios: [Scenario] = [
            Scenario(name: "Clean Sawtooth +8.0 °/s (0.08° noise)", trueVelocity: 8.0, noiseSigma: 0.08, headExcursionDeg: 0.2, blinkRate: 0.0, expectedPass: true),
            Scenario(name: "Clean Sawtooth +8.0 °/s (0.12° noise)", trueVelocity: 8.0, noiseSigma: 0.12, headExcursionDeg: 0.3, blinkRate: 0.02, expectedPass: true),
            Scenario(name: "Moderate Gain +6.5 °/s (0.10° noise)", trueVelocity: 6.5, noiseSigma: 0.10, headExcursionDeg: 0.4, blinkRate: 0.0, expectedPass: true),
            Scenario(name: "High Gain +9.2 °/s (0.09° noise)", trueVelocity: 9.2, noiseSigma: 0.09, headExcursionDeg: 0.25, blinkRate: 0.0, expectedPass: true),
            Scenario(name: "Low Gain +4.5 °/s (0.10° noise)", trueVelocity: 4.5, noiseSigma: 0.10, headExcursionDeg: 0.3, blinkRate: 0.0, expectedPass: true),
            Scenario(name: "Heavy Tracking Jitter (1.80° noise)", trueVelocity: 8.0, noiseSigma: 1.80, headExcursionDeg: 0.2, blinkRate: 0.0, expectedPass: false),
            Scenario(name: "Excessive Head Rotation (3.6° head move)", trueVelocity: 8.0, noiseSigma: 0.10, headExcursionDeg: 3.6, blinkRate: 0.0, expectedPass: false),
            Scenario(name: "Absent Optokinetic Pursuit (+0.5 °/s)", trueVelocity: 0.5, noiseSigma: 0.10, headExcursionDeg: 0.2, blinkRate: 0.0, expectedPass: false)
        ]

        let fps = 60.0
        let durationSec = 10.0
        let totalFrames = Int(fps * durationSec)
        let resetPeriodSec = 0.5

        var comparisons: [ValidationTrialComparison] = []

        for (idx, sc) in scenarios.enumerated() {
            let seed = UInt64(0xA5A5_0000 + idx * 997)
            let cals = replayCalibrationComparison(
                noiseSigmaDeg: min(0.12, sc.noiseSigma),
                fps: fps,
                seed: seed
            )

            var rng = DeterministicRNG(state: seed ^ 0xFEED_FACE)
            var samples: [EyeSample] = []
            samples.reserveCapacity(totalFrames)

            for f in 0..<totalFrames {
                let t = Double(f) / fps
                let phase = t.truncatingRemainder(dividingBy: resetPeriodSec)
                let cleanAngle = -2.0 + sc.trueVelocity * phase
                let noisyAngle = cleanAngle + rng.nextGaussian(sigma: sc.noiseSigma)
                let isBlinking = rng.nextUniform() < sc.blinkRate
                let headYaw = (f > 30) ? sc.headExcursionDeg : 0.05

                samples.append(
                    EyeSample(
                        timestamp: t,
                        rawYawDeg: noisyAngle,
                        faceTracked: true,
                        blinkLeft: isBlinking ? 0.85 : 0.04,
                        blinkRight: isBlinking ? 0.85 : 0.04,
                        headYawDeg: headYaw,
                        headPitchDeg: 0.0,
                        distanceCm: 30.0
                    )
                )
            }

            let (fixedRes, adaptiveRes) = replayTraceBothModes(
                samples: samples,
                fixedCalibration: cals.fixed,
                adaptiveCalibration: cals.adaptive
            )

            comparisons.append(
                ValidationTrialComparison(
                    id: idx + 1,
                    scenarioName: sc.name,
                    trueVelocityDegPerSec: sc.trueVelocity,
                    noiseSigmaDeg: sc.noiseSigma,
                    expectedToPass: sc.expectedPass,
                    fixedDurationSec: fixedRes.recordingDurationSec,
                    adaptiveDurationSec: adaptiveRes.recordingDurationSec,
                    fixedCalibrationSec: cals.fixed.totalCalibrationDurationSec,
                    adaptiveCalibrationSec: cals.adaptive.totalCalibrationDurationSec,
                    fixedDidAbstain: fixedRes.didAbstain,
                    adaptiveDidAbstain: adaptiveRes.didAbstain,
                    fixedVelocityEstimate: fixedRes.slowPhaseSpeedDegPerSec,
                    adaptiveVelocityEstimate: adaptiveRes.slowPhaseSpeedDegPerSec,
                    fixedAnalysisLatencyMs: fixedRes.analysisLatencyMs,
                    adaptiveAnalysisLatencyMs: adaptiveRes.analysisLatencyMs
                )
            )
        }

        let cleanTrials = comparisons.filter(\.expectedToPass)
        let badTrials = comparisons.filter { !$0.expectedToPass }

        let meanFixedCal = cleanTrials.map(\.fixedCalibrationSec).reduce(0.0, +) / Double(max(1, cleanTrials.count))
        let meanAdaptCal = cleanTrials.map(\.adaptiveCalibrationSec).reduce(0.0, +) / Double(max(1, cleanTrials.count))
        let meanFixedStim = cleanTrials.map(\.fixedDurationSec).reduce(0.0, +) / Double(max(1, cleanTrials.count))
        let meanAdaptStim = cleanTrials.map(\.adaptiveDurationSec).reduce(0.0, +) / Double(max(1, cleanTrials.count))

        let meanFixedTotal = meanFixedCal + meanFixedStim
        let meanAdaptTotal = meanAdaptCal + meanAdaptStim
        let reductionPct = max(0.0, (meanFixedTotal - meanAdaptTotal) / meanFixedTotal * 100.0)

        let fixedErrors = cleanTrials.compactMap(\.fixedAbsoluteErrorDegPerSec)
        let adaptErrors = cleanTrials.compactMap(\.adaptiveAbsoluteErrorDegPerSec)
        let fixedMAE = fixedErrors.reduce(0.0, +) / Double(max(1, fixedErrors.count))
        let adaptMAE = adaptErrors.reduce(0.0, +) / Double(max(1, adaptErrors.count))

        let fixedBiases = cleanTrials.compactMap { t -> Double? in
            guard let v = t.fixedVelocityEstimate else { return nil }
            return v - t.trueVelocityDegPerSec
        }
        let adaptBiases = cleanTrials.compactMap { t -> Double? in
            guard let v = t.adaptiveVelocityEstimate else { return nil }
            return v - t.trueVelocityDegPerSec
        }
        let fixedBias = fixedBiases.reduce(0.0, +) / Double(max(1, fixedBiases.count))
        let adaptBias = adaptBiases.reduce(0.0, +) / Double(max(1, adaptBiases.count))

        let modeDiffs = cleanTrials.compactMap { $0.velocityDifferenceBetweenModes.map(abs) }
        let maxModeDiscrepancy = modeDiffs.max() ?? 0.0

        let falseAccepts = badTrials.filter { !$0.fixedDidAbstain || !$0.adaptiveDidAbstain }.count
        let falseAbstains = cleanTrials.filter { $0.fixedDidAbstain || $0.adaptiveDidAbstain }.count
        let gateAgreements = comparisons.filter(\.modeAgreementOnGate).count

        let allLatencies = comparisons.flatMap { [$0.fixedAnalysisLatencyMs, $0.adaptiveAnalysisLatencyMs] }
        let meanLatencyMs = allLatencies.reduce(0.0, +) / Double(max(1, allLatencies.count))

        return ValidationBenchmarkReport(
            trials: comparisons,
            meanFixedCalibrationSec: meanFixedCal,
            meanAdaptiveCalibrationSec: meanAdaptCal,
            meanFixedStimulusSec: meanFixedStim,
            meanAdaptiveStimulusSec: meanAdaptStim,
            meanFixedTotalSec: meanFixedTotal,
            meanAdaptiveTotalSec: meanAdaptTotal,
            timeReductionPercent: reductionPct,
            fixedMeanAbsErrorDegPerSec: fixedMAE,
            adaptiveMeanAbsErrorDegPerSec: adaptMAE,
            fixedBiasDegPerSec: fixedBias,
            adaptiveBiasDegPerSec: adaptBias,
            maxModeDiscrepancyDegPerSec: maxModeDiscrepancy,
            falseAcceptanceRate: Double(falseAccepts) / Double(max(1, badTrials.count)),
            falseAbstentionRate: Double(falseAbstains) / Double(max(1, cleanTrials.count)),
            gateAgreementRate: Double(gateAgreements) / Double(max(1, comparisons.count)),
            meanAnalysisLatencyMs: meanLatencyMs
        )
    }
}
