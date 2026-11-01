import SwiftUI
import UIKit

enum PrimaryNavTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case scan = "Scan"
    case history = "History"
    case drivingResearch = "Driving Research"
    case messages = "Messages"
    case profile = "Profile"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .scan: return "eye.circle.fill"
        case .history: return "chart.xyaxis.line"
        case .drivingResearch: return "car.side.and.exclamationmark"
        case .messages: return "paperplane.fill"
        case .profile: return "person.badge.shield.checkmark.fill"
        }
    }
}

enum AppFlowStep: Equatable {
    case home
    case liveCheck
    case calibration
    case stripesTest(CalibrationModel)
    case result(OKNAnalysisResult, CalibrationModel?)
}

struct ContentView: View {
    @State private var tracker = FaceEyeTracker()
    @State private var store = DemoExperienceStore()
    @State private var platformStore = PlatformServicesStore()
    @State private var activeTab: PrimaryNavTab = .home
    @State private var step: AppFlowStep = .home
    @State private var acceptedCalibration: CalibrationModel? = nil
    @State private var lastResult: OKNAnalysisResult? = nil
    @State private var lastSamples: [EyeSample] = []
    @State private var collectiveBridge = CollectiveBridge()
    @State private var protocolMode: MeasurementProtocolMode = .researchFixed
    @State private var showingPauseArriveSafe: Bool = false
    @State private var pendingCategory: SessionTestCategory = .preDriveCheck
    @State private var pendingDrivingTag: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    private var isFullScreenCaptureActive: Bool {
        switch step {
        case .liveCheck, .calibration, .stripesTest:
            return true
        case .home, .result:
            return false
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NeuroTheme.background.ignoresSafeArea()

            Group {
                if isFullScreenCaptureActive {
                    scanFlowContainer
                } else {
                    switch activeTab {
                    case .home:
                        HomeView(
                            protocolMode: $protocolMode,
                            tracker: tracker,
                            store: store,
                            lastResult: lastResult,
                            onStartLiveCheck: {
                                pendingCategory = .preDriveCheck
                                pendingDrivingTag = nil
                                startLiveScanFlow()
                            },
                            onLaunchResultDirect: { directResult, cal in
                                acceptedCalibration = cal
                                lastResult = directResult
                                collectiveBridge.reset()
                                let cat: SessionTestCategory = directResult.provenance == .recordedSession ? .recordedReplay : .simulatedDemo
                                platformStore.recordMeasurementSession(
                                    result: directResult,
                                    calibration: cal,
                                    category: cat
                                )
                                withAnimation(.spring(duration: 0.3)) {
                                    activeTab = .scan
                                    step = .result(directResult, cal)
                                }
                            }
                        )
                        .padding(.bottom, 68)

                    case .scan:
                        scanFlowContainer
                            .padding(.bottom, 68)

                    case .history:
                        HistoryDashboardView(
                            platformStore: platformStore,
                            onStartNewScan: {
                                pendingCategory = .preDriveCheck
                                pendingDrivingTag = nil
                                startLiveScanFlow()
                            }
                        )
                        .padding(.bottom, 68)

                    case .drivingResearch:
                        DrivingResearchModuleView(
                            platformStore: platformStore,
                            onLaunchExperimentalScan: { factor in
                                pendingCategory = .drivingResearchProtocol
                                pendingDrivingTag = factor.rawValue
                                startLiveScanFlow()
                            }
                        )
                        .padding(.bottom, 68)

                    case .messages:
                        MessagesAndSharingHubView(
                            platformStore: platformStore,
                            demoStore: store
                        )
                        .padding(.bottom, 68)

                    case .profile:
                        AccountAndPrivacyCenterView(
                            platformStore: platformStore,
                            demoStore: store
                        )
                        .padding(.bottom, 68)
                    }
                }
            }

            if !isFullScreenCaptureActive {
                NeuroAssistBottomNavBar(
                    activeTab: $activeTab,
                    onTapScanTab: {
                        if case .result = step {
                            activeTab = .scan
                        } else {
                            pendingCategory = .preDriveCheck
                            pendingDrivingTag = nil
                            startLiveScanFlow()
                        }
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: step) { _, newStep in
            switch newStep {
            case .liveCheck, .calibration, .stripesTest:
                UIApplication.shared.isIdleTimerDisabled = true
            case .home, .result:
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                tracker.stop()
            } else if newPhase == .active {
                switch step {
                case .liveCheck, .calibration, .stripesTest:
                    tracker.start()
                case .home, .result:
                    break
                }
            }
        }
        .sheet(isPresented: $showingPauseArriveSafe) {
            PauseAndArriveSafeSheet(store: store) {
                if let cal = acceptedCalibration, cal.isAccepted {
                    tracker.start()
                    activeTab = .scan
                    step = .stripesTest(cal)
                } else {
                    startLiveScanFlow()
                }
            }
        }
    }

    private func startLiveScanFlow() {
        activeTab = .scan
        tracker.start()
        withAnimation(.spring(duration: 0.3)) {
            step = .liveCheck
        }
    }

    @ViewBuilder
    private var scanFlowContainer: some View {
        switch step {
        case .home:
            HomeView(
                protocolMode: $protocolMode,
                tracker: tracker,
                store: store,
                lastResult: lastResult,
                onStartLiveCheck: {
                    startLiveScanFlow()
                },
                onLaunchResultDirect: { directResult, cal in
                    acceptedCalibration = cal
                    lastResult = directResult
                    collectiveBridge.reset()
                    let cat: SessionTestCategory = directResult.provenance == .recordedSession ? .recordedReplay : .simulatedDemo
                    platformStore.recordMeasurementSession(
                        result: directResult,
                        calibration: cal,
                        category: cat
                    )
                    withAnimation(.spring(duration: 0.3)) {
                        step = .result(directResult, cal)
                    }
                }
            )

        case .liveCheck:
            LiveCheckView(
                tracker: tracker,
                store: store,
                onBack: {
                    tracker.stop()
                    withAnimation(.spring(duration: 0.3)) {
                        step = .home
                        activeTab = .home
                    }
                },
                onProceedToCalibration: {
                    withAnimation(.spring(duration: 0.3)) {
                        step = .calibration
                    }
                },
                onRunRecordedOrSimulatedWhenUnavailable: {
                    tracker.stop()
                    let (simRes, simCal) = DemoExperienceStore.runSimulatedScenario(.validPursuit, mode: protocolMode)
                    acceptedCalibration = simCal
                    lastResult = simRes
                    collectiveBridge.reset()
                    platformStore.recordMeasurementSession(
                        result: simRes,
                        calibration: simCal,
                        category: .simulatedDemo,
                        drivingResearchTag: pendingDrivingTag
                    )
                    withAnimation(.spring(duration: 0.3)) {
                        step = .result(simRes, simCal)
                    }
                }
            )

        case .calibration:
            CalibrationView(
                tracker: tracker,
                store: store,
                protocolMode: protocolMode,
                onBack: {
                    withAnimation(.spring(duration: 0.3)) {
                        step = .liveCheck
                    }
                },
                onCalibrationAccepted: { model in
                    acceptedCalibration = model
                    withAnimation(.spring(duration: 0.3)) {
                        step = .stripesTest(model)
                    }
                }
            )

        case .stripesTest(let model):
            StripesTestView(
                tracker: tracker,
                store: store,
                calibration: model,
                protocolMode: protocolMode,
                onCancel: {
                    withAnimation(.spring(duration: 0.3)) {
                        step = .calibration
                    }
                },
                onCompleted: { analysisResult, rawSamples in
                    lastResult = analysisResult
                    lastSamples = rawSamples
                    collectiveBridge.reset()
                    store.recordRealResult(analysisResult, samples: rawSamples, calibration: model)
                    platformStore.recordMeasurementSession(
                        result: analysisResult,
                        calibration: model,
                        category: analysisResult.provenance == .simulated ? .simulatedDemo : pendingCategory,
                        drivingResearchTag: pendingDrivingTag
                    )
                    withAnimation(.spring(duration: 0.3)) {
                        step = .result(analysisResult, model)
                    }
                    if analysisResult.didAbstain && store.consecutiveAbstainCount >= 2 {
                        showingPauseArriveSafe = true
                    }
                }
            )

        case .result(let analysisResult, let calModel):
            ResultView(
                result: analysisResult,
                calibration: calModel,
                store: store,
                onRetakeTest: {
                    if let cal = calModel ?? acceptedCalibration, cal.isAccepted {
                        tracker.start()
                        withAnimation(.spring(duration: 0.3)) {
                            step = .stripesTest(cal)
                        }
                    } else {
                        tracker.start()
                        withAnimation(.spring(duration: 0.3)) {
                            step = .calibration
                        }
                    }
                },
                onRecalibrate: {
                    acceptedCalibration = nil
                    tracker.start()
                    withAnimation(.spring(duration: 0.3)) {
                        step = .calibration
                    }
                },
                onDoneHome: {
                    tracker.stop()
                    withAnimation(.spring(duration: 0.3)) {
                        step = .home
                        activeTab = .home
                    }
                },
                onOpenPauseAndArriveSafe: {
                    showingPauseArriveSafe = true
                },
                bridge: collectiveBridge,
                // Raw trace only belongs to the result it was recorded with
                rawSamples: analysisResult == lastResult ? lastSamples : []
            )
        }
    }
}

// MARK: - 6-TAB SCIENTIFIC INSTRUMENT NAVIGATION BAR

struct NeuroAssistBottomNavBar: View {
    @Binding var activeTab: PrimaryNavTab
    let onTapScanTab: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PrimaryNavTab.allCases) { tab in
                let isSelected = (activeTab == tab)
                Button {
                    NeuroHaptics.selection()
                    if tab == .scan {
                        onTapScanTab()
                    } else {
                        withAnimation(.spring(duration: 0.25)) {
                            activeTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? NeuroTheme.teal : NeuroTheme.textSecondary)
                        Text(tab == .drivingResearch ? "Research" : tab.rawValue)
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? NeuroTheme.textPrimary : NeuroTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? NeuroTheme.teal.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(tab.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            NeuroTheme.surface
                .overlay(Rectangle().fill(NeuroTheme.border).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
