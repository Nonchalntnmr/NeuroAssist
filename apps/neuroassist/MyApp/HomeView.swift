import SwiftUI

struct HomeView: View {
    @Binding var protocolMode: MeasurementProtocolMode
    let tracker: FaceEyeTracker
    let store: DemoExperienceStore
    let lastResult: OKNAnalysisResult?
    let onStartLiveCheck: () -> Void
    let onLaunchResultDirect: (OKNAnalysisResult, CalibrationModel) -> Void

    @State private var showingValidationHarness = false
    @State private var showingPauseArriveSafe = false
    @State private var showingBaselineSheet = false
    @State private var showingModulesSheet = false
    @State private var showingDemoReplaySheet = false

    var body: some View {
        Group {
            if store.stageModeEnabled {
                stageModeHeroView
            } else {
                fullDashboardScrollView
            }
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingValidationHarness) {
            ValidationHarnessSheetView()
        }
        .sheet(isPresented: $showingPauseArriveSafe) {
            PauseAndArriveSafeSheet(store: store, onRetakeCheck: onStartLiveCheck)
        }
        .sheet(isPresented: $showingBaselineSheet) {
            BaselineTrendSheet(store: store)
        }
        .sheet(isPresented: $showingModulesSheet) {
            ModulesVisionSheet()
        }
        .sheet(isPresented: $showingDemoReplaySheet) {
            TransparentDemoAndReplaySheet(
                store: store,
                protocolMode: protocolMode,
                onSelectResult: { res, cal in
                    showingDemoReplaySheet = false
                    onLaunchResultDirect(res, cal)
                }
            )
        }
    }

    // MARK: - 10. STAGE MODE (Projector / Judges Presentation View: Giant Type, One Button)

    private var stageModeHeroView: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                HStack(spacing: 10) {
                    SawtoothSignatureView(height: 28, cycles: 3, animate: true)
                        .frame(width: 68)
                    Text("STAGE MODE")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(NeuroTheme.teal)
                }
                Spacer()
                Button {
                    NeuroHaptics.selection()
                    store.stageModeEnabled = false
                } label: {
                    Text("Exit Stage Mode")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if store.showPerformanceHUD {
                RealTimePerformanceHUD(tracker: tracker)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("NeuroAssist")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(NeuroTheme.textPrimary)

                Text(NeuroTheme.homeTagline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(NeuroTheme.teal)

                Text("60 Hz TrueDepth Oculomotor Reflex & 11-Gate Abstention Engine")
                    .font(.system(.headline, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }

            Spacer()

            Button {
                NeuroHaptics.impact(.heavy)
                onStartLiveCheck()
            } label: {
                HStack {
                    Text("Run stripes demo")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .background(NeuroTheme.teal)
                .foregroundStyle(NeuroTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: NeuroTheme.teal.opacity(0.65), radius: 18, y: 6)
            }

            HStack {
                Button("Simulated & Recorded Replay") {
                    showingDemoReplaySheet = true
                }
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(NeuroTheme.teal)

                Spacer()

                Toggle("HUD", isOn: Bindable(store).showPerformanceHUD)
                    .labelsHidden()
                    .tint(NeuroTheme.teal)
                Text("DEV HUD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }

            Text(NeuroTheme.researchFooter)
                .font(.system(.caption, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(28)
    }

    // MARK: - 1. Full Home Dashboard

    private var fullDashboardScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Brand Header + Sawtooth Signature + Stage Mode / HUD toggles
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            SawtoothSignatureView(height: 22, cycles: 3, animate: true)
                                .frame(width: 52)
                            Text("NEUROASSIST")
                                .font(.system(.caption, design: .monospaced).weight(.heavy))
                                .foregroundStyle(NeuroTheme.teal)
                        }
                        Text("NeuroAssist")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(NeuroTheme.textPrimary)
                        Text(NeuroTheme.homeTagline)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(NeuroTheme.teal)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            NeuroHaptics.selection()
                            store.stageModeEnabled = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles.tv")
                                Text("STAGE MODE")
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(NeuroTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NeuroTheme.teal.opacity(0.5), lineWidth: 1))
                        }

                        Button {
                            NeuroHaptics.selection()
                            store.showPerformanceHUD.toggle()
                        } label: {
                            Text(store.showPerformanceHUD ? "HUD: ON" : "HUD: OFF")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(store.showPerformanceHUD ? NeuroTheme.teal : NeuroTheme.textSecondary)
                        }
                    }
                }

                if store.showPerformanceHUD {
                    RealTimePerformanceHUD(tracker: tracker)
                }

                if tracker.isDrivingDetected {
                    HStack(spacing: 10) {
                        Image(systemName: "car.fill")
                            .foregroundStyle(NeuroTheme.amber)
                        Text("Paused while you're moving — tests lock automatically while driving.")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(NeuroTheme.amber)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeuroTheme.amber, lineWidth: 1))
                }

                // Big "Pre-drive check · 60 s" hero card with glowing teal Start button
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("PRE-DRIVE CHECK · 60 S")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(NeuroTheme.teal)
                        Spacer()
                        Picker("Mode", selection: $protocolMode) {
                            Text("Research (20s)").tag(MeasurementProtocolMode.researchFixed)
                            Text("Fast (~10s)").tag(MeasurementProtocolMode.adaptiveFast)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 175)
                    }

                    Text("Ready check → 5-spot calibration → 10 s stripes reflex")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(NeuroTheme.textPrimary)

                    Text("Measures horizontal optokinetic slow-phase eye velocity in calibrated degrees/sec. Refuses to output a number if any of the 11 signal-quality gates fail.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)

                    Button {
                        NeuroHaptics.impact(.medium)
                        onStartLiveCheck()
                    } label: {
                        HStack {
                            Text(tracker.isDrivingDetected ? "Paused while you're moving" : "Start Pre-Drive Check")
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(tracker.isDrivingDetected ? NeuroTheme.border : NeuroTheme.teal)
                        .foregroundStyle(tracker.isDrivingDetected ? NeuroTheme.textSecondary : NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: tracker.isDrivingDetected ? .clear : NeuroTheme.teal.opacity(0.55), radius: 14, y: 4)
                    }
                    .disabled(tracker.isDrivingDetected)
                }
                .padding(18)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(NeuroTheme.teal.opacity(0.6), lineWidth: 1.5)
                )

                // "Last result" and "Vs your usual" tiles
                HStack(spacing: 12) {
                    Button {
                        showingBaselineSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LAST RESULT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                            if let last = lastResult {
                                if last.didAbstain {
                                    Text("ABSTAIN")
                                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                                        .foregroundStyle(NeuroTheme.amber)
                                    Text("\(last.failedChecks.count) gate(s) failed")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(NeuroTheme.amber)
                                } else if let gain = last.gain, let spv = last.slowPhaseSpeedDegPerSec {
                                    Text(String(format: "%.2f", gain))
                                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                                        .foregroundStyle(NeuroTheme.teal)
                                    Text(String(format: "%.1f °/s · %@ ", spv, last.provenance.rawValue))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(NeuroTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            } else if let latestBase = store.baselineEntries.last {
                                Text(String(format: "%.2f", latestBase.gain))
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NeuroTheme.teal)
                                Text(String(format: "%.1f °/s slow-phase", latestBase.slowPhaseSpeedDegPerSec))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            } else {
                                Text("—")
                                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Text("No live run yet")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))
                    }

                    Button {
                        showingBaselineSheet = true
                    } label: {
                        let band = store.usualGainRange
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("VS YOUR USUAL")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                Spacer()
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.caption)
                                    .foregroundStyle(NeuroTheme.teal)
                            }
                            if let latest = store.baselineEntries.last {
                                let within = (band.lower...band.upper).contains(latest.gain)
                                Text(within ? "Usual Range" : "Changed")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(within ? NeuroTheme.teal : NeuroTheme.amber)
                                Text(String(format: "Band %.2f–%.2f", band.lower, band.upper))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            } else {
                                Text(String(format: "%.2f–%.2f", band.lower, band.upper))
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("Tap for trend chart")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.teal)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))
                    }
                }

                // Test & Platform Grid (Simulation/Replay, Baseline, Modules, Validation Harness)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    GridActionTile(
                        icon: "waveform.badge.magnifyingglass",
                        title: "Sim & Replay",
                        subtitle: "Watermarked demo & recorded traces",
                        accent: NeuroTheme.teal
                    ) {
                        showingDemoReplaySheet = true
                    }

                    GridActionTile(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Baseline",
                        subtitle: "Personal usual band & intervals",
                        accent: NeuroTheme.teal
                    ) {
                        showingBaselineSheet = true
                    }

                    GridActionTile(
                        icon: "square.grid.2x2.fill",
                        title: "6 Modules",
                        subtitle: "Vestibular, Fatigue, Concussion…",
                        accent: NeuroTheme.teal
                    ) {
                        showingModulesSheet = true
                    }

                    GridActionTile(
                        icon: "checkmark.shield.fill",
                        title: "Validation",
                        subtitle: "8-trace Fixed vs Fast benchmark",
                        accent: NeuroTheme.teal
                    ) {
                        showingValidationHarness = true
                    }
                }

                // "Arrive Safe" Row
                Button {
                    NeuroHaptics.selection()
                    showingPauseArriveSafe = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "location.fill.viewfinder")
                            .font(.title2)
                            .foregroundStyle(NeuroTheme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause & Arrive Safe")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NeuroTheme.textPrimary)
                            Text(
                                store.arriveSafeActive
                                ? "Active: Sharing with \(store.arriveSafeContactName) · ETA \(store.arriveSafeETAString)"
                                : "20-min rest timer, ride-share links, consented ETA share & 911 card"
                            )
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(store.arriveSafeActive ? NeuroTheme.teal : NeuroTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
                }

                Text(NeuroTheme.researchFooter)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }
}

private struct GridActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(NeuroTheme.textPrimary)
                Text(subtitle)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NeuroTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))
        }
    }
}

// MARK: - C & D. TRANSPARENT DEMONSTRATION MODE & RECORDED SESSION REPLAY SHEET

struct TransparentDemoAndReplaySheet: View {
    let store: DemoExperienceStore
    let protocolMode: MeasurementProtocolMode
    let onSelectResult: (OKNAnalysisResult, CalibrationModel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section D: Recorded Numerical Session Replay
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .foregroundStyle(NeuroTheme.teal)
                            Text("RECORDED NUMERICAL SESSIONS (NO VIDEO)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.teal)
                        }
                        Text("Replays consented numerical eye-pose traces through the live signal pipeline with a persistent RECORDED SESSION watermark.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        ForEach(store.recordedSessions) { rec in
                            Button {
                                NeuroHaptics.selection()
                                let res = SignalMath.analyzeOptokinetic(
                                    samples: rec.samples,
                                    calibration: rec.calibration,
                                    stripeDirectionSign: 1.0,
                                    mode: protocolMode,
                                    provenance: .recordedSession,
                                    stoppedEarly: false
                                )
                                onSelectResult(res, rec.calibration)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(rec.title)
                                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                                            .foregroundStyle(NeuroTheme.textPrimary)
                                        Spacer()
                                        Text("REPLAY →")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(NeuroTheme.teal)
                                    }
                                    Text(rec.summaryNote)
                                        .font(.system(.caption2, design: .default))
                                        .foregroundStyle(NeuroTheme.textSecondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NeuroTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeuroTheme.border, lineWidth: 1))
                            }
                        }
                    }

                    Divider().background(NeuroTheme.border)

                    // Section C: Transparent Demonstration Mode (Always Watermarked SIMULATED)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles.tv")
                                .foregroundStyle(NeuroTheme.amber)
                            Text("TRANSPARENT SIMULATION MODE (ISOLATED)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        Text("Every simulated scenario displays a persistent SIMULATED banner and is strictly isolated from real personal baselines.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        ForEach(DemoSimScenario.allCases) { scenario in
                            Button {
                                NeuroHaptics.selection()
                                let (res, cal) = DemoExperienceStore.runSimulatedScenario(scenario, mode: protocolMode)
                                onSelectResult(res, cal)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scenario.rawValue)
                                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                                            .foregroundStyle(NeuroTheme.textPrimary)
                                        Text("Watermarked SIMULATED · Full 11-gate pipeline evaluation")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(NeuroTheme.amber)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(NeuroTheme.amber)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NeuroTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeuroTheme.amber.opacity(0.45), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Demo & Session Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Scientific Validation Harness Sheet

struct ValidationHarnessSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: ValidationBenchmarkReport? = nil
    @State private var isRunning: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isRunning {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(NeuroTheme.teal)
                            Text("Replaying synthetic & contaminated optokinetic traces through Fixed Reference vs. Adaptive Fast pipelines…")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else if let report {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(NeuroTheme.teal)
                                Text("VALIDATION SUITE SUMMARY (\(report.trials.count) SCENARIOS)")
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(NeuroTheme.teal)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                HarnessStatTile(
                                    title: "Calibration Time",
                                    value: String(format: "%.1fs → %.1fs", report.meanFixedCalibrationSec, report.meanAdaptiveCalibrationSec),
                                    subtitle: "5 spatial targets",
                                    isGood: true
                                )
                                HarnessStatTile(
                                    title: "Stimulus Time (Clean)",
                                    value: String(format: "%.1fs → %.1fs", report.meanFixedStimulusSec, report.meanAdaptiveStimulusSec),
                                    subtitle: String(format: "-%.0f%% total duration", report.timeReductionPercent),
                                    isGood: true
                                )
                                HarnessStatTile(
                                    title: "Velocity Error (MAE)",
                                    value: String(format: "%.2f°/s vs %.2f°/s", report.fixedMeanAbsErrorDegPerSec, report.adaptiveMeanAbsErrorDegPerSec),
                                    subtitle: String(format: "Bias %+.2f vs %+.2f°/s", report.fixedBiasDegPerSec, report.adaptiveBiasDegPerSec),
                                    isGood: report.adaptiveMeanAbsErrorDegPerSec <= 0.5
                                )
                                HarnessStatTile(
                                    title: "Gate Safety (11 Gates)",
                                    value: String(format: "%.0f%% Agreement", report.gateAgreementRate * 100.0),
                                    subtitle: String(format: "False Accept: %.0f%%", report.falseAcceptanceRate * 100.0),
                                    isGood: report.falseAcceptanceRate == 0.0
                                )
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
                }
                .padding(20)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Validation Harness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(20))
                report = ValidationHarness.runSuite()
                isRunning = false
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct HarnessStatTile: View {
    let title: String
    let value: String
    let subtitle: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(isGood ? NeuroTheme.teal : NeuroTheme.amber)
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
