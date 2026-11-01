import SwiftUI
import UIKit
import ARKit
import SceneKit

enum NeuroTheme {
    // Exact specified palette:
    // Background #0B0F14
    static let background = Color(red: 11.0 / 255.0, green: 15.0 / 255.0, blue: 20.0 / 255.0)
    // Cards #101827
    static let surface = Color(red: 16.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
    // Lines #22314A
    static let border = Color(red: 34.0 / 255.0, green: 49.0 / 255.0, blue: 74.0 / 255.0)
    // Text #E6EDF5
    static let textPrimary = Color(red: 230.0 / 255.0, green: 237.0 / 255.0, blue: 245.0 / 255.0)
    // Muted #8DA1B8
    static let textSecondary = Color(red: 141.0 / 255.0, green: 161.0 / 255.0, blue: 184.0 / 255.0)
    // Teal #2DD4BF = trusted result
    static let teal = Color(red: 45.0 / 255.0, green: 212.0 / 255.0, blue: 191.0 / 255.0)
    // Amber #F5A524 = ABSTAIN / warning
    static let amber = Color(red: 245.0 / 255.0, green: 165.0 / 255.0, blue: 36.0 / 255.0)

    static let homeTagline = "Eyes don't lie. Neither do we."
    static let researchFooter = "Research prototype. Measures eye movement; doesn't diagnose."
}

// MARK: - Teal Sawtooth Logo, Loader & Signature Shape (slow climb, instant drop)

struct SawtoothWaveShape: Shape {
    var cycles: Int = 3
    var phaseProgress: CGFloat = 1.0

    var animatableData: CGFloat {
        get { phaseProgress }
        set { phaseProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 1, h > 1, cycles > 0 else { return path }

        let cycleW = w / CGFloat(cycles)
        let topY = rect.minY + h * 0.12
        let bottomY = rect.maxY - h * 0.12

        path.move(to: CGPoint(x: rect.minX, y: bottomY))
        for i in 0..<cycles {
            let startX = rect.minX + CGFloat(i) * cycleW
            let climbEndX = startX + cycleW * 0.88
            let dropEndX = startX + cycleW
            // Slow linear climb (pursuit slow phase)
            path.addLine(to: CGPoint(x: climbEndX, y: topY))
            // Instant vertical reset drop (quick phase)
            path.addLine(to: CGPoint(x: dropEndX, y: bottomY))
        }
        return path.trimmedPath(from: 0.0, to: min(1.0, max(0.0, phaseProgress)))
    }
}

struct SawtoothSignatureView: View {
    var height: CGFloat = 24
    var cycles: Int = 4
    var animate: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0.0

    var body: some View {
        SawtoothWaveShape(cycles: cycles, phaseProgress: (animate && !reduceMotion) ? drawn : 1.0)
            .stroke(
                NeuroTheme.teal,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            .frame(height: height)
            .shadow(color: NeuroTheme.teal.opacity(0.45), radius: 6)
            .onAppear {
                guard animate && !reduceMotion else {
                    drawn = 1.0
                    return
                }
                withAnimation(.spring(duration: 1.0, bounce: 0.15)) {
                    drawn = 1.0
                }
            }
    }
}

// MARK: - Persistent Watermark Banner for SIMULATED or RECORDED SESSION

struct ProvenanceWatermarkBanner: View {
    let provenance: DataProvenance

    var body: some View {
        if provenance != .liveCamera {
            HStack(spacing: 8) {
                Image(systemName: provenance == .simulated ? "sparkles.tv" : "waveform.badge.magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                Text(provenance.rawValue)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                Text("·")
                Text(provenance == .simulated ? "ISOLATED DEMO (DOES NOT SAVE TO BASELINE)" : "CONSENTED NUMERICAL REPLAY (NO VIDEO)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(NeuroTheme.background)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(provenance == .simulated ? NeuroTheme.amber : NeuroTheme.teal)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Real-Time Performance Developer HUD Overlay

struct RealTimePerformanceHUD: View {
    let tracker: FaceEyeTracker

    private var thermalLabel: String {
        switch tracker.thermalState {
        case .nominal: return "NOMINAL"
        case .fair: return "FAIR"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        @unknown default: return "NOMINAL"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HUDMetric(label: "FPS", value: String(format: "%.0f", tracker.fps), isGood: tracker.fps >= 50)
            HUDMetric(label: "DROPS", value: "\(tracker.droppedFrameCount)", isGood: tracker.droppedFrameCount == 0)
            HUDMetric(label: "PROC", value: String(format: "%.1fms", tracker.signalProcessingLatencyMs), isGood: tracker.signalProcessingLatencyMs < 5.0)
            HUDMetric(label: "UI", value: String(format: "%.1fms", tracker.renderLatencyMs), isGood: tracker.renderLatencyMs < 8.0)
            HUDMetric(label: "VALID", value: String(format: "%.0f%%", tracker.validSamplePercentage), isGood: tracker.validSamplePercentage >= 85.0)
            HUDMetric(label: "TRACK", value: tracker.faceTracked ? "LOCKED" : "LOST", isGood: tracker.faceTracked)
            HUDMetric(label: "THERM", value: thermalLabel, isGood: tracker.thermalState == .nominal || tracker.thermalState == .fair)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NeuroTheme.background.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(NeuroTheme.border, lineWidth: 1)
        )
    }
}

struct HUDMetric: View {
    let label: String
    let value: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isGood ? NeuroTheme.teal : NeuroTheme.amber)
        }
    }
}

enum NeuroHaptics {
    @MainActor
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }

    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(type)
    }
}

enum ScreenGeometry {
    /// Approximate physical points-per-centimeter on modern iPhones (~163 DPI logical points = 64.17 pt/cm).
    static let pointsPerCm: Double = 163.0 / 2.54

    static func pointsToCm(_ points: CGFloat) -> Double {
        Double(points) / pointsPerCm
    }

    static func cmToPoints(_ cm: Double) -> CGFloat {
        CGFloat(cm * pointsPerCm)
    }

    /// Converts a visual angle (degrees) at a given viewing distance (cm) into screen points.
    static func degreesToPoints(degrees: Double, distanceCm: Double) -> CGFloat {
        let validDist = max(20.0, min(50.0, distanceCm))
        let cm = 2.0 * validDist * tan((degrees * .pi / 180.0) / 2.0)
        return cmToPoints(cm)
    }
}

// MARK: - Asynchronous Background CSV Research Export

enum ResearchCSVExporter {
    static func generateCSVAsync(result: OKNAnalysisResult, calibration: CalibrationModel?) async -> URL? {
        generateCSV(result: result, calibration: calibration)
    }

    static func generateCSV(result: OKNAnalysisResult, calibration: CalibrationModel?) -> URL? {
        var lines: [String] = []
        let iso = ISO8601DateFormatter().string(from: Date())
        lines.append("# NeuroAssist Research Prototype — Optokinetic Measurement Export")
        lines.append("# Timestamp,\(iso)")
        lines.append("# Provenance,\(result.provenance.rawValue)")
        lines.append("# Protocol Mode,\(result.mode.rawValue)")
        lines.append("# Stopped Early,\(result.stoppedEarly ? "YES" : "NO")")
        lines.append(String(format: "# Recording Duration (s),%.2f", result.recordingDurationSec))
        lines.append(String(format: "# Analysis Latency (ms),%.2f", result.analysisLatencyMs))
        lines.append("# Total Frames,\(result.totalFrames)")
        lines.append("# Valid Frames,\(result.validFrames)")
        lines.append("# Rejected Frames,\(result.rejectedFrames)")
        lines.append(String(format: "# Unsmoothed Tracking Noise (deg),%.4f", result.trackingNoiseDeg))
        lines.append("# Disclaimer,Research prototype. Measures eye movement; doesn't diagnose.")
        lines.append("# Status,\(result.didAbstain ? "ABSTAIN" : "MEASURED")")

        if let cal = calibration {
            lines.append(String(format: "# Calibration Slope,%.4f", cal.slope))
            lines.append(String(format: "# Calibration Intercept (deg),%.4f", cal.intercept))
            lines.append(String(format: "# Calibration RMS Error (deg),%.4f", cal.rmsErrorDeg))
            lines.append(String(format: "# Calibration Mean Distance (cm),%.2f", cal.meanDistanceCm))
            lines.append(String(format: "# Calibration Total Duration (s),%.2f", cal.totalCalibrationDurationSec))
        }

        if !result.didAbstain,
           let gain = result.gain,
           let speed = result.slowPhaseSpeedDegPerSec,
           let ci = result.confidenceInterval95 {
            lines.append(String(format: "# Optokinetic Gain,%.4f", gain))
            lines.append(String(format: "# Slow-Phase Speed (deg/s),%.4f", speed))
            lines.append(String(format: "# 95% CI Lower (deg/s),%.4f", ci.lower))
            lines.append(String(format: "# 95% CI Upper (deg/s),%.4f", ci.upper))
            lines.append("# Clean Windows,\(result.cleanWindowCount)")
        } else {
            lines.append("# Optokinetic Gain,ABSTAIN")
            lines.append("# Slow-Phase Speed (deg/s),ABSTAIN")
        }

        lines.append("")
        lines.append("# QUALITY GATE CHECKS")
        lines.append("check_id,category,check_name,passed,measured_value,rule")
        for check in result.checks {
            lines.append("\(check.id),\"\(check.category.rawValue)\",\"\(check.name)\",\(check.passed ? "PASS" : "FAIL"),\"\(check.valueString)\",\"\(check.ruleString)\"")
        }

        lines.append("")
        lines.append("# FITTED SLOW-PHASE WINDOWS")
        lines.append("window_index,start_time_s,end_time_s,slope_deg_per_s,intercept_deg,sample_count,mean_abs_residual_deg")
        for (idx, w) in result.windows.enumerated() {
            lines.append(
                String(
                    format: "%d,%.4f,%.4f,%.4f,%.4f,%d,%.4f",
                    idx + 1,
                    w.startTime,
                    w.endTime,
                    w.slopeDegPerSec,
                    w.interceptDeg,
                    w.sampleCount,
                    w.meanAbsResidualDeg
                )
            )
        }

        lines.append("")
        lines.append("# PER-FRAME CALIBRATED EYE TRACE")
        lines.append("frame_index,time_s,calibrated_angle_deg,filtered_angle_deg,is_valid,is_fast_phase_or_guard")
        for pt in result.tracePoints {
            lines.append(
                String(
                    format: "%d,%.4f,%.4f,%.4f,%d,%d",
                    pt.id,
                    pt.timeSec,
                    pt.isValid ? pt.angleDeg : .nan,
                    pt.isValid ? pt.filteredAngleDeg : .nan,
                    pt.isValid ? 1 : 0,
                    pt.isFastPhase ? 1 : 0
                )
            )
        }

        let csvContent = lines.joined(separator: "\n")
        let filename = "NeuroAssist_OKN_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}

// MARK: - Live TrueDepth Front Camera Feed & Emulation UI

struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    init(session: ARSession) {
        self.session = session
    }

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)
        scnView.session = session
        scnView.scene = SCNScene()
        scnView.automaticallyUpdatesLighting = true
        scnView.rendersCameraGrain = false
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .black
        return scnView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }
}

struct SimulatorCameraPlaceholderView: View {
    let tracker: FaceEyeTracker
    @State private var scanLineY: CGFloat = 0.0

    init(tracker: FaceEyeTracker) {
        self.tracker = tracker
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.10, blue: 0.18), Color(red: 0.02, green: 0.04, blue: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Image(systemName: "faceid")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(w * 0.45, 80), height: min(h * 0.45, 80))
                    .foregroundStyle(tracker.faceTracked ? NeuroTheme.teal.opacity(0.45) : NeuroTheme.textSecondary.opacity(0.25))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, NeuroTheme.teal.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: w, height: 14)
                    .position(x: w * 0.5, y: scanLineY)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            scanLineY = h
                        }
                    }

                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tracker.isRunning ? NeuroTheme.teal : NeuroTheme.amber)
                            .frame(width: 5, height: 5)
                        Text(tracker.isSimulatorEmulation ? "DEMO MODE · 60 HZ" : "ACQUIRING FEED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 6)
                }
            }
        }
    }
}

struct CameraPermissionDeniedMiniView: View {
    let tracker: FaceEyeTracker

    init(tracker: FaceEyeTracker) {
        self.tracker = tracker
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(NeuroTheme.amber)
            Text("Camera Access Disabled")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(NeuroTheme.textPrimary)
            Button {
                tracker.openSettings()
            } label: {
                Text("Open Settings")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(NeuroTheme.amber)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeuroTheme.surface)
    }
}
