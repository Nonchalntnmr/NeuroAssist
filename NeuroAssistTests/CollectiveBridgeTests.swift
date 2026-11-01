import Foundation
import Testing
@testable import NeuroAssist

/// Tests for the naci.ingest/1 payload the phone sends to the NeuroAssist × CI server.
@MainActor
struct CollectiveBridgeTests {

    private let calibration = CalibrationModel(
        slope: 1.0,
        intercept: 0.0,
        rmsErrorDeg: 0.2,
        meanDistanceCm: 31.0,
        points: []
    )

    private func result(_ provenance: DataProvenance) -> OKNAnalysisResult {
        OKNAnalysisResult(
            provenance: provenance,
            gain: 0.8,
            slowPhaseSpeedDegPerSec: 8.0,
            confidenceInterval95: (7.9, 8.1),
            intervalHalfWidthDegPerSec: 0.1,
            cleanWindowCount: 10,
            windows: [],
            tracePoints: [],
            checks: []
        )
    }

    private func sample(t: Double, yaw: Double, tracked: Bool = true, head: Double = 0.1) -> EyeSample {
        EyeSample(
            timestamp: t,
            rawYawDeg: yaw,
            faceTracked: tracked,
            blinkLeft: 0.05,
            blinkRight: 0.05,
            headYawDeg: head,
            headPitchDeg: 0.0,
            distanceCm: 31.0
        )
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func lostAndNonFiniteFramesBecomeNull() throws {
        var samples = (0..<60).map { sample(t: 100.0 + Double($0) / 60.0, yaw: 1.0) }
        samples[10] = sample(t: samples[10].timestamp, yaw: .nan)
        samples[20] = sample(t: samples[20].timestamp, yaw: 2.0, tracked: false)
        samples[30] = sample(t: samples[30].timestamp, yaw: 2.0, head: .infinity)

        let body = try decode(CollectiveBridge.makeIngestBody(
            samples: samples, calibration: calibration, result: result(.liveCamera),
            subject: "na-test", history: []
        ))
        let trace = try #require(body["trace"] as? [String: Any])
        let x = try #require(trace["x"] as? [Any])
        let head = try #require(trace["head"] as? [Any])
        let t = try #require(trace["t"] as? [Double])

        #expect(x.count == 60 && head.count == 60 && t.count == 60)
        #expect(x[10] is NSNull)
        #expect(x[20] is NSNull)
        #expect(head[20] is NSNull)
        #expect(head[30] is NSNull)
        #expect((x[0] as? Double) == 1.0)
        // Time is relative to the first frame
        #expect(t[0] == 0.0)
    }

    @Test func timeIsNeverDecreasing() throws {
        var samples = (0..<40).map { sample(t: Double($0) / 60.0, yaw: 0.5) }
        samples[15] = sample(t: 0.0, yaw: 0.5) // out-of-order timestamp
        let body = try decode(CollectiveBridge.makeIngestBody(
            samples: samples, calibration: calibration, result: result(.liveCamera),
            subject: "na-test", history: []
        ))
        let t = try #require((body["trace"] as? [String: Any])?["t"] as? [Double])
        #expect(zip(t, t.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func tooShortTraceIsRejected() {
        let samples = (0..<29).map { sample(t: Double($0) / 60.0, yaw: 0.0) }
        #expect(throws: CollectiveBridgeError.self) {
            _ = try CollectiveBridge.makeIngestBody(
                samples: samples, calibration: calibration, result: result(.liveCamera),
                subject: "na-test", history: []
            )
        }
    }

    @Test func traceIsCappedAtServerLimit() throws {
        let samples = (0..<4000).map { sample(t: Double($0) / 60.0, yaw: 0.0) }
        let body = try decode(CollectiveBridge.makeIngestBody(
            samples: samples, calibration: calibration, result: result(.liveCamera),
            subject: "na-test", history: []
        ))
        let t = try #require((body["trace"] as? [String: Any])?["t"] as? [Double])
        #expect(t.count == 3600)
    }

    @Test(arguments: [
        (DataProvenance.liveCamera, "REAL"),
        (DataProvenance.simulated, "SYNTHETIC"),
        (DataProvenance.recordedSession, "PRERECORDED")
    ])
    func provenanceIsPreserved(provenance: DataProvenance, label: String) throws {
        let samples = (0..<60).map { sample(t: Double($0) / 60.0, yaw: 0.0) }
        let body = try decode(CollectiveBridge.makeIngestBody(
            samples: samples, calibration: calibration, result: result(provenance),
            subject: "na-test", history: []
        ))
        let prov = try #require(body["provenance"] as? [String: Any])
        #expect(prov["label"] as? String == label)
        #expect(body["schema"] as? String == "naci.ingest/1")
    }

    @Test func demoAndRealUseSeparateSubjects() {
        let bridge = CollectiveBridge()
        #expect(bridge.subjectId(for: .liveCamera) != bridge.subjectId(for: .simulated))
        #expect(bridge.subjectId(for: .simulated).hasPrefix("na-demo-"))
    }
}
