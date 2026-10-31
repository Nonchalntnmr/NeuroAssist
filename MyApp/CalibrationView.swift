import SwiftUI
import Charts

struct CalibrationView: View {
    let tracker: FaceEyeTracker
    let store: DemoExperienceStore
    let protocolMode: MeasurementProtocolMode
    let onBack: () -> Void
    let onCalibrationAccepted: (CalibrationModel) -> Void

    // 5 horizontal fractions of usable half-width: center (0), -half (-0.5), +half (+0.5), -full (-1.0), +full (+1.0)
    private let dotFractions: [Double] = [0.0, -0.5, 0.5, -1.0, 1.0]
    private let maxSecondsPerDot: Double = 2.0

    @State private var isRunningDots: Bool = false
    @State private var currentDotIndex: Int = 0
    @State private var dotElapsedSec: Double = 0.0
    @State private var liveRunningFitDeg: Double? = nil
    @State private var fittedModel: CalibrationModel? = nil
    @State private var failureMessage: String? = nil
    @State private var calibrationTask: Task<Void, Never>? = nil

    private var distanceInRange: Bool {
        tracker.faceTracked && (25.0...40.0).contains(tracker.distanceCm)
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalInset: CGFloat = 32.0
            let usableHalfWidthPt = max(60.0, (geo.size.width - horizontalInset * 2.0) / 2.0)

            VStack(spacing: 16) {
                // Header
                HStack {
                    Button {
                        calibrationTask?.cancel()
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Ready Check")
                        }
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    }

                    Spacer()

                    Text("STEP 2 OF 3 · CALIBRATION")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(NeuroTheme.teal)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                if store.showPerformanceHUD {
                    RealTimePerformanceHUD(tracker: tracker)
                        .padding(.horizontal, 22)
                }

                // Live Fit & Distance Readout Pill ("fit 0.31° · limit 1.5°")
                HStack(spacing: 10) {
                    Circle()
                        .fill((distanceInRange && tracker.isHeadSteady) ? NeuroTheme.teal : NeuroTheme.amber)
                        .frame(width: 8, height: 8)
                    Text(
                        tracker.faceTracked
                        ? String(format: "Dist %.0f cm · Head %@", tracker.distanceCm, tracker.isHeadSteady ? "Steady" : "Hold still")
                        : "Face not locked — center your face"
                    )
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle((distanceInRange && tracker.isHeadSteady) ? NeuroTheme.textPrimary : NeuroTheme.amber)

                    Spacer()

                    let fitVal = fittedModel?.rmsErrorDeg ?? liveRunningFitDeg
                    Text(
                        fitVal != nil
                        ? String(format: "fit %.2f° · limit 1.5°", fitVal!)
                        : "fit —° · limit 1.5°"
                    )
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle((fitVal ?? 0.0) <= 1.5 ? NeuroTheme.teal : NeuroTheme.amber)
                }
                .padding(12)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 22)

                Spacer()

                // Interactive 5-dot arena on near-black screen with glowing halo rings
                if isRunningDots {
                    let settleCutoff = protocolMode == .adaptiveFast ? SignalMath.adaptiveDotSettleSec : 0.8
                    let isSamplingWindow = dotElapsedSec >= settleCutoff
                    VStack(spacing: 26) {
                        Text(
                            isSamplingWindow
                            ? (protocolMode == .adaptiveFast ? "Sampling fixation… locks on stability" : "Sampling fixation… hold gaze steady")
                            : "Look directly at the glowing teal dot"
                        )
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(isSamplingWindow ? NeuroTheme.teal : NeuroTheme.textSecondary)
                        .multilineTextAlignment(.center)

                        ZStack {
                            // Subtle guide ticks for the 5 horizontal positions
                            ForEach(0..<dotFractions.count, id: \.self) { idx in
                                Circle()
                                    .fill(NeuroTheme.border)
                                    .frame(width: 6, height: 6)
                                    .offset(x: CGFloat(dotFractions[idx]) * usableHalfWidthPt)
                            }

                            // Active calibration target dot with glowing concentric halo rings
                            let activeOffsetPt = CGFloat(dotFractions[currentDotIndex]) * usableHalfWidthPt
                            let targetSpan = protocolMode == .adaptiveFast ? SignalMath.adaptiveDotMinDurationSec : maxSecondsPerDot
                            let progress = min(1.0, max(0.0, dotElapsedSec / targetSpan))

                            ZStack {
                                // Outer glowing halo ring
                                Circle()
                                    .stroke(NeuroTheme.teal.opacity(0.22), lineWidth: 1.5)
                                    .frame(width: 72, height: 72)
                                    .scaleEffect(isSamplingWindow ? 0.92 : 1.08)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isSamplingWindow)

                                // Middle halo ring
                                Circle()
                                    .stroke(NeuroTheme.teal.opacity(0.38), lineWidth: 1.5)
                                    .frame(width: 58, height: 58)

                                // Progress ring
                                Circle()
                                    .stroke(NeuroTheme.border, lineWidth: 3)
                                    .frame(width: 46, height: 46)

                                Circle()
                                    .trim(from: 0.0, to: progress)
                                    .stroke(
                                        isSamplingWindow ? NeuroTheme.teal : NeuroTheme.amber,
                                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 46, height: 46)

                                // Glowing core dot
                                Circle()
                                    .fill(NeuroTheme.teal)
                                    .frame(width: 18, height: 18)
                                    .shadow(color: NeuroTheme.teal, radius: 10)

                                Circle()
                                    .fill(NeuroTheme.background)
                                    .frame(width: 5, height: 5)
                            }
                            .offset(x: activeOffsetPt)
                            .animation(.spring(duration: 0.28, bounce: 0.25), value: currentDotIndex)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)

                        HStack(spacing: 8) {
                            Text("DOT \(currentDotIndex + 1) OF 5")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.teal)
                            Text("·")
                                .foregroundStyle(NeuroTheme.textSecondary)
                            Text(
                                liveRunningFitDeg != nil
                                ? String(format: "fit %.2f° · limit 1.5°", liveRunningFitDeg!)
                                : String(format: "%.1fs elapsed", dotElapsedSec)
                            )
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        }
                    }
                } else if let model = fittedModel, model.isAccepted {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(NeuroTheme.teal)
                            Text(String(format: "fit %.2f° · limit 1.5°", model.rmsErrorDeg))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(NeuroTheme.teal)
                        }

                        HStack(spacing: 20) {
                            VStack(spacing: 4) {
                                Text("RMS ERROR")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Text(String(format: "%.2f°", model.rmsErrorDeg))
                                    .font(.system(.headline, design: .rounded).weight(.heavy))
                                    .foregroundStyle(NeuroTheme.teal)
                                Text("limit ≤ 1.50°")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }

                            VStack(spacing: 4) {
                                Text("DISTANCE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Text(String(format: "%.1f cm", model.meanDistanceCm))
                                    .font(.system(.headline, design: .rounded).weight(.heavy))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("25–40 cm")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }

                            VStack(spacing: 4) {
                                Text("DURATION")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Text(String(format: "%.1fs", model.totalCalibrationDurationSec))
                                    .font(.system(.headline, design: .rounded).weight(.heavy))
                                    .foregroundStyle(NeuroTheme.teal)
                                Text(protocolMode == .adaptiveFast ? "Adaptive" : "Fixed 10s")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        CalibrationFitChart(model: model)
                    }
                    .padding(.horizontal, 22)
                } else if let failureMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(NeuroTheme.amber)

                        Text(failureMessage)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(NeuroTheme.amber)
                            .multilineTextAlignment(.center)

                        if let model = fittedModel {
                            Text(String(format: "fit %.2f° · limit 1.5°", model.rmsErrorDeg))
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.amber)

                            CalibrationFitChart(model: model)
                        }

                        Text("No calibration, no degrees: NeuroAssist never reports angular velocity without a verified ≤ 1.5° fit.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(NeuroTheme.amber.opacity(0.6), lineWidth: 1)
                    )
                    .padding(.horizontal, 22)
                } else {
                    VStack(spacing: 14) {
                        SawtoothSignatureView(height: 24, cycles: 3)
                            .frame(width: 90)
                        Text("5-Spot Gaze Calibration")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(NeuroTheme.textPrimary)
                        Text(
                            protocolMode == .adaptiveFast
                            ? "A glowing teal dot with halo rings will jump to 5 horizontal spots with a haptic tick per dot. Locks automatically once fixation is stable."
                            : "A glowing teal dot with halo rings will jump to 5 horizontal spots for 2.0 s each. Keep your head still and follow with your eyes."
                        )
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if let model = fittedModel, model.isAccepted {
                        Button {
                            NeuroHaptics.selection()
                            onCalibrationAccepted(model)
                        } label: {
                            HStack {
                                Text("Continue to 10s Stripes Test")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .background(NeuroTheme.teal)
                            .foregroundStyle(NeuroTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: NeuroTheme.teal.opacity(0.5), radius: 12, y: 4)
                        }

                        Button {
                            runCalibrationSequence(usableHalfWidthPt: usableHalfWidthPt)
                        } label: {
                            Text("Recalibrate")
                                .font(.system(.subheadline, design: .default).weight(.medium))
                                .foregroundStyle(NeuroTheme.textSecondary)
                                .padding(.vertical, 6)
                        }
                    } else if !isRunningDots {
                        Button {
                            runCalibrationSequence(usableHalfWidthPt: usableHalfWidthPt)
                        } label: {
                            HStack {
                                Text(
                                    failureMessage == nil
                                    ? "Start 5-Spot Calibration"
                                    : "Retry Calibration"
                                )
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                Spacer()
                                Image(systemName: "scope")
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .background(distanceInRange ? NeuroTheme.teal : NeuroTheme.border)
                            .foregroundStyle(distanceInRange ? NeuroTheme.background : NeuroTheme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!distanceInRange)
                    }
                }
                .padding(.horizontal, 22)

                Text(NeuroTheme.researchFooter)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .padding(.bottom, 12)
            }
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .onDisappear {
            calibrationTask?.cancel()
        }
    }

    private func runCalibrationSequence(usableHalfWidthPt: CGFloat) {
        calibrationTask?.cancel()
        fittedModel = nil
        failureMessage = nil
        liveRunningFitDeg = nil
        currentDotIndex = 0
        dotElapsedSec = 0.0
        isRunningDots = true
        NeuroHaptics.impact(.medium)

        calibrationTask = Task { @MainActor in
            var collectedPoints: [CalibrationPointSample] = []

            for i in 0..<dotFractions.count {
                if Task.isCancelled { return }
                currentDotIndex = i
                dotElapsedSec = 0.0
                // Haptic tick per dot jump
                NeuroHaptics.impact(.rigid)

                let offsetPt = CGFloat(dotFractions[i]) * usableHalfWidthPt
                let offsetCm = ScreenGeometry.pointsToCm(offsetPt)

                tracker.beginRecording()
                var earlySummary: CalibrationPointSample? = nil
                let maxTicks = 20 // 2.0s max per dot

                for tick in 1...maxTicks {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(100))
                    dotElapsedSec = Double(tick) * 0.1

                    let currentSamples = tracker.currentRecordingSnapshot()
                    let validWindow = currentSamples.filter { $0.isValid }
                    if validWindow.count >= 6, let madVal = SignalMath.mad(validWindow.map(\.rawYawDeg)) {
                        liveRunningFitDeg = 1.4826 * madVal
                    }

                    if protocolMode == .adaptiveFast && dotElapsedSec >= SignalMath.adaptiveDotMinDurationSec {
                        if let startT = currentSamples.first?.timestamp,
                           let candidate = SignalMath.evaluateAdaptiveCalibrationDot(
                               samples: currentSamples,
                               dotStartTime: startT,
                               targetOffsetCm: offsetCm
                           ) {
                            earlySummary = candidate
                            break
                        }
                    }
                }

                let dotSamples = tracker.finishRecording()
                if Task.isCancelled { return }

                if let earlySummary {
                    collectedPoints.append(earlySummary)
                } else if let startT = dotSamples.first?.timestamp,
                          let summary = SignalMath.summarizeCalibrationDot(
                              samples: dotSamples,
                              dotStartTime: startT,
                              targetOffsetCm: offsetCm
                          ) {
                    collectedPoints.append(summary)
                }

                // Update running linear fit RMS once >= 3 dots are collected
                if collectedPoints.count >= 3,
                   let partialFit = SignalMath.fitLine(
                       x: collectedPoints.map(\.medianMeasuredYawDeg),
                       y: collectedPoints.map(\.trueAngleDeg)
                   ) {
                    liveRunningFitDeg = partialFit.rms
                }
            }

            isRunningDots = false

            guard collectedPoints.count == 5,
                  let model = SignalMath.fitCalibration(points: collectedPoints) else {
                fittedModel = nil
                failureMessage = "Calibration failed: keep your head still and look at each dot"
                NeuroHaptics.notify(.warning)
                return
            }

            fittedModel = model
            liveRunningFitDeg = model.rmsErrorDeg
            if model.isAccepted {
                NeuroHaptics.notify(.success)
                // In Stage Mode, automatically advance after brief visual confirmation
                if store.stageModeEnabled {
                    try? await Task.sleep(for: .milliseconds(550))
                    if !Task.isCancelled {
                        onCalibrationAccepted(model)
                    }
                }
            } else {
                failureMessage = "Calibration failed: keep your head still and look at each dot"
                NeuroHaptics.notify(.warning)
            }
        }
    }
}

private struct CalibrationFitChart: View {
    let model: CalibrationModel

    var body: some View {
        let minX = (model.points.map(\.medianMeasuredYawDeg).min() ?? -10.0) - 1.0
        let maxX = (model.points.map(\.medianMeasuredYawDeg).max() ?? 10.0) + 1.0

        VStack(alignment: .leading, spacing: 6) {
            Text("5-DOT LINEAR FIT (MEASURED YAW → TRUE VISUAL ANGLE)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)

            Chart {
                LineMark(
                    x: .value("Measured Yaw (°)", minX),
                    y: .value("True Angle (°)", model.calibrate(rawYawDeg: minX))
                )
                .foregroundStyle((model.isAccepted ? NeuroTheme.teal : NeuroTheme.amber).opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 2))

                LineMark(
                    x: .value("Measured Yaw (°)", maxX),
                    y: .value("True Angle (°)", model.calibrate(rawYawDeg: maxX))
                )
                .foregroundStyle((model.isAccepted ? NeuroTheme.teal : NeuroTheme.amber).opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 2))

                ForEach(Array(model.points.enumerated()), id: \.offset) { _, pt in
                    PointMark(
                        x: .value("Measured Yaw (°)", pt.medianMeasuredYawDeg),
                        y: .value("True Angle (°)", pt.trueAngleDeg)
                    )
                    .symbolSize(48)
                    .foregroundStyle(model.isAccepted ? NeuroTheme.teal : NeuroTheme.amber)
                }
            }
            .frame(height: 115)
        }
        .padding(14)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NeuroTheme.border, lineWidth: 1)
        )
    }
}
