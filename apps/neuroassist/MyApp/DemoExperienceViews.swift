import SwiftUI
import Charts
import MapKit
import UserNotifications

// MARK: - Baseline History & Recorded Numerical Session Models

struct BaselineEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let gain: Double
    let slowPhaseSpeedDegPerSec: Double
    let ciLower: Double
    let ciUpper: Double
    let cleanWindows: Int
}

struct RecordedNumericalSession: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let recordedDate: Date
    let calibration: CalibrationModel
    let samples: [EyeSample]
    let summaryNote: String
}

enum DemoSimScenario: String, CaseIterable, Identifiable {
    case validPursuit = "Valid OKN Response (0.80 Gain)"
    case trackingLoss = "Tracking Loss / Too Dark (ABSTAIN)"
    case poorCalibration = "Poor Calibration Fit 2.1° (ABSTAIN)"
    case headMovement = "Excessive Head Movement 3.8° (ABSTAIN)"
    case highNoise = "High Tracking Noise 1.6° (ABSTAIN)"
    case insufficientWindows = "Insufficient Slow-Phase Windows (ABSTAIN)"

    var id: String { rawValue }
}

@MainActor
@Observable
final class DemoExperienceStore {
    var stageModeEnabled: Bool = false
    var showPerformanceHUD: Bool = false
    var consecutiveAbstainCount: Int = 0
    var restTimerRemainingSec: Int = 0
    var restTimerActive: Bool = false
    var arriveSafeActive: Bool = false
    var arriveSafeContactName: String = "Alex"
    var arriveSafeDestinationName: String = "Home · Cupertino"
    var arriveSafeETAString: String = ""
    var baselineEntries: [BaselineEntry] = []
    var recordedSessions: [RecordedNumericalSession] = []

    private var restTimerTask: Task<Void, Never>? = nil

    init() {
        seedRecordedSessions()
    }

    func recordRealResult(_ result: OKNAnalysisResult, samples: [EyeSample], calibration: CalibrationModel?) {
        // Never allow SIMULATED or RECORDED SESSION runs to pollute personal baseline or consecutive abstain count
        guard result.provenance == .liveCamera else { return }

        if result.didAbstain {
            consecutiveAbstainCount += 1
        } else {
            consecutiveAbstainCount = 0
            if let gain = result.gain,
               let speed = result.slowPhaseSpeedDegPerSec,
               let ci = result.confidenceInterval95 {
                let entry = BaselineEntry(
                    id: UUID(),
                    date: Date(),
                    gain: gain,
                    slowPhaseSpeedDegPerSec: speed,
                    ciLower: ci.lower / 10.0,
                    ciUpper: ci.upper / 10.0,
                    cleanWindows: result.cleanWindowCount
                )
                baselineEntries.append(entry)
            }
        }

        if let calibration, samples.count >= 60 {
            let rec = RecordedNumericalSession(
                id: UUID(),
                title: result.didAbstain
                    ? "Live Numerical Capture (ABSTAIN)"
                    : String(format: "Live Numerical Capture (Gain %.2f)", result.gain ?? 0.0),
                recordedDate: Date(),
                calibration: calibration,
                samples: samples,
                summaryNote: "Consented numerical eye-pose trace stored in memory (zero video/images)."
            )
            recordedSessions.insert(rec, at: 0)
        }
    }

    var usualGainRange: (lower: Double, upper: Double, median: Double) {
        let gains = baselineEntries.map(\.gain)
        guard gains.count >= 2, let med = SignalMath.median(gains) else {
            // Default reference band before multiple live measurements are collected
            return (0.68, 0.88, 0.78)
        }
        let mad = SignalMath.mad(gains) ?? 0.05
        let spread = max(0.06, 2.0 * 1.4826 * mad)
        return (max(0.20, med - spread), min(1.15, med + spread), med)
    }

    func startRest20MinTimer() {
        restTimerTask?.cancel()
        restTimerRemainingSec = 20 * 60
        restTimerActive = true
        NeuroHaptics.notify(.success)

        // Schedule local notification if authorized
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "NeuroAssist · 20-Minute Rest Complete"
            content.body = "Ready to retake your pre-drive eye movement check?"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 20 * 60, repeats: false)
            let req = UNNotificationRequest(identifier: "neuroassist.rest.timer", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }

        restTimerTask = Task { @MainActor in
            while restTimerRemainingSec > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                restTimerRemainingSec -= 1
            }
            restTimerActive = false
        }
    }

    func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerActive = false
        restTimerRemainingSec = 0
    }

    // MARK: - Pre-seeded Consented Numerical Sessions (For Recorded Session Replay)

    private func seedRecordedSessions() {
        let calPoints = [-10.0, -5.0, 0.0, 5.0, 10.0].map { deg in
            CalibrationPointSample(
                targetOffsetCm: tan(deg * .pi / 180.0) * 30.0,
                distanceCm: 30.0,
                trueAngleDeg: deg,
                medianMeasuredYawDeg: deg,
                madYawDeg: 0.09,
                sampleCount: 40,
                durationSec: 1.0,
                stoppedEarly: true
            )
        }
        guard let cal = SignalMath.fitCalibration(points: calPoints) else { return }

        let cleanSamples = Self.generateTrace(
            trueVelocityDegPerSec: 7.9,
            noiseSigmaDeg: 0.09,
            headYawExcursionDeg: 0.3,
            trackedProbability: 1.0
        )
        let headMoveSamples = Self.generateTrace(
            trueVelocityDegPerSec: 7.6,
            noiseSigmaDeg: 0.11,
            headYawExcursionDeg: 3.4,
            trackedProbability: 1.0
        )

        recordedSessions = [
            RecordedNumericalSession(
                id: UUID(),
                title: "Reference Subject #01 — Clean Sawtooth (10.0 s)",
                recordedDate: Date().addingTimeInterval(-3600 * 5),
                calibration: cal,
                samples: cleanSamples,
                summaryNote: "600 numerical frames at 60 Hz · 30.0 cm distance · 0 video frames saved."
            ),
            RecordedNumericalSession(
                id: UUID(),
                title: "Reference Subject #02 — Head Movement Artifact (ABSTAIN)",
                recordedDate: Date().addingTimeInterval(-3600 * 12),
                calibration: cal,
                samples: headMoveSamples,
                summaryNote: "600 numerical frames at 60 Hz · 95th % head rotation 3.2° > 2.0° gate."
            )
        ]
    }

    // MARK: - Transparent Demonstration Mode Generator (Always Watermarked SIMULATED)

    static func runSimulatedScenario(_ scenario: DemoSimScenario, mode: MeasurementProtocolMode) -> (OKNAnalysisResult, CalibrationModel) {
        let calRMS: Double = (scenario == .poorCalibration) ? 2.15 : 0.28
        let calPoints = [-10.0, -5.0, 0.0, 5.0, 10.0].enumerated().map { idx, deg in
            let perturbation = (scenario == .poorCalibration) ? (idx % 2 == 0 ? 2.4 : -2.4) : (idx % 2 == 0 ? 0.22 : -0.22)
            return CalibrationPointSample(
                targetOffsetCm: tan(deg * .pi / 180.0) * 30.0,
                distanceCm: 30.0,
                trueAngleDeg: deg,
                medianMeasuredYawDeg: deg + perturbation,
                madYawDeg: 0.10,
                sampleCount: 45,
                durationSec: 1.0,
                stoppedEarly: true
            )
        }
        let fittedCal = SignalMath.fitCalibration(points: calPoints) ?? CalibrationModel(
            slope: 1.0,
            intercept: 0.0,
            rmsErrorDeg: calRMS,
            meanDistanceCm: 30.0,
            totalCalibrationDurationSec: 5.0,
            points: calPoints
        )

        let samples: [EyeSample]
        switch scenario {
        case .validPursuit:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 0.10, headYawExcursionDeg: 0.3, trackedProbability: 1.0)
        case .trackingLoss:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 0.12, headYawExcursionDeg: 0.4, trackedProbability: 0.55)
        case .poorCalibration:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 0.10, headYawExcursionDeg: 0.3, trackedProbability: 1.0)
        case .headMovement:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 0.10, headYawExcursionDeg: 3.8, trackedProbability: 1.0)
        case .highNoise:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 1.65, headYawExcursionDeg: 0.3, trackedProbability: 1.0)
        case .insufficientWindows:
            samples = generateTrace(trueVelocityDegPerSec: 8.0, noiseSigmaDeg: 0.12, headYawExcursionDeg: 0.3, trackedProbability: 1.0, durationSec: 2.2)
        }

        let res = SignalMath.analyzeOptokinetic(
            samples: samples,
            calibration: fittedCal,
            stripeDirectionSign: 1.0,
            mode: mode,
            provenance: .simulated,
            stoppedEarly: false
        )
        return (res, fittedCal)
    }

    static func generateTrace(
        trueVelocityDegPerSec: Double,
        noiseSigmaDeg: Double,
        headYawExcursionDeg: Double,
        trackedProbability: Double,
        durationSec: Double = 10.0
    ) -> [EyeSample] {
        let fps = 60.0
        let total = Int(fps * durationSec)
        var state: UInt64 = 0xA5A5_1234_8765_4321
        func nextUniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        func nextGaussian(_ sigma: Double) -> Double {
            let u1 = max(1e-12, nextUniform())
            let u2 = nextUniform()
            return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2) * sigma
        }

        var out: [EyeSample] = []
        out.reserveCapacity(total)
        let resetPeriod = 0.55
        for i in 0..<total {
            let t = Double(i) / fps
            let phase = t.truncatingRemainder(dividingBy: resetPeriod)
            let cleanYaw = -2.2 + trueVelocityDegPerSec * phase
            let noisyYaw = cleanYaw + nextGaussian(noiseSigmaDeg)
            let tracked = nextUniform() <= trackedProbability
            let hYaw = headYawExcursionDeg * sin(2.0 * .pi * 0.35 * t)

            out.append(
                EyeSample(
                    timestamp: t,
                    rawYawDeg: noisyYaw,
                    faceTracked: tracked,
                    blinkLeft: 0.04,
                    blinkRight: 0.04,
                    headYawDeg: hYaw,
                    headPitchDeg: 0.1,
                    distanceCm: 30.0,
                    ambientLightLux: tracked ? 950.0 : 120.0
                )
            )
        }
        return out
    }
}

// MARK: - 7. PAUSE & ARRIVE SAFE SHEET (After 2 Abstains or Directly from Home)

struct PauseAndArriveSafeSheet: View {
    let store: DemoExperienceStore
    let onRetakeCheck: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showingArriveSafeConsent = false
    @State private var selectedCoordinate = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var showingMissedArrivalPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(NeuroTheme.amber)
                            Text("PAUSE & ARRIVE SAFE")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        Text("Let's not rush this. We couldn't get a reliable reading — if you feel tired or unwell, don't drive yet.")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }

                    // Card 1: Rest 20 min
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "timer")
                                .font(.title2)
                                .foregroundStyle(NeuroTheme.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rest 20 min")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("Starts a 20-minute countdown timer and schedules a 'Ready to retake?' notification.")
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                            Spacer()
                        }

                        if store.restTimerActive {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("REST TIMER ACTIVE")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(NeuroTheme.teal)
                                    Text(String(format: "%02d:%02d", store.restTimerRemainingSec / 60, store.restTimerRemainingSec % 60))
                                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                                        .foregroundStyle(NeuroTheme.teal)
                                }
                                Spacer()
                                Button("End & Retake") {
                                    store.stopRestTimer()
                                    dismiss()
                                    onRetakeCheck()
                                }
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(12)
                            .background(NeuroTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Button {
                                store.startRest20MinTimer()
                            } label: {
                                Text("Start 20-Min Rest Timer & Notification")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NeuroTheme.teal)
                                    .foregroundStyle(NeuroTheme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                    // Card 2: Get a ride
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "car.fill")
                                .font(.title2)
                                .foregroundStyle(NeuroTheme.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Get a ride")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("Open ride-share apps or call a trusted contact directly.")
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                if let url = URL(string: "uber://") {
                                    openURL(url)
                                }
                            } label: {
                                Label("Open Uber", systemImage: "arrow.up.right.square")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NeuroTheme.background)
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                if let url = URL(string: "lyft://") {
                                    openURL(url)
                                }
                            } label: {
                                Label("Open Lyft", systemImage: "arrow.up.right.square")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NeuroTheme.background)
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                    // Card 3: Arrive Safe (MapKit destination + explicit consent + prefilled message share)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "location.fill.viewfinder")
                                .font(.title2)
                                .foregroundStyle(NeuroTheme.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Arrive Safe")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("Pick a destination and trusted contact. Shares an explicit user-consented ETA + Apple Maps link.")
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }

                        Map(position: $cameraPosition) {
                            Marker(store.arriveSafeDestinationName, coordinate: selectedCoordinate)
                                .tint(NeuroTheme.teal)
                        }
                        .frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack(spacing: 10) {
                            TextField("Trusted Contact", text: Bindable(store).arriveSafeContactName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(NeuroTheme.background)
                                .foregroundStyle(NeuroTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            TextField("Destination", text: Bindable(store).arriveSafeDestinationName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(NeuroTheme.background)
                                .foregroundStyle(NeuroTheme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .font(.system(.caption, design: .monospaced))

                        if store.arriveSafeActive {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Circle().fill(NeuroTheme.teal).frame(width: 8, height: 8)
                                    Text("Sharing with \(store.arriveSafeContactName) · ETA \(store.arriveSafeETAString)")
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .foregroundStyle(NeuroTheme.teal)
                                    Spacer()
                                    Button("Stop") {
                                        store.arriveSafeActive = false
                                    }
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.amber)
                                }

                                let mapsLink = "https://maps.apple.com/?ll=\(selectedCoordinate.latitude),\(selectedCoordinate.longitude)&q=\(store.arriveSafeDestinationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Destination")"
                                let messageText = "Arrive Safe check-in: Heading to \(store.arriveSafeDestinationName), ETA \(store.arriveSafeETAString). Apple Maps: \(mapsLink)"

                                ShareLink(item: messageText) {
                                    Label("Send Prefilled ETA & Apple Maps Message", systemImage: "message.fill")
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(NeuroTheme.teal)
                                        .foregroundStyle(NeuroTheme.background)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                Button {
                                    showingMissedArrivalPrompt = true
                                } label: {
                                    Text("Preview 'ETA + 15 min' Check-In Prompt")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(NeuroTheme.textSecondary)
                                }
                            }
                            .padding(12)
                            .background(NeuroTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Button {
                                showingArriveSafeConsent = true
                            } label: {
                                Text("Review Consent & Share ETA with \(store.arriveSafeContactName)")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NeuroTheme.background)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.teal, lineWidth: 1))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                    // Always-Visible Emergency Card (Stroke Warning Signs + User-Tapped Call 911)
                    EmergencyStrokeWarningCard()
                }
                .padding(20)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Pause & Arrive Safe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
            .alert("Explicit Location & ETA Consent", isPresented: $showingArriveSafeConsent) {
                Button("Cancel", role: .cancel) {}
                Button("Consent & Prepare Message") {
                    let etaDate = Date().addingTimeInterval(25 * 60)
                    let fmt = DateFormatter()
                    fmt.timeStyle = .short
                    store.arriveSafeETAString = fmt.string(from: etaDate)
                    store.arriveSafeActive = true
                    NeuroHaptics.notify(.success)
                }
            } message: {
                Text("NeuroAssist only shares a one-time prefilled ETA and Apple Maps link when you explicitly tap Send. It does not perform continuous background tracking or auto-contact authorities.")
            }
            .alert("ETA + 15 Min Check-In", isPresented: $showingMissedArrivalPrompt) {
                Button("I've Arrived Safely", role: .cancel) {
                    store.arriveSafeActive = false
                }
                if let smsURL = URL(string: "sms:&body=I%20haven't%20arrived%20yet%20at%20\(store.arriveSafeDestinationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "destination").%20Last%20shared%20map:%20https://maps.apple.com/?ll=\(selectedCoordinate.latitude),\(selectedCoordinate.longitude)") {
                    Button("Send 'I haven't arrived yet'") {
                        openURL(smsURL)
                    }
                }
            } message: {
                Text("You haven't marked your trip complete 15 minutes after your ETA (\(store.arriveSafeETAString)). Would you like to send a prefilled check-in message to \(store.arriveSafeContactName)?")
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EmergencyStrokeWarningCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(NeuroTheme.amber)
                Text("EMERGENCY WARNING SIGNS (B.E. F.A.S.T.)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(NeuroTheme.amber)
            }

            Text("If you or someone nearby notices sudden **balance** loss, **vision** changes, **face drooping**, **arm weakness**, or **speech** difficulty, seek emergency medical care immediately.")
                .font(.system(.caption, design: .default))
                .foregroundStyle(NeuroTheme.textPrimary)

            Button {
                // User explicitly taps to open the system phone dialer; never auto-dials without user interaction
                if let tel = URL(string: "tel://911") {
                    openURL(tel)
                }
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Call 911 (User-Initiated Dial)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(NeuroTheme.amber)
                .foregroundStyle(NeuroTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NeuroTheme.amber.opacity(0.8), lineWidth: 1.5)
        )
    }
}

// MARK: - 8. BASELINE SHEET (Personal Usual Band + Today's Dot + Interval)

struct BaselineTrendSheet: View {
    let store: DemoExperienceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let band = store.usualGainRange
                    let latest = store.baselineEntries.last

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PERSONAL OPTOKINETIC GAIN BASELINE")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)
                        if let latest {
                            let within = (band.lower...band.upper).contains(latest.gain)
                            Text(within ? "Today's reading is within your usual range." : "Today's reading shows a change from your usual range.")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(within ? NeuroTheme.teal : NeuroTheme.amber)
                        } else {
                            Text("Complete a live measurement to plot today's point against your usual band.")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NeuroTheme.textPrimary)
                        }
                        Text(String(format: "Usual personal band: %.2f – %.2f gain (median %.2f). Simulated runs are isolated and never stored here.", band.lower, band.upper, band.median))
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }

                    // Trend Chart with shaded Usual Band + each measurement's 95% interval
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TREND VS YOUR USUAL BAND")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        Chart {
                            RectangleMark(
                                yStart: .value("Usual Low", band.lower),
                                yEnd: .value("Usual High", band.upper)
                            )
                            .foregroundStyle(NeuroTheme.teal.opacity(0.14))

                            RuleMark(y: .value("Usual Median", band.median))
                                .foregroundStyle(NeuroTheme.teal.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            ForEach(Array(store.baselineEntries.enumerated()), id: \.element.id) { idx, entry in
                                RuleMark(
                                    x: .value("Run", idx + 1),
                                    yStart: .value("CI Low", entry.ciLower),
                                    yEnd: .value("CI High", entry.ciUpper)
                                )
                                .foregroundStyle(NeuroTheme.textSecondary)
                                .lineStyle(StrokeStyle(lineWidth: 2))

                                PointMark(
                                    x: .value("Run", idx + 1),
                                    y: .value("Gain", entry.gain)
                                )
                                .symbolSize(idx == store.baselineEntries.count - 1 ? 90 : 50)
                                .foregroundStyle(idx == store.baselineEntries.count - 1 ? NeuroTheme.teal : NeuroTheme.textPrimary)
                            }
                        }
                        .chartYScale(domain: 0.0...1.2)
                        .frame(height: 220)
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                    Text(NeuroTheme.researchFooter)
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Personal Baseline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 9. MODULES SHEET (The Vision Slide, In-App)

struct ModulesVisionSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let modules: [(title: String, subtitle: String, icon: String, enabled: Bool)] = [
        ("Measurement (OKN Core)", "Calibrated horizontal optokinetic slow-phase velocity & 11-gate quality engine.", "waveform.path.ecg", true),
        ("Vestibular", "Horizontal & vertical gaze stability and VOR suppression research endpoints.", "gyroscope", false),
        ("Fatigue", "Longitudinal saccadic peak-velocity & slow-phase drift change from personal baseline.", "moon.zzz.fill", false),
        ("Concussion", "Post-impact oculomotor smooth pursuit and convergence research tracking.", "brain.head.profile", false),
        ("Cognition", "Antisaccade latency and visual working-memory fixation dispersion protocols.", "sparkles.rectangle.stack", false),
        ("Drug-Trial Endpoints", "Timestamped, reproducible digital oculomotor biomarkers with audit CSV export.", "cross.vial.fill", false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        SawtoothSignatureView(height: 20, cycles: 3)
                            .frame(width: 48)
                        Text("ONE SIGNAL ENGINE → SIX RESEARCH MODULES")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)
                    }

                    Text("NeuroAssist separates calibrated ocular measurement from downstream clinical validation. Every module below shares the same 60 Hz TrueDepth acquisition & abstention architecture.")
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)

                    ForEach(modules, id: \.title) { mod in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: mod.icon)
                                    .foregroundStyle(mod.enabled ? NeuroTheme.teal : NeuroTheme.textSecondary)
                                Text(mod.title)
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Spacer()
                                Text(mod.enabled ? "ACTIVE ENGINE" : "RESEARCH ONLY")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(mod.enabled ? NeuroTheme.teal.opacity(0.2) : NeuroTheme.border)
                                    .foregroundStyle(mod.enabled ? NeuroTheme.teal : NeuroTheme.textSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }

                            Text(mod.subtitle)
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(NeuroTheme.textSecondary)

                            Text("Research only · needs its own validation")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        .padding(16)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(mod.enabled ? NeuroTheme.teal.opacity(0.6) : NeuroTheme.border, lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Platform Modules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
