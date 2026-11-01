import SwiftUI
import Charts

struct ResultView: View {
    let result: OKNAnalysisResult
    let calibration: CalibrationModel?
    let store: DemoExperienceStore
    let onRetakeTest: () -> Void
    let onRecalibrate: () -> Void
    let onDoneHome: () -> Void
    let onOpenPauseAndArriveSafe: () -> Void
    var bridge: CollectiveBridge? = nil
    var rawSamples: [EyeSample] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var csvURL: URL? = nil
    @State private var traceDrawProgress: Double = 0.0
    @State private var showNumberSlam: Bool = false
    @State private var animatedGain: Double = 0.0
    @State private var showAllQualityChecks: Bool = false
    @State private var showSignalToEvidence: Bool = true
    @State private var showWhatWeMeasured: Bool = false
    @State private var showWhatThisCannotEstablish: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top bar
                HStack {
                    HStack(spacing: 8) {
                        SawtoothSignatureView(height: 18, cycles: 3)
                            .frame(width: 40)
                        Text("RESULT · \(result.scientificStatus.rawValue)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(result.scientificStatus == .valid ? NeuroTheme.teal : NeuroTheme.amber)
                    }
                    Spacer()

                    if let csvURL {
                        ShareLink(item: csvURL) {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export CSV")
                            }
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(NeuroTheme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NeuroTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(NeuroTheme.border, lineWidth: 1)
                            )
                        }
                    }

                    Button("Home", action: onDoneHome)
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }

                // Persistent SIMULATED or RECORDED SESSION Watermark if not Live TrueDepth
                ProvenanceWatermarkBanner(provenance: result.provenance)

                if result.didAbstain {
                    abstainHeroCard
                } else {
                    measuredHeroRevealCard
                }

                // Recorded Calibrated Eye Trace (Draws itself across the screen on MEASURED)
                if let cal = calibration, cal.isAccepted, !result.tracePoints.isEmpty {
                    traceChartCard
                }

                // NeuroAssist × CI: independent multi-agent review of this recording
                if let bridge {
                    AgentCollectiveCard(
                        bridge: bridge,
                        result: result,
                        calibration: calibration,
                        samples: rawSamples
                    )
                }

                // B. SIGNAL-TO-EVIDENCE REVEAL (Interactive Evidence Breakdown)
                signalToEvidenceSection

                // Expandable Quality Gate Checklist ("11 of 11 checks passed" / Failed checks)
                qualityChecksSection

                // F. SCIENTIFIC INTERPRETABILITY ("What we measured" & "What this cannot establish")
                scientificInterpretabilitySection

                // Always-visible Emergency Stroke Warning Card on Pause/Abstain or expandable
                if result.didAbstain && store.consecutiveAbstainCount >= 2 {
                    Button(action: onOpenPauseAndArriveSafe) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("2 Consecutive Abstains — Open Pause & Arrive Safe")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(NeuroTheme.amber.opacity(0.2))
                        .foregroundStyle(NeuroTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.amber, lineWidth: 1.5))
                    }
                }

                // Bottom actions
                VStack(spacing: 10) {
                    Button {
                        NeuroHaptics.impact(.medium)
                        onRetakeTest()
                    } label: {
                        HStack {
                            Text(result.didAbstain ? "Retake with this fix" : "Repeat Stripes Test")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(result.didAbstain ? NeuroTheme.amber : NeuroTheme.teal)
                        .foregroundStyle(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: (result.didAbstain ? NeuroTheme.amber : NeuroTheme.teal).opacity(0.45), radius: 10, y: 4)
                    }

                    Button(action: onRecalibrate) {
                        HStack {
                            Text("Recalibrate 5 Dots")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                            Spacer()
                            Image(systemName: "scope")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(NeuroTheme.surface)
                        .foregroundStyle(NeuroTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(NeuroTheme.border, lineWidth: 1)
                        )
                    }
                }

                Text(NeuroTheme.researchFooter)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .task {
            csvURL = await ResearchCSVExporter.generateCSVAsync(result: result, calibration: calibration)
            triggerChoreography()
        }
    }

    private func triggerChoreography() {
        guard !result.didAbstain, let finalGain = result.gain else {
            traceDrawProgress = 1.0
            return
        }
        if reduceMotion {
            traceDrawProgress = 1.0
            showNumberSlam = true
            animatedGain = finalGain
            return
        }

        traceDrawProgress = 0.0
        showNumberSlam = false
        animatedGain = 0.0

        // Step 1: Eye trace draws itself across the screen in teal (0.7s)
        withAnimation(.easeInOut(duration: 0.75)) {
            traceDrawProgress = 1.0
        }

        // Step 2: Gain slams in huge with count-up + haptic
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            NeuroHaptics.impact(.heavy)
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                showNumberSlam = true
            }
            let steps = 16
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(22))
                animatedGain = finalGain * (Double(i) / Double(steps))
            }
            animatedGain = finalGain
            NeuroHaptics.notify(.success)
        }
    }

    // MARK: - 5. RESULT — MEASURED Hero Card (Choreographed Reveal)

    private var measuredHeroRevealCard: some View {
        let gainVal = result.gain ?? 0.0
        let speedVal = result.slowPhaseSpeedDegPerSec ?? 0.0
        let ci = result.confidenceInterval95 ?? (lower: 0.0, upper: 0.0)
        let band = store.usualGainRange
        let withinUsual = (band.lower...band.upper).contains(gainVal)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MEASURED · ALL \(result.checks.count) GATES PASSED", systemImage: "checkmark.seal.fill")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(NeuroTheme.teal)
                Spacer()
                Text(String(format: "%.1fs · %.1fms", result.recordingDurationSec, result.analysisLatencyMs))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }

            if showNumberSlam {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(format: "%.2f", animatedGain))
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(NeuroTheme.teal)
                        .contentTransition(.numericText(value: animatedGain))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OKN GAIN")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)
                        Text(String(format: "%.1f °/s slow-phase", speedVal))
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }
                }
                .transition(.scale(scale: 0.75).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    SawtoothSignatureView(height: 28, cycles: 4, animate: true)
                        .frame(width: 140)
                    Text("Tracing slow-phase evidence…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)
                }
                .padding(.vertical, 16)
            }

            // Physical Cadence & Nyquist Diagnostic Pill
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption2)
                    .foregroundStyle(NeuroTheme.teal)
                Text(String(format: "Hardware: 60 Hz TrueDepth · %.1f fps · Jitter: ±%.1f ms · Nyquist Limit: 30 Hz", result.cadenceDiagnostics.meanFps, result.cadenceDiagnostics.cadenceJitterMs))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(NeuroTheme.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 95% Interval underneath
            VStack(alignment: .leading, spacing: 4) {
                Text("95% BINOMIAL CONFIDENCE INTERVAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
                Text(
                    String(
                        format: "%.2f to %.2f gain  (%.1f to %.1f °/s, ±%.2f °/s across %d windows)",
                        ci.lower / 10.0,
                        ci.upper / 10.0,
                        ci.lower,
                        ci.upper,
                        result.intervalHalfWidthDegPerSec,
                        result.cleanWindowCount
                    )
                )
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(NeuroTheme.textPrimary)
            }

            // Personal Baseline comparison badge + Tap to expand checks pill
            HStack {
                Text(withinUsual ? "Within your usual range (\(String(format: "%.2f–%.2f", band.lower, band.upper)))" : "Change from your usual range (\(String(format: "%.2f–%.2f", band.lower, band.upper)))")
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundStyle(withinUsual ? NeuroTheme.teal : NeuroTheme.amber)

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showAllQualityChecks.toggle()
                    }
                } label: {
                    Text("\(result.passedCheckCount) of \(result.checks.count) checks passed ▾")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NeuroTheme.teal.opacity(0.65), lineWidth: 1.5)
        )
    }

    // MARK: - 6. RESULT — ABSTAIN Hero Card (Zero Numbers Shown, Deliberate & Confident)

    private var abstainHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(result.scientificStatus == .invalid ? "INVALID ACQUISITION — PROTOCOL FAILED" : "INCONCLUSIVE — INSUFFICIENT EVIDENCE", systemImage: result.scientificStatus == .invalid ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(NeuroTheme.amber)
                Spacer()
            }

            Text(result.scientificStatus == .invalid ? "INVALID" : "ABSTAIN")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(NeuroTheme.amber)

            if let rootCause = result.primaryRootCause {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(NeuroTheme.background)
                    Text("PRIMARY ROOT CAUSE: \(rootCause.rawValue)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.background)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NeuroTheme.amber)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("NeuroAssist refuses to guess or output a gain/velocity number when any quality gate fails. Fix the items below and retake:")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(NeuroTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(result.failedChecks) { failed in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(NeuroTheme.amber)
                            Text(failed.name)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(NeuroTheme.textPrimary)
                            Spacer()
                            Text("\(failed.valueString) (rule \(failed.ruleString))")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        Text(failed.fixHint)
                            .font(.system(.caption, design: .default).weight(.medium))
                            .foregroundStyle(NeuroTheme.amber)
                    }
                    .padding(12)
                    .background(NeuroTheme.background.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NeuroTheme.amber.opacity(0.85), lineWidth: 1.5)
        )
    }

    // MARK: - Animated Eye Trace Chart Card

    private var traceChartCard: some View {
        let maxTime = result.tracePoints.last?.timeSec ?? 10.0
        let visibleCutoff = maxTime * traceDrawProgress
        let validPts = result.tracePoints.filter { $0.isValid && $0.timeSec <= visibleCutoff }
        let visibleWindows = result.windows.filter { $0.endTime <= visibleCutoff + 0.1 }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CALIBRATED EYE TRACE (°) & FITTED SLOW PHASES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(NeuroTheme.textSecondary).frame(width: 6, height: 6)
                        Text("Raw (°)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(NeuroTheme.teal).frame(width: 6, height: 6)
                        Text("Slow phase")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                    }
                }
            }

            Chart {
                ForEach(validPts) { pt in
                    LineMark(
                        x: .value("Time (s)", pt.timeSec),
                        y: .value("Eye Angle (°)", pt.angleDeg),
                        series: .value("Type", "RawTrace")
                    )
                    .foregroundStyle(NeuroTheme.textSecondary.opacity(0.50))
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }

                ForEach(visibleWindows) { win in
                    LineMark(
                        x: .value("Time (s)", win.startTime),
                        y: .value("Eye Angle (°)", win.fittedAngle(at: win.startTime)),
                        series: .value("Window", win.id.uuidString)
                    )
                    .foregroundStyle(NeuroTheme.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.8))

                    LineMark(
                        x: .value("Time (s)", win.endTime),
                        y: .value("Eye Angle (°)", win.fittedAngle(at: win.endTime)),
                        series: .value("Window", win.id.uuidString)
                    )
                    .foregroundStyle(NeuroTheme.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.8))
                }
            }
            .chartXScale(domain: 0.0...max(4.5, maxTime))
            .frame(height: 185)
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NeuroTheme.border, lineWidth: 1)
        )
    }

    // MARK: - B. SIGNAL-TO-EVIDENCE REVEAL Section

    private var signalToEvidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    showSignalToEvidence.toggle()
                }
            } label: {
                HStack {
                    Text("SIGNAL-TO-EVIDENCE PIPELINE BREAKDOWN")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)
                    Spacer()
                    Image(systemName: showSignalToEvidence ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
            }

            if showSignalToEvidence {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    EvidenceCell(label: "TOTAL FRAMES", value: "\(result.totalFrames)")
                    EvidenceCell(label: "VALID FRAMES", value: "\(result.validFrames)")
                    EvidenceCell(label: "REJECTED", value: "\(result.rejectedFrames)")
                    EvidenceCell(label: "CLEAN WINDOWS", value: "\(result.cleanWindowCount)")
                    EvidenceCell(
                        label: "EST. SPV",
                        value: (!result.didAbstain && result.slowPhaseSpeedDegPerSec != nil)
                            ? String(format: "%.2f °/s", result.slowPhaseSpeedDegPerSec!)
                            : "ABSTAIN"
                    )
                    EvidenceCell(
                        label: "OKN GAIN",
                        value: (!result.didAbstain && result.gain != nil)
                            ? String(format: "%.2f", result.gain!)
                            : "ABSTAIN"
                    )
                    EvidenceCell(
                        label: "95% CI HALF",
                        value: (!result.didAbstain && result.intervalHalfWidthDegPerSec.isFinite)
                            ? String(format: "±%.2f °/s", result.intervalHalfWidthDegPerSec)
                            : "ABSTAIN"
                    )
                    EvidenceCell(
                        label: "CAL RMS",
                        value: result.calibrationRMSDeg.isFinite ? String(format: "%.2f°", result.calibrationRMSDeg) : "—"
                    )
                    EvidenceCell(
                        label: "NOISE (UNSM.)",
                        value: result.trackingNoiseDeg.isFinite ? String(format: "%.2f°", result.trackingNoiseDeg) : "—"
                    )
                }
            }
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
    }

    // MARK: - Quality Gate Checklist Section

    private var qualityChecksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    showAllQualityChecks.toggle()
                }
            } label: {
                HStack {
                    Text("QUALITY GATE · \(result.passedCheckCount) OF \(result.checks.count) CHECKS PASSED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(result.didAbstain ? NeuroTheme.amber : NeuroTheme.teal)
                    Spacer()
                    Text(showAllQualityChecks ? "Hide" : "Expand all")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
            }

            if showAllQualityChecks || result.didAbstain {
                ForEach(result.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.passed ? NeuroTheme.teal : NeuroTheme.amber)
                            .font(.system(size: 15))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                                .font(.system(.subheadline, design: .default).weight(.medium))
                                .foregroundStyle(NeuroTheme.textPrimary)

                            if !check.passed {
                                Text(check.fixHint)
                                    .font(.system(.caption2, design: .default))
                                    .foregroundStyle(NeuroTheme.amber)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(check.valueString)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(check.passed ? NeuroTheme.teal : NeuroTheme.amber)
                            Text("Rule: \(check.ruleString)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 5)

                    if check.id != result.checks.last?.id {
                        Divider().background(NeuroTheme.border)
                    }
                }
            }
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NeuroTheme.border, lineWidth: 1)
        )
    }

    // MARK: - F. SCIENTIFIC INTERPRETABILITY ("What we measured" & "What this cannot establish")

    private var scientificInterpretabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showWhatWeMeasured) {
                Text("NeuroAssist estimates horizontal **optokinetic slow-phase eye velocity (SPV)** in calibrated degrees per second (°/s) and **directional gain** (SPV ÷ 10 °/s stripe speed). A 5-point screen calibration maps ARKit TrueDepth eye-pose angles into physical visual angle at your measured viewing distance, strips quick resetting phases (> 40 °/s or retrograde reset jumps), fits ordinary least-squares lines to contiguous ≤ 0.5 s slow-phase segments, and reports the median slope with an exact binomial 95% confidence interval.")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .padding(.top, 6)
            } label: {
                Text("What we measured")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(NeuroTheme.textPrimary)
            }
            .tint(NeuroTheme.teal)

            Divider().background(NeuroTheme.border)

            DisclosureGroup(isExpanded: $showWhatThisCannotEstablish) {
                Text("This is an eye-movement **research indicator** and personal baseline comparison. A passing quality gate means the optical recording satisfied all 11 signal-quality criteria—**it does not establish that a person is neurologically normal, unintoxicated, or safe to drive**. Conversely, an ABSTAIN result means signal quality was insufficient to report a trustworthy number, not that a medical condition is present.")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .padding(.top, 6)
            } label: {
                Text("What this cannot establish")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(NeuroTheme.amber)
            }
            .tint(NeuroTheme.amber)
        }
        .padding(16)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
    }
}

private struct EvidenceCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(NeuroTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
