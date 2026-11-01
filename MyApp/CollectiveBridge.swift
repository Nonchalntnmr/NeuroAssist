import Foundation
import Observation
import SwiftUI
import UIKit

// MARK: - NeuroAssist → CI bridge (naci.ingest/1)
//
// The phone sends a numerical gaze trace (degrees per frame, no images or video) to a
// NeuroAssist × CI server. The server recomputes the measurement with its engine of record
// (neurocore), runs the five-agent collective with CI memory built from the history the phone
// sends, and returns every agent message. The server keeps nothing after it responds, so the
// phone owns the history (file-protected, per pseudonymous subject).

/// Decoded subset of the server's `naci.run/1` response shown in the app.
struct CollectiveRunResponse: Decodable {
    struct Collective: Decodable {
        let decision: String
        let rounds: Int?
        let latencyMs: Double?
        let artifactFlagged: Bool?
        let artifactCauses: [String]?
        let baselineIds: [String]?
        let vetoes: [Veto]?
        let messages: [AgentMessage]
        let audit: Audit?

        enum CodingKeys: String, CodingKey {
            case decision, rounds, vetoes, messages, audit
            case latencyMs = "latency_ms"
            case artifactFlagged = "artifact_flagged"
            case artifactCauses = "artifact_causes"
            case baselineIds = "baseline_ids"
        }
    }

    struct Veto: Decodable, Hashable {
        let by: String
        let text: String
    }

    struct Audit: Decodable {
        let chainOk: Bool?
        enum CodingKeys: String, CodingKey { case chainOk = "chain_ok" }
    }

    struct AgentMessage: Decodable, Identifiable {
        let id: String
        let round: Int
        let sender: String
        let to: String?
        let kind: String
        let topic: String
        let text: String
        let refs: [String]?
        let replyTo: String?

        enum CodingKeys: String, CodingKey {
            case id, round, sender, to, kind, topic, text, refs
            case replyTo = "reply_to"
        }
    }

    struct BaselineDecision: Decodable {
        let decision: String
    }

    struct Compare: Decodable {
        let deterministic: BaselineDecision?
        let singleAgent: BaselineDecision?
        enum CodingKeys: String, CodingKey {
            case deterministic
            case singleAgent = "single_agent"
        }
    }

    struct ServerSession: Decodable {
        struct Measurement: Decodable {
            let status: String
            let value: Double?
            let ciLow: Double?
            let ciHigh: Double?
            let windows: Int?
            enum CodingKeys: String, CodingKey {
                case status, value, windows
                case ciLow = "ci_low"
                case ciHigh = "ci_high"
            }
        }
        struct Check: Decodable, Hashable {
            let id: String
            let label: String
            let show: String?
            let rule: String?
            let ok: Bool
        }
        struct Quality: Decodable {
            let validFrac: Double
            let fps: Double
            let noiseDeg: Double?
            let checks: [Check]?
            let abstainReasons: [String]?
            enum CodingKeys: String, CodingKey {
                case fps, checks
                case validFrac = "valid_frac"
                case noiseDeg = "noise_deg"
                case abstainReasons = "abstain_reasons"
            }
        }
        let sessionId: String
        let measurement: Measurement
        let quality: Quality
        enum CodingKeys: String, CodingKey {
            case measurement, quality
            case sessionId = "session_id"
        }
    }

    let collective: Collective
    let compare: Compare?
    let serverMs: Double?
    let engineOfRecord: String?
    let session: ServerSession?

    enum CodingKeys: String, CodingKey {
        case collective, compare, session
        case serverMs = "server_ms"
        case engineOfRecord = "engine_of_record"
    }
}

enum CollectiveBridgeError: LocalizedError {
    case invalidServerURL
    case traceTooShort(Int)
    case server(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The CI server address is not a valid http(s) URL."
        case .traceTooShort(let n):
            return "Only \(n) frames were recorded; the collective needs at least 30."
        case .server(let status, let detail):
            return "CI server returned HTTP \(status): \(detail)"
        }
    }
}

@MainActor
@Observable
final class CollectiveBridge {
    enum RunState {
        case idle
        case running
        case finished(CollectiveRunResponse, host: String)
        case failed(String)
    }

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Self.serverKey) }
    }
    /// Explicit consent to send numerical traces and history summaries to the server.
    var hasConsented: Bool {
        didSet { UserDefaults.standard.set(hasConsented, forKey: Self.consentKey) }
    }
    private(set) var state: RunState = .idle

    private static let serverKey = "ci.serverURL"
    private static let consentKey = "ci.consent"
    private static let maxHistory = 60
    private static let maxFrames = 3600

    init() {
        #if targetEnvironment(simulator)
        let defaultURL = "http://127.0.0.1:8000"
        #else
        let defaultURL = "http://192.168.1.10:8000"
        #endif
        serverURLString = UserDefaults.standard.string(forKey: Self.serverKey) ?? defaultURL
        hasConsented = UserDefaults.standard.bool(forKey: Self.consentKey)
    }

    func reset() {
        state = .idle
    }

    /// Pseudonymous subject id. Synthetic (demo) sessions use a separate subject so they can
    /// never enter the real personal baseline.
    func subjectId(for provenance: DataProvenance) -> String {
        let key = provenance == .liveCamera ? "ci.subject.real" : "ci.subject.demo"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let prefix = provenance == .liveCamera ? "na" : "na-demo"
        let id = "\(prefix)-\(UUID().uuidString.prefix(12).lowercased())"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    func historyCount(for provenance: DataProvenance) -> Int {
        loadHistory(subject: subjectId(for: provenance)).count
    }

    func deleteHistory(for provenance: DataProvenance) {
        try? FileManager.default.removeItem(at: historyURL(subject: subjectId(for: provenance)))
    }

    func run(samples: [EyeSample], calibration: CalibrationModel, result: OKNAnalysisResult) async {
        guard hasConsented else { return }
        state = .running
        do {
            guard let base = URL(string: serverURLString),
                  let scheme = base.scheme, ["http", "https"].contains(scheme),
                  let host = base.host() else {
                throw CollectiveBridgeError.invalidServerURL
            }
            let subject = subjectId(for: result.provenance)
            let history = loadHistory(subject: subject)
            let body = try Self.makeIngestBody(
                samples: samples,
                calibration: calibration,
                result: result,
                subject: subject,
                history: history
            )

            var request = URLRequest(url: base.appending(path: "api/py/v1/collective/ingest"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let detail = String(data: data.prefix(300), encoding: .utf8) ?? "no detail"
                throw CollectiveBridgeError.server(status: status, detail: detail)
            }
            let decoded = try JSONDecoder().decode(CollectiveRunResponse.self, from: data)

            // Persist the server-computed record (without trace) as future history
            if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let session = raw["session"] as? [String: Any] {
                saveHistory(Array((history + [session]).suffix(Self.maxHistory)), subject: subject)
            }
            state = .finished(decoded, host: host)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Payload

    static func provenanceLabel(_ provenance: DataProvenance) -> String {
        switch provenance {
        case .liveCamera: return "REAL"
        case .recordedSession: return "PRERECORDED"
        case .simulated: return "SYNTHETIC"
        }
    }

    static func makeIngestBody(
        samples: [EyeSample],
        calibration: CalibrationModel,
        result: OKNAnalysisResult,
        subject: String,
        history: [[String: Any]]
    ) throws -> Data {
        let frames = Array(samples.suffix(maxFrames))
        guard frames.count >= 30, let t0 = frames.first?.timestamp else {
            throw CollectiveBridgeError.traceTooShort(frames.count)
        }

        // Calibrated horizontal gaze in degrees; lost/blink/non-finite frames are sent as null
        var t: [Double] = []
        var x: [Any] = []
        var head: [Any] = []
        var lastT = 0.0
        for s in frames {
            let rel = max(lastT, s.timestamp - t0) // enforce non-decreasing time
            lastT = rel
            t.append(rel)
            let gaze = calibration.calibrate(rawYawDeg: s.rawYawDeg)
            x.append(s.isValid && gaze.isFinite ? gaze : NSNull())
            head.append(s.faceTracked && s.headYawDeg.isFinite ? s.headYawDeg : NSNull())
        }

        var clientResult: [String: Any] = [
            "status": result.didAbstain ? "ABSTAINED" : "MEASURED",
            "engine": "neuroassist-ios-signalmath"
        ]
        if let speed = result.slowPhaseSpeedDegPerSec, speed.isFinite { clientResult["slow_phase_deg_s"] = speed }
        if let gain = result.gain, gain.isFinite { clientResult["gain"] = gain }

        let body: [String: Any] = [
            "schema": "naci.ingest/1",
            "session_id": "ios-\(UUID().uuidString.lowercased())",
            "subject_id": subject,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "provenance": [
                "label": provenanceLabel(result.provenance),
                "source": "neuroassist-ios",
                "device": deviceModelIdentifier(),
                "capture": [
                    "protocol": "OKN_STRIPES_10DEG_S",
                    "frames": frames.count,
                    "calibration_rms_deg": calibration.rmsErrorDeg.isFinite ? calibration.rmsErrorDeg : 0.0,
                    "distance_cm": calibration.meanDistanceCm.isFinite ? calibration.meanDistanceCm : 0.0,
                    "client_result": clientResult
                ] as [String: Any]
            ] as [String: Any],
            "trace": ["t": t, "x": x, "head": head],
            "history": history
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return String(id.prefix(40))
    }

    // MARK: - On-device history (file-protected)

    private func historyURL(subject: String) -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "ci-history", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(subject).json")
    }

    private func loadHistory(subject: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: historyURL(subject: subject)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    private func saveHistory(_ history: [[String: Any]], subject: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: history) else { return }
        try? data.write(to: historyURL(subject: subject), options: [.atomic, .completeFileProtection])
    }
}

// MARK: - Agent Collective card (Result screen)

struct AgentCollectiveCard: View {
    let bridge: CollectiveBridge
    let result: OKNAnalysisResult
    let calibration: CalibrationModel?
    let samples: [EyeSample]

    @State private var showSettings = false

    private var canRun: Bool {
        calibration != nil && samples.count >= 30 && bridge.hasConsented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(NeuroTheme.teal)
                Text("AGENT COLLECTIVE · CI")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
                .accessibilityLabel("Collective server settings")
            }

            Text("Five agents (signal quality, contextual memory, physiology, skeptic, auditor) independently re-examine this recording against your history. Quality and skeptic agents can veto.")
                .font(.system(.caption))
                .foregroundStyle(NeuroTheme.textSecondary)

            if showSettings || !bridge.hasConsented {
                consentAndSettings
            }

            switch bridge.state {
            case .idle:
                runButton
            case .running:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Collective deliberating…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Collective not run", systemImage: "wifi.exclamationmark")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(NeuroTheme.amber)
                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    Text("The on-device result above stands on its own; no collective verdict was produced.")
                        .font(.system(.caption))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    runButton
                }
            case .finished(let response, let host):
                CollectiveRunResultView(response: response, host: host, deviceResult: result)
            }
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
    }

    private var runButton: some View {
        Button {
            guard let calibration else { return }
            NeuroHaptics.impact(.medium)
            Task { await bridge.run(samples: samples, calibration: calibration, result: result) }
        } label: {
            HStack {
                Text(samples.count < 30 ? "No raw trace available for this result" : "Run Collective Review")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Spacer()
                Image(systemName: "arrow.up.forward.circle.fill")
            }
            .padding(14)
            .background(canRun ? NeuroTheme.teal : NeuroTheme.border)
            .foregroundStyle(canRun ? NeuroTheme.background : NeuroTheme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canRun)
    }

    private var consentAndSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CI SERVER")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            TextField("http://192.168.1.10:8000", text: Bindable(bridge).serverURLString)
                .font(.system(.caption, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(10)
                .background(NeuroTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Toggle(isOn: Bindable(bridge).hasConsented) {
                Text("Send this recording's numerical eye-angle trace (no images or video) and \(bridge.historyCount(for: result.provenance)) past session summaries to this server. It is processed off-device and the server stores nothing after responding.")
                    .font(.system(.caption))
                    .foregroundStyle(NeuroTheme.textPrimary)
            }
            .tint(NeuroTheme.teal)

            Button(role: .destructive) {
                bridge.deleteHistory(for: result.provenance)
            } label: {
                Text("Delete stored \(result.provenance == .liveCamera ? "personal" : "demo") history on this phone")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
            }
        }
        .padding(12)
        .background(NeuroTheme.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CollectiveRunResultView: View {
    let response: CollectiveRunResponse
    let host: String
    let deviceResult: OKNAnalysisResult

    private var decisionColor: Color {
        switch response.collective.decision {
        case "NO_CHANGE", "CHANGE": return NeuroTheme.teal
        default: return NeuroTheme.amber
        }
    }

    private var decisionExplanation: String {
        switch response.collective.decision {
        case "NO_CHANGE": return "Consistent with your personal baseline."
        case "CHANGE": return "Differs from your personal baseline beyond its uncertainty. This is a measurement observation, not a diagnosis."
        case "NO_BASELINE": return "Measured, but fewer than 3 trusted past sessions exist, so no personal comparison is made."
        default: return "The collective abstained: the evidence does not support a conclusion."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Verdict
            VStack(alignment: .leading, spacing: 4) {
                Text(response.collective.decision.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(decisionColor)
                Text(decisionExplanation)
                    .font(.system(.caption))
                    .foregroundStyle(NeuroTheme.textPrimary)
                Text("Processed off-device at \(host) · engine of record: \(response.engineOfRecord ?? "server") · \(String(format: "%.0f", response.serverMs ?? 0)) ms · audit chain \(response.collective.audit?.chainOk == true ? "intact" : "unverified")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }

            // Device vs server measurement (two independent engines)
            if let session = response.session {
                HStack(alignment: .top, spacing: 10) {
                    measurementCell(
                        title: "ON-DEVICE",
                        value: deviceResult.slowPhaseSpeedDegPerSec,
                        status: deviceResult.didAbstain ? "ABSTAINED" : "MEASURED",
                        caption: "SignalMath OKN"
                    )
                    measurementCell(
                        title: "SERVER",
                        value: session.measurement.value,
                        status: session.measurement.status,
                        caption: String(format: "neurocore · valid %.0f%%", session.quality.validFrac * 100)
                    )
                }
            }

            // Comparison with simpler systems on the same input
            if let compare = response.compare {
                HStack(spacing: 8) {
                    comparisonPill("Deterministic", compare.deterministic?.decision)
                    comparisonPill("Single agent", compare.singleAgent?.decision)
                    comparisonPill("Collective", response.collective.decision)
                }
            }

            if let vetoes = response.collective.vetoes, !vetoes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(vetoes, id: \.self) { veto in
                        Label {
                            Text("\(Self.agentName(veto.by)) vetoed: \(veto.text)")
                                .font(.system(.caption))
                        } icon: {
                            Image(systemName: "hand.raised.fill")
                        }
                        .foregroundStyle(NeuroTheme.amber)
                    }
                }
            }

            Text("DELIBERATION · \(response.collective.messages.count) MESSAGES · \(response.collective.rounds ?? 0) ROUNDS · BASELINE n=\(response.collective.baselineIds?.count ?? 0)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(response.collective.messages) { msg in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: Self.agentIcon(msg.sender))
                            .font(.system(size: 13))
                            .foregroundStyle(Self.kindColor(msg.kind))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("R\(msg.round) · \(Self.agentName(msg.sender)) → \(msg.to == "*" || msg.to == nil ? "all" : Self.agentName(msg.to ?? "")) · \(msg.kind)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Self.kindColor(msg.kind))
                            Text(msg.text)
                                .font(.system(.caption))
                                .foregroundStyle(NeuroTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func measurementCell(title: String, value: Double?, status: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            Text(value.map { String(format: "%.2f °/s", $0) } ?? "—")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(status == "MEASURED" ? NeuroTheme.teal : NeuroTheme.amber)
            Text("\(status) · \(caption)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(NeuroTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func comparisonPill(_ title: String, _ decision: String?) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            Text((decision ?? "—").replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(NeuroTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    static func agentName(_ id: String) -> String {
        switch id {
        case "signal_quality": return "Signal Quality"
        case "contextual_memory": return "Memory (CI)"
        case "physiology": return "Physiology"
        case "skeptic": return "Skeptic"
        case "auditor": return "Auditor"
        default: return id
        }
    }

    static func agentIcon(_ id: String) -> String {
        switch id {
        case "signal_quality": return "waveform.path.ecg"
        case "contextual_memory": return "externaldrive.badge.timemachine"
        case "physiology": return "eye"
        case "skeptic": return "questionmark.diamond"
        case "auditor": return "checkmark.seal"
        default: return "circle"
        }
    }

    static func kindColor(_ kind: String) -> Color {
        switch kind {
        case "VETO", "CHALLENGE": return NeuroTheme.amber
        case "VERDICT", "LIFT_VETO", "RESOLVE": return NeuroTheme.teal
        default: return NeuroTheme.textSecondary
        }
    }
}
