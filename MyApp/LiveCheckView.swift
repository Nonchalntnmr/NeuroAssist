import SwiftUI
import Charts

struct LiveCheckView: View {
    let tracker: FaceEyeTracker
    let store: DemoExperienceStore
    let onBack: () -> Void
    let onProceedToCalibration: () -> Void
    let onRunRecordedOrSimulatedWhenUnavailable: () -> Void

    private var lightGood: Bool {
        tracker.ambientLightLux >= 250.0
    }

    private var distanceGood: Bool {
        tracker.faceTracked && (25.0...40.0).contains(tracker.distanceCm)
    }

    private var headGood: Bool {
        tracker.faceTracked && tracker.isHeadSteady
    }

    private var fpsGood: Bool {
        tracker.frameRateFps >= 20.0
    }

    private var faceGood: Bool {
        tracker.faceTracked
    }

    private var eyesGood: Bool {
        tracker.faceTracked && tracker.blinkLeft <= 0.5 && tracker.blinkRight <= 0.5
    }

    private var checksList: [(name: String, passed: Bool, fix: String)] {
        [
            ("Light", lightGood, "Too dark: face a lamp or window"),
            ("Distance", distanceGood, tracker.distanceCm < 25 ? "Move phone slightly further (~30 cm)" : "Bring phone closer (~30 cm)"),
            ("Head", headGood, "Hold your head steady"),
            ("Frame rate", fpsGood, "Wait for camera to reach ≥ 20 fps"),
            ("Face", faceGood, "Center your face in the oval guide"),
            ("Eyes", eyesGood, "Keep both eyes open")
        ]
    }

    private var failedCount: Int {
        checksList.filter { !$0.passed }.count
    }

    private var readyToCalibrate: Bool {
        failedCount == 0 && !tracker.isDrivingDetected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Top bar
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Home")
                        }
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    Spacer()
                    Text("STEP 1 OF 3 · READY CHECK")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(NeuroTheme.teal)
                }

                if store.showPerformanceHUD {
                    RealTimePerformanceHUD(tracker: tracker)
                }

                if tracker.isDrivingDetected {
                    HStack(spacing: 10) {
                        Image(systemName: "car.fill")
                            .foregroundStyle(NeuroTheme.amber)
                        Text("Paused while you're moving — park safely before running an eye check.")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(NeuroTheme.amber)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeuroTheme.amber, lineWidth: 1))
                }

                if tracker.isInterrupted {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(NeuroTheme.amber)
                            Text("Camera Session Interrupted")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        Text("Another app, phone call, or system service interrupted the TrueDepth camera stream.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        HStack(spacing: 12) {
                            Button {
                                NeuroHaptics.selection()
                                tracker.retryCamera()
                            } label: {
                                Text("Resume Camera")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.amber)
                                    .foregroundStyle(NeuroTheme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button(action: onRunRecordedOrSimulatedWhenUnavailable) {
                                Text("Use Demo Trace")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.surface)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.amber, lineWidth: 1))
                }

                if let errorMsg = tracker.sessionErrorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(NeuroTheme.amber)
                            Text("Camera / ARKit Error")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        Text(errorMsg)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        HStack(spacing: 12) {
                            Button {
                                NeuroHaptics.selection()
                                tracker.retryCamera()
                            } label: {
                                Text("Retry Camera")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.amber)
                                    .foregroundStyle(NeuroTheme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button {
                                NeuroHaptics.selection()
                                tracker.enableEmulationMode()
                            } label: {
                                Text("Demo Mode")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.surface)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button(action: onRunRecordedOrSimulatedWhenUnavailable) {
                                Text("Use Demo Trace")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.surface)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.amber, lineWidth: 1))
                } else if tracker.cameraPermissionDenied {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Camera Access Disabled")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(NeuroTheme.amber)
                        Text("Live eye tracking requires front camera access. Enable camera permissions in iOS Settings.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        HStack(spacing: 12) {
                            Button {
                                tracker.openSettings()
                            } label: {
                                Text("Open Settings")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.amber)
                                    .foregroundStyle(NeuroTheme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button {
                                NeuroHaptics.selection()
                                tracker.retryCamera()
                            } label: {
                                Text("Retry Camera")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.surface)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button(action: onRunRecordedOrSimulatedWhenUnavailable) {
                                Text("Use Demo Trace")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NeuroTheme.surface)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(16)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.amber, lineWidth: 1))
                } else if tracker.isSimulatorEmulation {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.tv")
                            .foregroundStyle(NeuroTheme.teal)
                        Text("DEMO MODE · SYNTHETIC EYE DATA · RESULTS MARKED SIMULATED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Spacer()
                        #if !targetEnvironment(simulator)
                        Button {
                            NeuroHaptics.selection()
                            tracker.retryCamera()
                        } label: {
                            Text("EXIT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.amber)
                        }
                        #endif
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(NeuroTheme.teal.opacity(0.3), lineWidth: 1))
                }

                // Live Face Guide — Live Video Preview inside Dashed Oval with Iris Lock Rings & Eye Corner Dots
                LiveFaceIrisGuideCard(tracker: tracker)

                // 6 Live Tiles: Light, Distance, Head, Frame rate, Face, Eyes
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatusTile(
                        title: "LIGHT",
                        value: String(format: "%.0f lx", tracker.ambientLightLux),
                        isGood: lightGood
                    )
                    StatusTile(
                        title: "DISTANCE",
                        value: tracker.faceTracked ? String(format: "%.0f cm", tracker.distanceCm) : "— cm",
                        isGood: distanceGood
                    )
                    StatusTile(
                        title: "HEAD",
                        value: headGood ? "Steady" : "Moving",
                        isGood: headGood
                    )
                    StatusTile(
                        title: "FRAME RATE",
                        value: String(format: "%.0f fps", tracker.frameRateFps),
                        isGood: fpsGood
                    )
                    StatusTile(
                        title: "FACE",
                        value: faceGood ? "Locked" : "Lost",
                        isGood: faceGood
                    )
                    StatusTile(
                        title: "EYES",
                        value: eyesGood ? "Open" : "Blink",
                        isGood: eyesGood
                    )
                }

                // Live 5-second unsmoothed raw yaw preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("LIVE HORIZONTAL EYE YAW (5 S)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Spacer()
                        Text(tracker.faceTracked ? String(format: "%+.1f° raw", tracker.currentRawYawDeg) : "—")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(tracker.faceTracked ? NeuroTheme.teal : NeuroTheme.amber)
                    }

                    let validSamples = tracker.recentSamples.filter(\.isValid)
                    let latestTime = tracker.recentSamples.last?.timestamp ?? 0.0

                    Chart(validSamples) { sample in
                        LineMark(
                            x: .value("Time (s)", sample.timestamp - latestTime),
                            y: .value("Yaw (°)", sample.rawYawDeg)
                        )
                        .foregroundStyle(NeuroTheme.teal)
                        .interpolationMethod(.linear)
                    }
                    .chartXScale(domain: -5.0...0.0)
                    .chartYScale(domain: -20.0...20.0)
                    .frame(height: 95)
                }
                .padding(14)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))

                // Start Button stays grey ("Fix N things to start") until all 6 are green, then glows teal
                Button {
                    NeuroHaptics.impact(.medium)
                    onProceedToCalibration()
                } label: {
                    HStack {
                        if readyToCalibrate {
                            Text("All 6 Green — Start 5-Dot Calibration")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                        } else if tracker.isDrivingDetected {
                            Text("Paused while you're moving")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                        } else {
                            let firstFix = checksList.first(where: { !$0.passed })?.fix ?? ""
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fix \(failedCount) \(failedCount == 1 ? "thing" : "things") to start")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                if !firstFix.isEmpty {
                                    Text(firstFix)
                                        .font(.system(.caption, design: .default))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: readyToCalibrate ? "arrow.right.circle.fill" : "lock.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(readyToCalibrate ? NeuroTheme.teal : NeuroTheme.border)
                    .foregroundStyle(readyToCalibrate ? NeuroTheme.background : NeuroTheme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: readyToCalibrate ? NeuroTheme.teal.opacity(0.55) : .clear, radius: 12, y: 4)
                }
                .disabled(!readyToCalibrate)

                if !tracker.isSimulatorEmulation {
                    HStack(spacing: 12) {
                        Button {
                            NeuroHaptics.selection()
                            tracker.enableEmulationMode()
                        } label: {
                            Label("Run in Demo Mode", systemImage: "sparkles.tv")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.teal)
                        }
                        Spacer()
                        Button(action: onRunRecordedOrSimulatedWhenUnavailable) {
                            Text("Use Demo Trace")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Text(NeuroTheme.researchFooter)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .onAppear {
            if !tracker.isRunning {
                tracker.start()
            }
        }
    }
}

// MARK: - Live Face Guide (Dashed Oval, Teal Lock-On Iris Rings, Amber Eye Corner Dots)

private struct LiveFaceIrisGuideCard: View {
    let tracker: FaceEyeTracker

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TRUEDEPTH EYE & FACE TRACKING GUIDE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(tracker.irisLocked ? NeuroTheme.teal : NeuroTheme.amber)
                        .frame(width: 7, height: 7)
                    Text(tracker.irisLocked ? "EYES TRACKED" : "ACQUIRING EYES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(tracker.irisLocked ? NeuroTheme.teal : NeuroTheme.amber)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let centerX = w * 0.5
                let centerY = h * 0.5
                let ovalW = min(w * 0.58, 190.0)
                let ovalH = h * 0.88

                ZStack {
                    // Live camera preview layer clipped to oval
                    Group {
                        if tracker.isInterrupted {
                            VStack(spacing: 8) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(NeuroTheme.amber)
                                Text("CAMERA PAUSED")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.amber)
                                Text("Interrupted")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                            .frame(width: ovalW, height: ovalH)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Ellipse())
                        } else if let errorMsg = tracker.sessionErrorMessage {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(NeuroTheme.amber)
                                Text("CAMERA ISSUE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.amber)
                                Text(errorMsg)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                            .frame(width: ovalW, height: ovalH)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Ellipse())
                        } else if tracker.cameraPermissionDenied {
                            CameraPermissionDeniedMiniView(tracker: tracker)
                                .frame(width: ovalW, height: ovalH)
                                .clipShape(Ellipse())
                        } else if tracker.isTrueDepthSupported && !tracker.isSimulatorEmulation {
                            #if !targetEnvironment(simulator)
                            ARCameraPreview(session: tracker.rawARSession)
                                .frame(width: ovalW, height: ovalH)
                                .clipShape(Ellipse())
                                .overlay(Color.black.opacity(0.12))
                            #else
                            SimulatorCameraPlaceholderView(tracker: tracker)
                                .frame(width: ovalW, height: ovalH)
                                .clipShape(Ellipse())
                            #endif
                        } else {
                            SimulatorCameraPlaceholderView(tracker: tracker)
                                .frame(width: ovalW, height: ovalH)
                                .clipShape(Ellipse())
                        }
                    }
                    .position(x: centerX, y: centerY)

                    // Dashed face guide oval
                    Ellipse()
                        .stroke(
                            tracker.faceTracked ? NeuroTheme.teal.opacity(0.85) : NeuroTheme.amber.opacity(0.75),
                            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                        )
                        .frame(width: ovalW, height: ovalH)
                        .position(x: centerX, y: centerY)

                    // Amber dots on left and right eye corners (inner & outer canthi)
                    ForEach(0..<tracker.leftEyeCornersNormalized.count, id: \.self) { idx in
                        let pt = tracker.leftEyeCornersNormalized[idx]
                        Circle()
                            .fill(NeuroTheme.amber)
                            .frame(width: 6, height: 6)
                            .position(
                                x: centerX + pt.x * (ovalW * 0.5),
                                y: centerY + pt.y * (ovalH * 0.5)
                            )
                    }
                    ForEach(0..<tracker.rightEyeCornersNormalized.count, id: \.self) { idx in
                        let pt = tracker.rightEyeCornersNormalized[idx]
                        Circle()
                            .fill(NeuroTheme.amber)
                            .frame(width: 6, height: 6)
                            .position(
                                x: centerX + pt.x * (ovalW * 0.5),
                                y: centerY + pt.y * (ovalH * 0.5)
                            )
                    }

                    // Teal rings that lock onto both irises with spring physics
                    IrisLockRing(isLocked: tracker.irisLocked)
                        .position(
                            x: centerX + tracker.leftIrisNormalized.x * (ovalW * 0.5),
                            y: centerY + tracker.leftIrisNormalized.y * (ovalH * 0.5)
                        )
                        .animation(.spring(duration: 0.22, bounce: 0.3), value: tracker.irisLocked)

                    IrisLockRing(isLocked: tracker.irisLocked)
                        .position(
                            x: centerX + tracker.rightIrisNormalized.x * (ovalW * 0.5),
                            y: centerY + tracker.rightIrisNormalized.y * (ovalH * 0.5)
                        )
                        .animation(.spring(duration: 0.22, bounce: 0.3), value: tracker.irisLocked)
                }
            }
            .frame(height: 155)
        }
        .padding(14)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
    }
}

private struct IrisLockRing: View {
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isLocked ? NeuroTheme.teal : NeuroTheme.amber, lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .fill(isLocked ? NeuroTheme.teal : NeuroTheme.amber)
                .frame(width: 6, height: 6)
        }
        .shadow(color: (isLocked ? NeuroTheme.teal : NeuroTheme.amber).opacity(0.6), radius: 4)
    }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(isGood ? NeuroTheme.teal : NeuroTheme.amber)
                    .frame(width: 6, height: 6)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.border, lineWidth: 1))
    }
}
