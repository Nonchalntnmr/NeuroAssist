import SwiftUI
import Charts

struct StripesTestView: View {
    let tracker: FaceEyeTracker
    let store: DemoExperienceStore
    let calibration: CalibrationModel
    let protocolMode: MeasurementProtocolMode
    let onCancel: () -> Void
    let onCompleted: (OKNAnalysisResult, [EyeSample]) -> Void

    private let maxTestDurationSec: Double = 10.0
    private let stripePeriodDeg: Double = 2.0
    private let stripeVelocityDegPerSec: Double = 10.0

    @State private var isPresentingStripes: Bool = false
    @State private var startTimestamp: Date? = nil
    @State private var elapsedSec: Double = 0.0
    @State private var liveSnapshot: OnlineOKNSnapshot? = nil
    @State private var expandSignalMicroscope: Bool = false
    @State private var testTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            NeuroTheme.background.ignoresSafeArea()

            if isPresentingStripes, let startDate = startTimestamp {
                // Full-screen smooth vertical black-and-white stripes moving right at 10 deg/s (zero flashing)
                TimelineView(.animation) { timeline in
                    let t = max(0.0, timeline.date.timeIntervalSince(startDate))
                    let periodPt = max(
                        12.0,
                        ScreenGeometry.degreesToPoints(
                            degrees: stripePeriodDeg,
                            distanceCm: calibration.meanDistanceCm
                        )
                    )
                    let halfPeriodPt = periodPt / 2.0
                    let speedPtPerSec = periodPt * (stripeVelocityDegPerSec / stripePeriodDeg)
                    let phaseOffsetPt = CGFloat(t) * speedPtPerSec

                    ZStack {
                        Canvas { context, size in
                            context.fill(
                                Path(CGRect(origin: .zero, size: size)),
                                with: .color(.black)
                            )

                            let wrappedShift = phaseOffsetPt.truncatingRemainder(dividingBy: periodPt)
                            var x = -periodPt + wrappedShift
                            while x < size.width + periodPt {
                                let rect = CGRect(x: x, y: 0, width: halfPeriodPt, height: size.height)
                                context.fill(Path(rect), with: .color(.white))
                                x += periodPt
                            }
                        }
                        .ignoresSafeArea()

                        // Center Countdown Ring so the subject fixates the middle while stripes drift past
                        let remaining = max(0.0, maxTestDurationSec - elapsedSec)
                        let ringProgress = min(1.0, max(0.0, elapsedSec / maxTestDurationSec))
                        ZStack {
                            Circle()
                                .fill(NeuroTheme.background.opacity(0.84))
                                .frame(width: 78, height: 78)

                            Circle()
                                .stroke(NeuroTheme.border, lineWidth: 4)
                                .frame(width: 68, height: 68)

                            Circle()
                                .trim(from: 0.0, to: ringProgress)
                                .stroke(
                                    NeuroTheme.teal,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 68, height: 68)

                            VStack(spacing: 1) {
                                Text(String(format: "%.1f", remaining))
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("SEC")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.teal)
                            }
                        }
                    }
                }

                // Top instruction pill + Bottom Live Signal Microscope
                VStack(spacing: 8) {
                    if store.showPerformanceHUD {
                        RealTimePerformanceHUD(tracker: tracker)
                    }

                    HStack(spacing: 10) {
                        Circle()
                            .fill((tracker.faceTracked && tracker.isHeadSteady) ? NeuroTheme.teal : NeuroTheme.amber)
                            .frame(width: 8, height: 8)
                        Text(liveSnapshot?.activeWarning ?? "Look at the center ring and let the stripes drift past.")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(liveSnapshot?.activeWarning != nil ? NeuroTheme.amber : NeuroTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            NeuroHaptics.selection()
                            withAnimation(.spring(duration: 0.3)) {
                                expandSignalMicroscope.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: expandSignalMicroscope ? "waveform.circle.fill" : "waveform.circle")
                                Text(expandSignalMicroscope ? "MICROSCOPE" : "MINI TRACE")
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NeuroTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(NeuroTheme.background.opacity(0.90))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(NeuroTheme.border, lineWidth: 1)
                    )

                    Spacer()

                    // A. LIVE SIGNAL MICROSCOPE / REAL-TIME SAWTOOTH DRAWER AT THE BOTTOM
                    LiveSignalMicroscopeOverlay(
                        snapshot: liveSnapshot,
                        expanded: expandSignalMicroscope
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else {
                // Pre-test readiness screen
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(action: onCancel) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Calibration")
                            }
                            .font(.system(.subheadline, design: .default).weight(.medium))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        }
                        Spacer()
                        Text("STEP 3 OF 3 · STRIPES TEST")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)
                    }

                    if store.showPerformanceHUD {
                        RealTimePerformanceHUD(tracker: tracker)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 14) {
                        SawtoothSignatureView(height: 24, cycles: 4)
                            .frame(width: 110)

                        Text("10-Second Optokinetic Stripes")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(NeuroTheme.textPrimary)

                        Text("Look at the center ring and let the stripes drift past.")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)

                        Text(
                            protocolMode == .adaptiveFast
                            ? "Smooth vertical stripes (2° period at \(String(format: "%.1f cm", calibration.meanDistanceCm))) move right at 10°/s. The live bottom trace draws your real calibrated eye signal in degrees and stops early once ≥ 8 clean windows reach ±1.0°/s precision."
                            : "Smooth vertical stripes (2° period at \(String(format: "%.1f cm", calibration.meanDistanceCm))) move right at 10°/s for 10.0 seconds. The live bottom trace draws your real calibrated eye signal in degrees."
                        )
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    .padding(22)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(NeuroTheme.border, lineWidth: 1)
                    )

                    Spacer()

                    Button(action: startStripesRun) {
                        HStack {
                            Text(protocolMode == .adaptiveFast ? "Start Adaptive Stripes Test" : "Start 10-Second Stripes Test")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(NeuroTheme.teal)
                        .foregroundStyle(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: NeuroTheme.teal.opacity(0.5), radius: 12, y: 4)
                    }

                    Text(NeuroTheme.researchFooter)
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(22)
                .onAppear {
                    if store.stageModeEnabled && !isPresentingStripes {
                        startStripesRun()
                    }
                }
            }
        }
        .statusBarHidden(isPresentingStripes)
        .onDisappear {
            testTask?.cancel()
        }
    }

    private func startStripesRun() {
        testTask?.cancel()
        NeuroHaptics.impact(.medium)
        let start = Date()
        startTimestamp = start
        elapsedSec = 0.0
        liveSnapshot = nil
        isPresentingStripes = true
        tracker.beginRecording()

        let cal = calibration
        let mode = protocolMode

        testTask = Task { @MainActor in
            var stoppedEarly = false
            let steps = 100 // 10.0 seconds max (100 x 100ms)

            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(100))
                elapsedSec = Double(step) * 0.1

                // Every 200ms, update the real-time live trace & online slow-phase estimator
                if step % 2 == 0 {
                    let snapshotSamples = tracker.currentRecordingSnapshot()
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let online = SignalMath.evaluateOnlineSnapshot(
                        samples: snapshotSamples,
                        calibration: cal,
                        mode: mode,
                        stripeDirectionSign: 1.0
                    )
                    let procMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                    tracker.updateProcessingLatencyMs(procMs)

                    if Task.isCancelled { return }
                    liveSnapshot = online

                    if online.canStopEarlyWithPrecision || online.shouldAbortEarlyForQuality {
                        stoppedEarly = true
                        break
                    }
                }
            }

            if Task.isCancelled { return }
            let samples = tracker.finishRecording()
            isPresentingStripes = false

            let result = SignalMath.analyzeOptokinetic(
                samples: samples,
                calibration: cal,
                stripeDirectionSign: 1.0,
                mode: mode,
                provenance: .liveCamera,
                stoppedEarly: stoppedEarly
            )

            if Task.isCancelled { return }
            NeuroHaptics.notify(result.didAbstain ? .warning : .success)
            onCompleted(result, samples)
        }
    }
}

// MARK: - A. LIVE SIGNAL MICROSCOPE (Real-Time Calibrated Eye Trace & Detected Slow-Phase Segments)

private struct LiveSignalMicroscopeOverlay: View {
    let snapshot: OnlineOKNSnapshot?
    let expanded: Bool

    var body: some View {
        let pts = snapshot?.recentTracePoints ?? []
        let windows = snapshot?.recentWindows ?? []
        let validPts = pts.filter(\.isValid)
        let fastPts = pts.filter { $0.isValid && $0.isFastPhase }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(expanded ? "LIVE SIGNAL MICROSCOPE (REAL-TIME CALIBRATED °)" : "LIVE EYE TRACE (CALIBRATED °)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.teal)

                Spacer()

                if let snap = snapshot {
                    Text("WINDOWS \(snap.cleanWindowCount)/8")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(snap.cleanWindowCount >= 8 ? NeuroTheme.teal : NeuroTheme.textSecondary)

                    if let medV = snap.currentMedianVelocityDegPerSec {
                        Text(String(format: "SPV %.1f °/s", medV))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }

                    if snap.trackingNoiseDeg.isFinite {
                        Text(String(format: "NOISE %.2f°", snap.trackingNoiseDeg))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(snap.trackingNoiseDeg <= 0.45 ? NeuroTheme.teal : NeuroTheme.amber)
                    }
                }
            }

            if validPts.isEmpty {
                HStack {
                    Text("Waiting for valid calibrated TrueDepth samples…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(NeuroTheme.amber)
                    Spacer()
                }
                .frame(height: expanded ? 140 : 68)
            } else {
                Chart {
                    // 1. Raw unsmoothed calibrated eye-position signal
                    ForEach(validPts) { pt in
                        LineMark(
                            x: .value("Time (s)", pt.timeSec),
                            y: .value("Angle (°)", pt.angleDeg),
                            series: .value("Signal", "Raw")
                        )
                        .foregroundStyle(expanded ? NeuroTheme.textSecondary.opacity(0.55) : NeuroTheme.teal)
                        .lineStyle(StrokeStyle(lineWidth: expanded ? 1.2 : 2.0))
                    }

                    if expanded {
                        // 2. Filtered eye-position signal (3-pt median)
                        ForEach(validPts) { pt in
                            LineMark(
                                x: .value("Time (s)", pt.timeSec),
                                y: .value("Angle (°)", pt.filteredAngleDeg),
                                series: .value("Signal", "Filtered")
                            )
                            .foregroundStyle(NeuroTheme.textPrimary.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }

                        // 3. Detected slow-phase OLS segments in bright Teal
                        ForEach(windows) { win in
                            LineMark(
                                x: .value("Time (s)", win.startTime),
                                y: .value("Angle (°)", win.fittedAngle(at: win.startTime)),
                                series: .value("SlowPhase", win.id.uuidString)
                            )
                            .foregroundStyle(NeuroTheme.teal)
                            .lineStyle(StrokeStyle(lineWidth: 3.0))

                            LineMark(
                                x: .value("Time (s)", win.endTime),
                                y: .value("Angle (°)", win.fittedAngle(at: win.endTime)),
                                series: .value("SlowPhase", win.id.uuidString)
                            )
                            .foregroundStyle(NeuroTheme.teal)
                            .lineStyle(StrokeStyle(lineWidth: 3.0))
                        }

                        // 4. Rejected fast phases & reset jumps in Amber
                        ForEach(fastPts) { pt in
                            PointMark(
                                x: .value("Time (s)", pt.timeSec),
                                y: .value("Angle (°)", pt.angleDeg)
                            )
                            .symbolSize(24)
                            .foregroundStyle(NeuroTheme.amber)
                        }
                    }
                }
                .chartYScale(domain: -12.0...12.0)
                .chartXAxis(expanded ? .automatic : .hidden)
                .chartYAxis {
                    AxisMarks(values: [-10, 0, 10]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(NeuroTheme.border)
                        AxisValueLabel {
                            if let deg = value.as(Double.self) {
                                Text("\(Int(deg))°")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: expanded ? 145 : 70)
            }

            if expanded {
                HStack(spacing: 12) {
                    LegendDot(color: NeuroTheme.textSecondary, label: "Raw (°)")
                    LegendDot(color: NeuroTheme.textPrimary, label: "Filtered (°)")
                    LegendDot(color: NeuroTheme.teal, label: "Slow-Phase Fit")
                    LegendDot(color: NeuroTheme.amber, label: "Rejected Fast Phase")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NeuroTheme.background.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NeuroTheme.border, lineWidth: 1)
        )
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
        }
    }
}
