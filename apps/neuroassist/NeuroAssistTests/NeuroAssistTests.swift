import XCTest
@testable import NeuroAssist

final class NeuroAssistTests: XCTestCase {

    /// Deterministic Box-Muller Gaussian generator so the unit test is reproducible.
    private struct SeededGaussian {
        private var state: UInt64 = 0xCAFEBABE_12345678

        mutating func nextUniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let upper = state >> 11
            return Double(upper) / Double(1 << 53)
        }

        mutating func nextGaussian(sigma: Double) -> Double {
            let u1 = max(1e-12, nextUniform())
            let u2 = nextUniform()
            let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
            return z0 * sigma
        }
    }

    private func makeIdealCalibration() -> CalibrationModel {
        let points = [-10.0, -5.0, 0.0, 5.0, 10.0].map { angle in
            CalibrationPointSample(
                targetOffsetCm: tan(angle * .pi / 180.0) * 30.0,
                distanceCm: 30.0,
                trueAngleDeg: angle,
                medianMeasuredYawDeg: angle
            )
        }
        return SignalMath.fitCalibration(points: points)!
    }

    func testSyntheticSawtoothPassesGateWithinHalfDegreePerSecAndHeavyNoiseAbstains() {
        let calibration = makeIdealCalibration()
        XCTAssertTrue(calibration.isAccepted)
        XCTAssertLessThanOrEqual(calibration.rmsErrorDeg, 1.5)

        let fps = 60.0
        let durationSec = 10.0
        let totalFrames = Int(fps * durationSec) // 600 frames
        let trueSlowVelocity = 8.0 // +8 deg/s slow drift
        let resetPeriodSec = 0.5   // reset every 0.5 s

        // 1. Low noise (0.1 deg sigma) synthetic sawtooth
        var rng = SeededGaussian()
        var cleanSawtoothSamples: [EyeSample] = []
        cleanSawtoothSamples.reserveCapacity(totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) / fps
            let phaseTime = t.truncatingRemainder(dividingBy: resetPeriodSec)
            // Slow drift from -2 deg to +2 deg at +8 deg/s, resetting every 0.5 s
            let cleanAngle = -2.0 + trueSlowVelocity * phaseTime
            let noisyAngle = cleanAngle + rng.nextGaussian(sigma: 0.1)

            cleanSawtoothSamples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: noisyAngle,
                    faceTracked: true,
                    blinkLeft: 0.05,
                    blinkRight: 0.05,
                    headYawDeg: 0.1,
                    headPitchDeg: -0.1,
                    distanceCm: 30.0
                )
            )
        }

        let resultClean = SignalMath.analyzeOptokinetic(
            samples: cleanSawtoothSamples,
            calibration: calibration,
            stripeDirectionSign: 1.0
        )

        XCTAssertFalse(resultClean.didAbstain, "Expected quality gate to pass on 0.1° noise sawtooth, failed: \(resultClean.failedChecks.map(\.name))")
        guard let estimatedSpeed = resultClean.slowPhaseSpeedDegPerSec,
              let estimatedGain = resultClean.gain else {
            XCTFail("Expected non-nil slowPhaseSpeedDegPerSec and gain when quality gate passes")
            return
        }

        XCTAssertEqual(estimatedSpeed, trueSlowVelocity, accuracy: 0.5, "Slow-phase velocity estimate must be within 0.5 deg/s of +8.0 deg/s")
        XCTAssertEqual(estimatedGain, 0.80, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(resultClean.cleanWindowCount, 8)
        XCTAssertGreaterThan(resultClean.trackingNoiseDeg, 0.07, "Unsmoothed tracking noise on 0.10° sigma input must not read artificially low (~0.02°)")
        XCTAssertLessThan(resultClean.trackingNoiseDeg, 0.16, "Unsmoothed tracking noise on 0.10° sigma input must accurately reflect ~0.10°")

        // 2. Heavy noise (1.8 deg sigma) synthetic sawtooth -> must ABSTAIN and withhold numbers
        var heavyNoiseSamples: [EyeSample] = []
        heavyNoiseSamples.reserveCapacity(totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) / fps
            let phaseTime = t.truncatingRemainder(dividingBy: resetPeriodSec)
            let cleanAngle = -2.0 + trueSlowVelocity * phaseTime
            let noisyAngle = cleanAngle + rng.nextGaussian(sigma: 1.8)

            heavyNoiseSamples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: noisyAngle,
                    faceTracked: true,
                    blinkLeft: 0.05,
                    blinkRight: 0.05,
                    headYawDeg: 0.1,
                    headPitchDeg: -0.1,
                    distanceCm: 30.0
                )
            )
        }

        let resultNoisy = SignalMath.analyzeOptokinetic(
            samples: heavyNoiseSamples,
            calibration: calibration,
            stripeDirectionSign: 1.0
        )

        XCTAssertTrue(resultNoisy.didAbstain, "Expected heavy noise to trigger ABSTAIN")
        XCTAssertNil(resultNoisy.gain, "ABSTAIN result must never expose a gain number")
        XCTAssertNil(resultNoisy.slowPhaseSpeedDegPerSec, "ABSTAIN result must never expose a deg/s number")
        XCTAssertFalse(resultNoisy.failedChecks.isEmpty, "Expected failed quality checks to be populated")
    }

    func testValidationHarnessFixedVsAdaptiveAgreementAndSpeedup() {
        let report = ValidationHarness.runSuite()

        // Verify adaptive mode cuts total calibration + stimulus time by >= 40%
        XCTAssertLessThan(report.meanAdaptiveTotalSec, report.meanFixedTotalSec)
        XCTAssertGreaterThanOrEqual(report.timeReductionPercent, 40.0, "Expected >= 40% duration reduction in Adaptive Fast Mode")

        // Verify accuracy & mode agreement across clean and contaminated synthetic traces
        XCTAssertLessThanOrEqual(report.fixedMeanAbsErrorDegPerSec, 0.35)
        XCTAssertLessThanOrEqual(report.adaptiveMeanAbsErrorDegPerSec, 0.35)
        XCTAssertLessThanOrEqual(report.maxModeDiscrepancyDegPerSec, 0.35, "Adaptive early stopping must agree closely with fixed 10s reference")

        // Zero false acceptances on contaminated traces & 100% gate agreement
        XCTAssertEqual(report.falseAcceptanceRate, 0.0, "Must never accept contaminated traces")
        XCTAssertEqual(report.falseAbstentionRate, 0.0, "Must not falsely abstain on clean traces")
        XCTAssertEqual(report.gateAgreementRate, 1.0, "Fixed and Adaptive modes must agree on all 11 quality gates")
    }

    @MainActor
    func testPlatformServicesVaultEncryptionConsentDefaultsAndAbstainIntegrity() throws {
        let store = PlatformServicesStore()

        // 1. Verify all external sharing permissions default to OFF until explicit user opt-in
        store.deleteAccountAndWipeAllData()
        for perm in store.permissions {
            XCTAssertFalse(perm.isEnabled, "All external sharing scopes must default to OFF (\(perm.scope.rawValue))")
        }

        // 2. Verify AES-256-GCM encryption & decryption round-trip via SecureKeychainVault
        let sampleProfile = UserProfileRecord(
            accountID: "test-user-01",
            authState: .localResearchAccount,
            displayName: "Dr. Test Researcher"
        )
        let encryptedData = try SecureKeychainVault.encryptCodable(sampleProfile)
        let decryptedProfile = try SecureKeychainVault.decryptCodable(UserProfileRecord.self, from: encryptedData)
        XCTAssertEqual(decryptedProfile, sampleProfile)

        // 3. Verify recording an ABSTAIN session never fabricates slowPhaseVelocity or oknGain
        let (abstainRes, abstainCal) = DemoExperienceStore.runSimulatedScenario(.headMovement, mode: .researchFixed)
        let recordedAbstain = store.recordMeasurementSession(
            result: abstainRes,
            calibration: abstainCal,
            category: .drivingResearchProtocol,
            userNotes: "Test note separated from measured data",
            drivingResearchTag: ExperimentalConditionFactor.selfReportedFatigueDrowsiness.rawValue
        )
        XCTAssertTrue(recordedAbstain.didAbstain)
        XCTAssertNil(recordedAbstain.slowPhaseVelocityDegPerSec, "ABSTAIN session in history must never fabricate SPV")
        XCTAssertNil(recordedAbstain.oknGain, "ABSTAIN session in history must never fabricate OKN gain")
        XCTAssertEqual(recordedAbstain.userEnteredNotes, "Test note separated from measured data")

        // 4. Verify CSV & JSON exports succeed and preserve ABSTAIN markers
        let csvURL = store.exportSessionsAsCSVFile(sessionsToExport: store.sessions)
        let jsonURL = store.exportSessionsAsJSONFile(sessionsToExport: store.sessions)
        XCTAssertNotNil(csvURL)
        XCTAssertNotNil(jsonURL)

        // 5. Verify granular opt-in & revocation are logged in the immutable audit trail
        store.setPermission(scope: .deIdentifiedProductAnalytics, enabled: true)
        XCTAssertTrue(store.permissions.first(where: { $0.scope == .deIdentifiedProductAnalytics })?.isEnabled == true)
        store.setPermission(scope: .deIdentifiedProductAnalytics, enabled: false)
        XCTAssertTrue(store.permissions.first(where: { $0.scope == .deIdentifiedProductAnalytics })?.isEnabled == false)
        XCTAssertTrue(store.auditLog.contains(where: { $0.actionType == "CONSENT_REVOKED" }))
    }

    // MARK: - Phase 4: Deterministic Ground-Truth Scientific Verification Tests

    func testConstantVelocitySlowPhaseRecovery() {
        let cal = makeIdealCalibration()
        let fps = 60.0
        let targetSpeed = 10.0 // +10 deg/s
        let resetSec = 0.5
        var samples: [EyeSample] = []
        var rng = SeededGaussian()

        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: resetSec)
            let angle = -2.5 + targetSpeed * phase + rng.nextGaussian(sigma: 0.05)
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.05,
                    headPitchDeg: -0.05,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertEqual(result.scientificStatus, .valid)
        XCTAssertFalse(result.didAbstain)
        guard let speed = result.slowPhaseSpeedDegPerSec else {
            XCTFail("Speed must be present for valid test")
            return
        }
        XCTAssertEqual(speed, targetSpeed, accuracy: 0.5)
        XCTAssertEqual(result.cadenceDiagnostics.droppedFrameCount, 0)
        XCTAssertEqual(result.artifactFlags.blinkFramesCount, 0)
    }

    func testSinusoidalSmoothPursuitEstimation() {
        let cal = makeIdealCalibration()
        let fps = 60.0
        var samples: [EyeSample] = []

        // 1.5 Hz sinusoidal smooth pursuit
        for i in 0..<600 {
            let t = Double(i) / fps
            let angle = 4.0 * sin(2.0 * .pi * 1.5 * t)
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertGreaterThan(result.windows.count, 0, "Sinusoidal pursuit must yield segmented direction-aligned windows")
        XCTAssertEqual(result.cadenceDiagnostics.droppedFrameCount, 0)
        XCTAssertGreaterThan(result.cadenceDiagnostics.meanFps, 55.0)
    }

    func testRapidMotionBeyondSamplingLimitsTriggersRejection() {
        let cal = makeIdealCalibration()
        let fps = 60.0
        var samples: [EyeSample] = []

        // Injects 35 Hz motion (violating 30 Hz Nyquist cutoff of 60 Hz sensor)
        for i in 0..<600 {
            let t = Double(i) / fps
            let angle = 6.0 * sin(2.0 * .pi * 35.0 * t) // Nyquist violation
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertTrue(result.didAbstain)
        XCTAssertGreaterThan(result.artifactFlags.rapidMotionUndersampledCount, 0)
        XCTAssertNil(result.slowPhaseSpeedDegPerSec)
    }

    func testIrregularTimestampsAndJitterHandling() {
        let cal = makeIdealCalibration()
        var samples: [EyeSample] = []
        var rng = SeededGaussian()
        var currentT = 0.0

        for _ in 0..<600 {
            let jitterSec = rng.nextGaussian(sigma: 0.008) // ±8ms jitter
            let dt = max(0.002, 0.01667 + jitterSec)
            currentT += dt
            let phase = currentT.truncatingRemainder(dividingBy: 0.5)
            let angle = -2.0 + 8.0 * phase
            samples.append(
                EyeSample(
                    timestamp: currentT,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertGreaterThan(result.cadenceDiagnostics.cadenceJitterMs, 4.0)
        XCTAssertTrue(result.cadenceDiagnostics.isSamplingIrregular)
    }

    func testMissingFramesAndDroppedPackets() {
        let cal = makeIdealCalibration()
        var samples: [EyeSample] = []
        var currentT = 0.0

        for i in 0..<600 {
            // Drop a chunk of frames between 200 and 300 to simulate sensor stalls
            if i >= 200 && i < 280 {
                currentT += 0.01667
                continue
            }
            currentT += 0.01667
            let phase = currentT.truncatingRemainder(dividingBy: 0.5)
            let angle = -2.0 + 8.0 * phase
            samples.append(
                EyeSample(
                    timestamp: currentT,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertGreaterThan(result.cadenceDiagnostics.droppedFrameCount, 20)
        XCTAssertTrue(result.cadenceDiagnostics.droppedFrameRatio > 0.05)
        XCTAssertTrue(result.didAbstain)
        XCTAssertEqual(result.scientificStatus, .invalid)
    }

    func testBlinksAndTrackingInterruptionBlanking() {
        let cal = makeIdealCalibration()
        let fps = 60.0
        var samples: [EyeSample] = []

        for i in 0..<600 {
            let t = Double(i) / fps
            let isBlinking = (i >= 120 && i <= 145) || (i >= 350 && i <= 375) // two blinks
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            let angle = -2.0 + 8.0 * phase
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: isBlinking ? 0.0 : angle,
                    faceTracked: !isBlinking,
                    blinkLeft: isBlinking ? 0.95 : 0.05,
                    blinkRight: isBlinking ? 0.95 : 0.05,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertGreaterThan(result.artifactFlags.blinkFramesCount, 40)
        XCTAssertGreaterThan(result.artifactFlags.postSaccadicBlankedCount, 0)
    }

    func testAngularWraparoundGuard() {
        // Tests that 179 deg to -179 deg unwraps to +181 deg (+2 deg diff) instead of -358 deg jump
        let angle1 = 179.0
        let angle2 = -179.0
        let unwrapped = SignalMath.unwrapAngleDeg(angle2, previousDeg: angle1)
        XCTAssertEqual(unwrapped, 181.0, accuracy: 1e-4)

        let angleBack = SignalMath.unwrapAngleDeg(179.0, previousDeg: -179.0)
        XCTAssertEqual(angleBack, -181.0, accuracy: 1e-4)
    }

    func testZeroHeadMovementVsExcessiveHeadMotion() {
        let cal = makeIdealCalibration()
        let fps = 60.0

        // Case A: Steady head (<0.2 deg)
        var steadySamples: [EyeSample] = []
        var rng = SeededGaussian()
        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            let angle = -2.0 + 8.0 * phase + rng.nextGaussian(sigma: 0.05)
            steadySamples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.08,
                    headPitchDeg: -0.05,
                    distanceCm: 30.0
                )
            )
        }
        let resultSteady = SignalMath.analyzeOptokinetic(samples: steadySamples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertEqual(resultSteady.scientificStatus, .valid)

        // Case B: Excessive head motion (>3.5 deg)
        var shakySamples: [EyeSample] = []
        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            shakySamples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: -2.0 + 8.0 * phase,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 3.8 * sin(2.0 * .pi * 0.4 * t),
                    headPitchDeg: 2.5 * cos(2.0 * .pi * 0.4 * t),
                    distanceCm: 30.0
                )
            )
        }
        let resultShaky = SignalMath.analyzeOptokinetic(samples: shakySamples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertTrue(resultShaky.didAbstain)
        XCTAssertEqual(resultShaky.scientificStatus, .invalid)
        XCTAssertEqual(resultShaky.primaryRootCause, .headMovement)
    }

    func testSensorNoiseGateCalibrationAndThresholds() {
        let cal = makeIdealCalibration()
        let fps = 60.0
        var rng = SeededGaussian()

        // Marginal noise at 0.30 deg sigma should pass gate (<=0.45 deg)
        var acceptableSamples: [EyeSample] = []
        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            acceptableSamples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: -2.0 + 8.0 * phase + rng.nextGaussian(sigma: 0.28),
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }
        let resultAcceptable = SignalMath.analyzeOptokinetic(samples: acceptableSamples, calibration: cal, stripeDirectionSign: 1.0)
        XCTAssertLessThanOrEqual(resultAcceptable.trackingNoiseDeg, 0.45)
    }

    func testCalibrationFailureRejection() {
        let erraticAngles = [12.0, -8.0, 14.0, -11.0, 18.0]
        let degradedPoints = zip([-10.0, -5.0, 0.0, 5.0, 10.0], erraticAngles).map { trueAngle, measured in
            CalibrationPointSample(
                targetOffsetCm: tan(trueAngle * .pi / 180.0) * 30.0,
                distanceCm: 30.0,
                trueAngleDeg: trueAngle,
                medianMeasuredYawDeg: measured
            )
        }
        let badCal = SignalMath.fitCalibration(points: degradedPoints)!
        XCTAssertFalse(badCal.isAccepted, "RMS > 1.5 deg must not be accepted")

        let fps = 60.0
        var samples: [EyeSample] = []
        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: -2.0 + 8.0 * phase,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.0,
                    headPitchDeg: 0.0,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: badCal, stripeDirectionSign: 1.0)
        XCTAssertTrue(result.didAbstain)
        XCTAssertEqual(result.scientificStatus, .invalid)
        XCTAssertTrue(result.failedChecks.contains { $0.category == .calibrationError }, "Expected calibrationError in failed checks")
    }

    @MainActor
    func testCIObservationContractSchemaValidation() throws {
        let store = PlatformServicesStore()
        let cal = makeIdealCalibration()
        let fps = 60.0
        var samples: [EyeSample] = []

        var rng = SeededGaussian()
        for i in 0..<600 {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: 0.5)
            let angle = -2.0 + 8.0 * phase + rng.nextGaussian(sigma: 0.05)
            samples.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: angle,
                    faceTracked: true,
                    blinkLeft: 0.0,
                    blinkRight: 0.0,
                    headYawDeg: 0.05,
                    headPitchDeg: -0.05,
                    distanceCm: 30.0
                )
            )
        }

        let result = SignalMath.analyzeOptokinetic(samples: samples, calibration: cal, stripeDirectionSign: 1.0)
        let session = store.recordMeasurementSession(
            result: result,
            calibration: cal,
            category: .baselineOculomotor,
            userNotes: "Synthetic gold standard trace"
        )

        let obs = NeuroAssistCIObservation.from(session: session)
        XCTAssertEqual(obs.schemaVersion, "neuroassist.ci.observation/1.0")
        XCTAssertEqual(obs.scientificStatus, "VALID")
        XCTAssertEqual(obs.protocolType, "OPTOKINETIC_NYSTAGMUS")
        XCTAssertNotNil(obs.slowPhaseVelocityDegPerSec)
        XCTAssertNotNil(obs.oknGain)
        XCTAssertTrue(obs.allGatesPassed)
        XCTAssertGreaterThan(obs.meanFps, 50.0)

        // Verify JSON export round-trip
        let jsonURL = store.exportSessionAsCIObservationJSON(session: session)
        XCTAssertNotNil(jsonURL)
        guard let url = jsonURL, let data = try? Data(contentsOf: url) else {
            XCTFail("Failed to read exported CI Observation JSON")
            return
        }

        let decoder = JSONDecoder()
        let decodedObs = try decoder.decode(NeuroAssistCIObservation.self, from: data)
        XCTAssertEqual(decodedObs, obs)
    }
}
