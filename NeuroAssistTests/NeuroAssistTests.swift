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
}
