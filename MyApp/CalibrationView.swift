import SwiftUI
import Charts

/// Rebuilt Calibration Flow satisfying the 6 Critical UX Rebuild Principles:
/// - State A: Automatic Position Guide with 0.75s steady hold auto-advance
/// - State B: Stationary 5-Point Sequence with 380ms smooth glides, 300ms settling, and zero motion sampling
/// - State C: Intelligent pause on tracking loss / head motion + isolated target retry preserving collected dots
/// - State D: Clear scientific verification outcome with 1.5° threshold enforcement
/// - Clean Visual Hierarchy: Hides raw engineering telemetry from primary screen behind a Diagnostics Sheet
struct CalibrationView: View {
    let tracker: FaceEyeTracker
    let store: DemoExperienceStore
    let protocolMode: MeasurementProtocolMode
    let onBack: () -> Void
    let onCalibrationAccepted: (CalibrationModel) -> Void

    // 5 horizontal fractions of usable screen half-width:
    // Center (0.0) -> Mid-Left (-0.5) -> Far-Left (-0.9) -> Mid-Right (+0.5) -> Far-Right (+0.9)
    // Starting at Center (0.0) means zero eye movement required when transitioning from positioning!
    private let dotFractions: [Double] = [0.0, -0.5, -0.9, 0.5, 0.9]

    enum FlowStep: Equatable {
        case positioning
        case calibrating(targetIndex: Int)
        case verified(model: CalibrationModel)
        case failed(reason: String, model: CalibrationModel?)
    }

    enum TargetPhase: Equatable {
        case moving
        case settling
        case sampling(progress: Double)
        case paused(reason: String)
    }

    @State private var flowStep: FlowStep = .positioning
    @State private var targetPhase: TargetPhase = .moving
    @State private var targetOffsetPt: CGFloat = 0.0
    @State private var currentDotIndex: Int = 0
    @State private var collectedPoints: [CalibrationPointSample] = []
    @State private var targetAttemptCount: Int = 0
    @State private var liveRunningRMS: Double? = nil
    @State private var showDiagnosticsSheet: Bool = false

    // State A: Positioning Readiness Tracking
    @State private var positionHoldProgress: Double = 0.0
    @State private var positionMonitorTask: Task<Void, Never>? = nil
    @State private var calibrationSequenceTask: Task<Void, Never>? = nil

    private var isDistanceAcceptable: Bool {
        tracker.faceTracked && (25.0...40.0).contains(tracker.distanceCm)
    }

    private var isPositioningReady: Bool {
        tracker.faceTracked &&
        isDistanceAcceptable &&
        tracker.isHeadSteady &&
        !tracker.isBlink
    }

    private var positioningInstruction: String {
        if !tracker.faceTracked {
            return "Center your face in view"
        } else if tracker.distanceCm < 25.0 {
            return "Move your phone slightly farther away"
        } else if tracker.distanceCm > 40.0 {
            return "Move your phone slightly closer"
        } else if !tracker.isHeadSteady {
            return "Keep your head still"
        } else if tracker.isBlink {
            return "Keep eyes open and look at the screen"
        } else {
            return "Perfect. Hold this position."
        }
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalMargin: CGFloat = 36.0
            let usableHalfWidthPt = max(60.0, (geo.size.width - horizontalMargin * 2.0) / 2.0)

            ZStack {
                NeuroTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Navigation Header
                    headerBar

                    Spacer()

                    // Main Interactive Content Area
                    switch flowStep {
                    case .positioning:
                        positioningView(usableHalfWidthPt: usableHalfWidthPt)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))

                    case .calibrating(let targetIdx):
                        calibrationArenaView(
                            targetIdx: targetIdx,
                            usableHalfWidthPt: usableHalfWidthPt
                        )
                        .transition(.opacity)

                    case .verified(let model):
                        verificationSuccessView(model: model, usableHalfWidthPt: usableHalfWidthPt)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))

                    case .failed(let reason, let model):
                        verificationFailureView(reason: reason, model: model, usableHalfWidthPt: usableHalfWidthPt)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    Spacer()

                    // Bottom Action Area
                    bottomActionBar(usableHalfWidthPt: usableHalfWidthPt)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 16)
                }
            }
            .onAppear {
                startPositioningMonitor(usableHalfWidthPt: usableHalfWidthPt)
            }
            .onDisappear {
                cancelAllTasks()
            }
            .sheet(isPresented: $showDiagnosticsSheet) {
                EngineeringDiagnosticsSheet(
                    tracker: tracker,
                    collectedPoints: collectedPoints,
                    fittedModel: verifiedModel,
                    protocolMode: protocolMode
                )
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                cancelAllTasks()
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

            // Optional Engineering Diagnostics Button
            Button {
                showDiagnosticsSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                    Text("Diagnostics")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeuroTheme.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NeuroTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(NeuroTheme.teal.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    // MARK: - State A: Positioning Guide View

    private func positioningView(usableHalfWidthPt: CGFloat) -> some View {
        VStack(spacing: 24) {
            // Calm Face Guide Oval
            ZStack {
                // Ambient pulsating ring when ready
                if isPositioningReady {
                    RoundedRectangle(cornerRadius: 85)
                        .stroke(NeuroTheme.teal.opacity(0.25), lineWidth: 3)
                        .frame(width: 176, height: 236)
                        .scaleEffect(1.04)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPositioningReady)
                }

                // Main Face Oval Guide
                RoundedRectangle(cornerRadius: 80)
                    .stroke(
                        isPositioningReady ? NeuroTheme.teal : NeuroTheme.border,
                        lineWidth: isPositioningReady ? 3.0 : 1.5
                    )
                    .frame(width: 160, height: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 80)
                            .fill(NeuroTheme.surface.opacity(0.5))
                    )

                // Face Lock & Iris Center Indicator
                if tracker.faceTracked {
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            Circle()
                                .stroke(isPositioningReady ? NeuroTheme.teal : NeuroTheme.amber, lineWidth: 2)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .fill(isPositioningReady ? NeuroTheme.teal : NeuroTheme.amber)
                                        .frame(width: 6, height: 6)
                                )
                                .offset(x: tracker.leftIrisNormalized.x * 20.0, y: tracker.leftIrisNormalized.y * 20.0)

                            Circle()
                                .stroke(isPositioningReady ? NeuroTheme.teal : NeuroTheme.amber, lineWidth: 2)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .fill(isPositioningReady ? NeuroTheme.teal : NeuroTheme.amber)
                                        .frame(width: 6, height: 6)
                                )
                                .offset(x: tracker.rightIrisNormalized.x * 20.0, y: tracker.rightIrisNormalized.y * 20.0)
                        }

                        // Subtle Nose Bridge Line
                        RoundedRectangle(cornerRadius: 2)
                            .fill(NeuroTheme.textSecondary.opacity(0.3))
                            .frame(width: 3, height: 20)
                    }
                } else {
                    Image(systemName: "faceid")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(NeuroTheme.textSecondary.opacity(0.6))
                }

                // Automatic Hold Countdown Ring around the guide
                if isPositioningReady && positionHoldProgress > 0.05 {
                    RoundedRectangle(cornerRadius: 80)
                        .trim(from: 0.0, to: positionHoldProgress)
                        .stroke(
                            NeuroTheme.teal,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 160, height: 220)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(height: 240)

            // Primary Guidance Banner
            VStack(spacing: 8) {
                Text(positioningInstruction)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPositioningReady ? NeuroTheme.teal : NeuroTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(
                    isPositioningReady
                    ? "Starting calibration automatically…"
                    : "Hold the device at eye level, 25–40 cm from your face."
                )
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - State B & C: Calibration Arena View

    private func calibrationArenaView(targetIdx: Int, usableHalfWidthPt: CGFloat) -> some View {
        VStack(spacing: 28) {
            // Minimal 5-Dot Progress Indicator
            HStack(spacing: 8) {
                ForEach(0..<dotFractions.count, id: \.self) { idx in
                    HStack(spacing: 0) {
                        if idx < collectedPoints.count {
                            Circle()
                                .fill(NeuroTheme.teal)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(NeuroTheme.background)
                                )
                        } else if idx == currentDotIndex {
                            Circle()
                                .stroke(NeuroTheme.teal, lineWidth: 2)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .fill(NeuroTheme.teal)
                                        .frame(width: 6, height: 6)
                                )
                        } else {
                            Circle()
                                .fill(NeuroTheme.border.opacity(0.6))
                                .frame(width: 8, height: 8)
                        }
                    }
                    if idx < dotFractions.count - 1 {
                        Rectangle()
                            .fill(idx < collectedPoints.count ? NeuroTheme.teal.opacity(0.6) : NeuroTheme.border.opacity(0.3))
                            .frame(width: 18, height: 2)
                    }
                }
            }
            .padding(.top, 8)

            // Step Label
            Text("TARGET \(targetIdx + 1) OF 5")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.teal)

            // Calibration Target Arena
            ZStack {
                // Subtle horizontal track line
                Rectangle()
                    .fill(NeuroTheme.border.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 36)

                // Subtle anchor ticks for the 5 points
                ForEach(0..<dotFractions.count, id: \.self) { idx in
                    Circle()
                        .fill(idx <= collectedPoints.count ? NeuroTheme.teal.opacity(0.3) : NeuroTheme.border.opacity(0.4))
                        .frame(width: 4, height: 4)
                        .offset(x: CGFloat(dotFractions[idx]) * usableHalfWidthPt)
                }

                // Stationary Bullseye Fixation Target
                ZStack {
                    // Outer Soft Halo
                    Circle()
                        .stroke(
                            targetHaloColor.opacity(0.25),
                            lineWidth: 2
                        )
                        .frame(width: 48, height: 48)

                    // Sampling Progress Arc
                    if case .sampling(let prog) = targetPhase {
                        Circle()
                            .trim(from: 0.0, to: prog)
                            .stroke(
                                NeuroTheme.teal,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 38, height: 38)
                    }

                    // Middle Bullseye Ring
                    Circle()
                        .stroke(targetHaloColor, lineWidth: 2.5)
                        .frame(width: 28, height: 28)

                    // Central Precision Fixation Dot (6 pt micro-dot: unambiguous focal center)
                    Circle()
                        .fill(targetCenterColor)
                        .frame(width: 8, height: 8)
                }
                .offset(x: targetOffsetPt)
            }
            .frame(maxWidth: .infinity, minHeight: 180)

            // Contextual Status Feedback Banner
            VStack(spacing: 6) {
                switch targetPhase {
                case .moving:
                    Text("Moving to target…")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.textSecondary)

                case .settling:
                    Text("Fixate on the center dot")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.teal)

                case .sampling:
                    Text("Hold gaze steady on the dot")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.teal)

                case .paused(let reason):
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(NeuroTheme.amber)
                        Text(reason)
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(NeuroTheme.amber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(NeuroTheme.surface)
                    .clipShape(Capsule())
                }

                if let rms = liveRunningRMS {
                    Text(String(format: "Running fit: %.2f° (limit ≤ 1.50°)", rms))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(rms <= 1.5 ? NeuroTheme.teal.opacity(0.8) : NeuroTheme.amber)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var targetHaloColor: Color {
        switch targetPhase {
        case .moving: return NeuroTheme.textSecondary.opacity(0.5)
        case .settling: return NeuroTheme.teal.opacity(0.6)
        case .sampling: return NeuroTheme.teal
        case .paused: return NeuroTheme.amber
        }
    }

    private var targetCenterColor: Color {
        switch targetPhase {
        case .moving: return NeuroTheme.textSecondary
        case .settling: return NeuroTheme.teal
        case .sampling: return NeuroTheme.teal
        case .paused: return NeuroTheme.amber
        }
    }

    // MARK: - State D: Verification Success View

    private func verificationSuccessView(model: CalibrationModel, usableHalfWidthPt: CGFloat) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(NeuroTheme.teal)

            Text("Calibration Verified")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(NeuroTheme.textPrimary)

            Text("Measurement pipeline calibrated to true visual angle.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)

            // Metrics Summary Row
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("RMS ERROR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    Text(String(format: "%.2f°", model.rmsErrorDeg))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(NeuroTheme.teal)
                    Text("limit ≤ 1.50°")
                        .font(.system(size: 10, design: .monospaced))
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
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }

                VStack(spacing: 4) {
                    Text("PACING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    Text(String(format: "%.1fs", model.totalCalibrationDurationSec))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(NeuroTheme.teal)
                    Text(protocolMode == .adaptiveFast ? "Adaptive" : "Fixed 10s")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(NeuroTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 22)

            CalibrationFitChart(model: model)
                .padding(.horizontal, 22)
        }
    }

    // MARK: - State D: Verification Failure View

    private func verificationFailureView(reason: String, model: CalibrationModel?, usableHalfWidthPt: CGFloat) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 42))
                .foregroundStyle(NeuroTheme.amber)

            Text("Calibration Inconclusive")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(NeuroTheme.amber)

            Text(reason)
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            if let model {
                Text(String(format: "Fit RMS: %.2f° · Scientific Threshold: ≤ 1.50°", model.rmsErrorDeg))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.amber)

                CalibrationFitChart(model: model)
                    .padding(.horizontal, 22)
            }

            Text("NeuroAssist strictly adheres to scientific integrity: we never display angular gain without an empirical ≤ 1.5° calibration.")
                .font(.system(size: 11, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Bottom Action Bar

    private func bottomActionBar(usableHalfWidthPt: CGFloat) -> some View {
        VStack(spacing: 12) {
            switch flowStep {
            case .positioning:
                Button {
                    NeuroHaptics.impact(.medium)
                    startCalibrationSequence(usableHalfWidthPt: usableHalfWidthPt)
                } label: {
                    HStack {
                        Text(isPositioningReady ? "Start Calibration Now" : "Position Your Face to Begin")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        Spacer()
                        Image(systemName: isPositioningReady ? "arrow.right" : "scope")
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(isPositioningReady ? NeuroTheme.teal : NeuroTheme.border)
                    .foregroundStyle(isPositioningReady ? NeuroTheme.background : NeuroTheme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!isPositioningReady)

            case .calibrating:
                EmptyView()

            case .verified(let model):
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
                    .padding(.vertical, 16)
                    .background(NeuroTheme.teal)
                    .foregroundStyle(NeuroTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: NeuroTheme.teal.opacity(0.4), radius: 10, y: 4)
                }

                Button {
                    cancelAllTasks()
                    flowStep = .positioning
                    startPositioningMonitor(usableHalfWidthPt: usableHalfWidthPt)
                } label: {
                    Text("Recalibrate")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .padding(.vertical, 4)
                }

            case .failed:
                Button {
                    cancelAllTasks()
                    flowStep = .positioning
                    startPositioningMonitor(usableHalfWidthPt: usableHalfWidthPt)
                } label: {
                    HStack {
                        Text("Retry Calibration")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(NeuroTheme.teal)
                    .foregroundStyle(NeuroTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Calibration Logic & State Transitions

    private func startPositioningMonitor(usableHalfWidthPt: CGFloat) {
        positionMonitorTask?.cancel()
        positionHoldProgress = 0.0
        positionMonitorTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard flowStep == .positioning else { break }

                if isPositioningReady {
                    positionHoldProgress = min(1.0, positionHoldProgress + (0.05 / 0.75))
                    if positionHoldProgress >= 1.0 {
                        NeuroHaptics.impact(.medium)
                        startCalibrationSequence(usableHalfWidthPt: usableHalfWidthPt)
                        break
                    }
                } else {
                    positionHoldProgress = max(0.0, positionHoldProgress - 0.15)
                }
            }
        }
    }

    private func startCalibrationSequence(usableHalfWidthPt: CGFloat) {
        positionMonitorTask?.cancel()
        calibrationSequenceTask?.cancel()
        collectedPoints.removeAll()
        liveRunningRMS = nil
        currentDotIndex = 0
        targetOffsetPt = 0.0

        flowStep = .calibrating(targetIndex: 0)

        calibrationSequenceTask = Task { @MainActor in
            for i in 0..<dotFractions.count {
                if Task.isCancelled { return }
                currentDotIndex = i
                flowStep = .calibrating(targetIndex: i)
                targetAttemptCount = 0

                let targetX = CGFloat(dotFractions[i]) * usableHalfWidthPt
                let offsetCm = ScreenGeometry.pointsToCm(targetX)

                var pointSuccess = false

                while !pointSuccess && targetAttemptCount < 2 {
                    if Task.isCancelled { return }

                    // 1. Move smoothly to next position (Strictly ZERO sampling during motion)
                    targetPhase = .moving
                    withAnimation(.easeInOut(duration: 0.38)) {
                        targetOffsetPt = targetX
                    }
                    try? await Task.sleep(for: .milliseconds(380))
                    if Task.isCancelled { return }

                    // 2. Gaze settling window (Strictly ZERO sampling during settling)
                    targetPhase = .settling
                    NeuroHaptics.impact(.light)
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }

                    // 3. Stationary sampling window
                    targetPhase = .sampling(progress: 0.0)
                    tracker.beginRecording()
                    let stationaryStartTime = CFAbsoluteTimeGetCurrent()

                    var stationaryElapsedSec: Double = 0.0
                    var acquiredSample: CalibrationPointSample? = nil
                    let maxStationaryDwellSec: Double = 3.5

                    while stationaryElapsedSec < maxStationaryDwellSec {
                        if Task.isCancelled { return }
                        try? await Task.sleep(for: .milliseconds(50))

                        // Intelligent pause check:
                        if !tracker.faceTracked {
                            targetPhase = .paused(reason: "Face lost — center face in frame")
                            continue
                        } else if !isDistanceAcceptable {
                            let hint = tracker.distanceCm < 25.0 ? "Move phone slightly farther away" : "Move phone slightly closer"
                            targetPhase = .paused(reason: hint)
                            continue
                        } else if !tracker.isHeadSteady {
                            targetPhase = .paused(reason: "Keep your head still")
                            continue
                        } else if tracker.isBlink {
                            targetPhase = .paused(reason: "Hold gaze steady on dot")
                            continue
                        }

                        // Steady state: accumulate time and evaluate
                        stationaryElapsedSec += 0.05
                        let targetSpan = protocolMode == .adaptiveFast ? SignalMath.adaptiveDotMinDurationSec : 1.2
                        let samplingProgress = min(1.0, stationaryElapsedSec / targetSpan)
                        targetPhase = .sampling(progress: samplingProgress)

                        let snapshot = tracker.currentRecordingSnapshot()

                        if protocolMode == .adaptiveFast && stationaryElapsedSec >= SignalMath.adaptiveDotMinDurationSec {
                            if let candidate = SignalMath.evaluateAdaptiveCalibrationDot(
                                samples: snapshot,
                                dotStartTime: stationaryStartTime,
                                targetOffsetCm: offsetCm
                            ) {
                                acquiredSample = candidate
                                break
                            }
                        } else if protocolMode == .researchFixed && stationaryElapsedSec >= 1.2 {
                            if let summary = SignalMath.summarizeCalibrationDot(
                                samples: snapshot,
                                dotStartTime: stationaryStartTime,
                                targetOffsetCm: offsetCm
                            ) {
                                acquiredSample = summary
                                break
                            }
                        }
                    }

                    _ = tracker.finishRecording()
                    if Task.isCancelled { return }

                    if let sample = acquiredSample {
                        pointSuccess = true
                        collectedPoints.append(sample)
                        NeuroHaptics.selection()

                        // Update running linear fit RMS once >= 3 points
                        if collectedPoints.count >= 3,
                           let partialFit = SignalMath.fitLine(
                               x: collectedPoints.map(\.medianMeasuredYawDeg),
                               y: collectedPoints.map(\.trueAngleDeg)
                           ) {
                            liveRunningRMS = partialFit.rms
                        }
                    } else {
                        targetAttemptCount += 1
                        if targetAttemptCount < 2 {
                            targetPhase = .paused(reason: "Let's steady your gaze on this target")
                            try? await Task.sleep(for: .milliseconds(400))
                        }
                    }
                }

                // If point failed after 2 full attempts
                if !pointSuccess {
                    flowStep = .failed(
                        reason: "Fixation was interrupted at Target \(i + 1). Keep your head still and follow each dot.",
                        model: nil
                    )
                    NeuroHaptics.notify(.warning)
                    return
                }
            }

            // 4. Verify Final Calibration Fit
            guard collectedPoints.count == dotFractions.count,
                  let model = SignalMath.fitCalibration(points: collectedPoints) else {
                flowStep = .failed(
                    reason: "Calibration could not be fitted with sufficient points.",
                    model: nil
                )
                NeuroHaptics.notify(.warning)
                return
            }

            liveRunningRMS = model.rmsErrorDeg

            if model.isAccepted {
                flowStep = .verified(model: model)
                NeuroHaptics.notify(.success)
                if store.stageModeEnabled {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled {
                        onCalibrationAccepted(model)
                    }
                }
            } else {
                flowStep = .failed(
                    reason: String(format: "Residual fit error (%.2f°) exceeded the 1.50° threshold. Keep your head still and look directly at each dot.", model.rmsErrorDeg),
                    model: model
                )
                NeuroHaptics.notify(.warning)
            }
        }
    }

    private func cancelAllTasks() {
        positionMonitorTask?.cancel()
        calibrationSequenceTask?.cancel()
        positionMonitorTask = nil
        calibrationSequenceTask = nil
    }

    private var verifiedModel: CalibrationModel? {
        if case .verified(let model) = flowStep {
            return model
        }
        return nil
    }
}

// MARK: - Calibration Fit Chart

struct CalibrationFitChart: View {
    let model: CalibrationModel

    var body: some View {
        let minX = (model.points.map(\.medianMeasuredYawDeg).min() ?? -10.0) - 1.0
        let maxX = (model.points.map(\.medianMeasuredYawDeg).max() ?? 10.0) + 1.0

        VStack(alignment: .leading, spacing: 6) {
            Text("5-POINT LINEAR FIT (MEASURED YAW → VISUAL ANGLE)")
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
            .frame(height: 110)
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

// MARK: - Engineering Diagnostics Sheet

struct EngineeringDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tracker: FaceEyeTracker
    let collectedPoints: [CalibrationPointSample]
    let fittedModel: CalibrationModel?
    let protocolMode: MeasurementProtocolMode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Cadence & Sensor Telemetry Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CADENCE & SENSOR TELEMETRY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        HStack(spacing: 12) {
                            HUDMetric(label: "FPS", value: String(format: "%.0f", tracker.fps), isGood: tracker.fps >= 50)
                            HUDMetric(label: "DROPS", value: "\(tracker.droppedFrameCount)", isGood: tracker.droppedFrameCount == 0)
                            HUDMetric(label: "VALID", value: String(format: "%.0f%%", tracker.validSamplePercentage), isGood: tracker.validSamplePercentage >= 85.0)
                            HUDMetric(label: "TRACK", value: tracker.faceTracked ? "LOCKED" : "LOST", isGood: tracker.faceTracked)
                        }

                        HStack(spacing: 12) {
                            HUDMetric(label: "PROC", value: String(format: "%.1fms", tracker.signalProcessingLatencyMs), isGood: tracker.signalProcessingLatencyMs < 5.0)
                            HUDMetric(label: "UI", value: String(format: "%.1fms", tracker.renderLatencyMs), isGood: tracker.renderLatencyMs < 8.0)
                            HUDMetric(label: "LUX", value: String(format: "%.0f", tracker.ambientLightLux), isGood: tracker.ambientLightLux > 100)
                            HUDMetric(label: "HEAD", value: tracker.isHeadSteady ? "STEADY" : "MOVE", isGood: tracker.isHeadSteady)
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Frame Validity Rejection Breakdown Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FRAME REJECTION INSTRUMENTATION")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        if let primary = tracker.primaryRejectionReason {
                            HStack {
                                Text("Primary Drop Cause:")
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Spacer()
                                Text(primary)
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundStyle(NeuroTheme.amber)
                            }
                        }

                        ForEach(EyeSample.FrameValidityReason.allCases, id: \.self) { reason in
                            let count = tracker.rejectionReasonCounts[reason] ?? 0
                            HStack {
                                Text(reason.humanDescription)
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Spacer()
                                Text("\(count) frames")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(reason == .valid ? NeuroTheme.teal : NeuroTheme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Calibration Points & Fit Parameters
                    if let model = fittedModel {
                        CalibrationFitChart(model: model)
                    }

                    // Mathematical Principles Disclosure
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SCIENTIFIC SPECIFICATIONS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        Text("• Acceptance Limit: RMS Residual ≤ 1.50°")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Text("• Gaze Sampling: Stationary collection only (zero motion sampling)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Text("• Saccadic Settling Guard: 300 ms post-transition dwell")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Text("• Protocol Mode: \(protocolMode.rawValue)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Engineering Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
