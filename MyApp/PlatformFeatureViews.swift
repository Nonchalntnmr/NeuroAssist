import SwiftUI
import Charts

// MARK: - TAB 3: PERSISTENT MEASUREMENT HISTORY DASHBOARD

struct HistoryDashboardView: View {
    let platformStore: PlatformServicesStore
    let onStartNewScan: () -> Void

    @State private var selectedCategoryFilter: String = "All"
    @State private var searchDateRangeDays: Int = 90
    @State private var selectedSessionForDetail: PersistentMeasurementSession? = nil
    @State private var compareSessionA: PersistentMeasurementSession? = nil
    @State private var compareSessionB: PersistentMeasurementSession? = nil
    @State private var showingComparisonSheet: Bool = false
    @State private var showingDeleteAllAlert: Bool = false
    @State private var exportedCSVURL: URL? = nil
    @State private var exportedJSONURL: URL? = nil

    private var filteredSessions: [PersistentMeasurementSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -searchDateRangeDays, to: Date()) ?? .distantPast
        return platformStore.sessions.filter { session in
            let matchesDate = session.timestamp >= cutoff
            let matchesCategory = (selectedCategoryFilter == "All") || (session.testCategory.rawValue == selectedCategoryFilter)
            return matchesDate && matchesCategory
        }
    }

    private var measuredSessions: [PersistentMeasurementSession] {
        filteredSessions.filter { !$0.didAbstain && $0.oknGain != nil }.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header & Export Actions
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ENCRYPTED LONGITUDINAL ARCHIVE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Text("Measurement History")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(NeuroTheme.textPrimary)
                        Text("\(filteredSessions.count) recorded session(s) · AES-256-GCM local vault")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        onStartNewScan()
                    } label: {
                        Label("New Scan", systemImage: "eye.fill")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(NeuroTheme.teal)
                            .foregroundStyle(NeuroTheme.background)
                            .clipShape(Capsule())
                    }
                }

                // Filter Controls (Date Range & Test Type)
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(title: "All", isSelected: selectedCategoryFilter == "All") {
                                selectedCategoryFilter = "All"
                            }
                            ForEach(SessionTestCategory.allCases) { cat in
                                filterChip(title: cat.rawValue, isSelected: selectedCategoryFilter == cat.rawValue) {
                                    selectedCategoryFilter = cat.rawValue
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("DATE WINDOW:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        ForEach([7, 30, 90, 365], id: \.self) { days in
                            Button {
                                searchDateRangeDays = days
                            } label: {
                                Text("\(days)d")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(searchDateRangeDays == days ? NeuroTheme.teal.opacity(0.2) : NeuroTheme.background)
                                    .foregroundStyle(searchDateRangeDays == days ? NeuroTheme.teal : NeuroTheme.textSecondary)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                }
                .padding(12)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))

                // Longitudinal Chart (Only Valid Measured Sessions — Never Fabricating Missing/Abstain Numbers)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LONGITUDINAL OKN GAIN & 95% CI")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Spacer()
                        Text("ABSTAIN SESSIONS EXCLUDED FROM NUMERIC FIT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.amber)
                    }

                    if measuredSessions.isEmpty {
                        Text("No valid measured sessions in the selected filter window. Unreliable (ABSTAIN) runs are preserved in the timeline below without fabricating numerical gain values.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                            .padding(.vertical, 16)
                    } else {
                        Chart {
                            ForEach(Array(measuredSessions.enumerated()), id: \.element.id) { idx, session in
                                if let gain = session.oknGain {
                                    let ciLo = (session.confidenceIntervalLowerDegPerSec ?? (gain * 10.0 - 0.8)) / 10.0
                                    let ciHi = (session.confidenceIntervalUpperDegPerSec ?? (gain * 10.0 + 0.8)) / 10.0
                                    RuleMark(
                                        x: .value("Run", idx + 1),
                                        yStart: .value("CI Low", ciLo),
                                        yEnd: .value("CI High", ciHi)
                                    )
                                    .foregroundStyle(NeuroTheme.teal.opacity(0.45))
                                    .lineStyle(StrokeStyle(lineWidth: 2))

                                    LineMark(
                                        x: .value("Run", idx + 1),
                                        y: .value("Gain", gain)
                                    )
                                    .foregroundStyle(NeuroTheme.teal)

                                    PointMark(
                                        x: .value("Run", idx + 1),
                                        y: .value("Gain", gain)
                                    )
                                    .foregroundStyle(NeuroTheme.teal)
                                    .symbolSize(55)
                                }
                            }
                        }
                        .chartYScale(domain: 0.0...1.2)
                        .frame(height: 185)
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // Session-to-Session Comparison Bar
                if filteredSessions.count >= 2 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COMPARE TWO SESSIONS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.teal)
                            Text(compareSubtitle)
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            if compareSessionA == nil {
                                compareSessionA = filteredSessions.first
                            }
                            if compareSessionB == nil && filteredSessions.count >= 2 {
                                compareSessionB = filteredSessions[1]
                            }
                            showingComparisonSheet = true
                        } label: {
                            Text("Compare")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(NeuroTheme.background)
                                .foregroundStyle(NeuroTheme.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NeuroTheme.teal, lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))
                }

                // Export & Complete Data Deletion Controls
                HStack(spacing: 10) {
                    if let csvURL = exportedCSVURL {
                        ShareLink(item: csvURL) {
                            Label("Share CSV", systemImage: "tablecells")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        Button {
                            exportedCSVURL = platformStore.exportSessionsAsCSVFile(sessionsToExport: filteredSessions)
                        } label: {
                            Label("Export CSV", systemImage: "arrow.down.doc")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.surface)
                                .foregroundStyle(NeuroTheme.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.border, lineWidth: 1))
                        }
                    }

                    if let jsonURL = exportedJSONURL {
                        ShareLink(item: jsonURL) {
                            Label("Share JSON", systemImage: "curlybraces")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        Button {
                            exportedJSONURL = platformStore.exportSessionsAsJSONFile(sessionsToExport: filteredSessions)
                        } label: {
                            Label("Export JSON", systemImage: "doc.badge.gearshape")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.surface)
                                .foregroundStyle(NeuroTheme.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.border, lineWidth: 1))
                        }
                    }

                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .padding(10)
                            .background(NeuroTheme.surface)
                            .foregroundStyle(NeuroTheme.amber)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.amber.opacity(0.4), lineWidth: 1))
                    }
                    .accessibilityLabel("Delete all measurement history")
                }

                // Session Timeline List
                Text("SESSION TIMELINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeuroTheme.textSecondary)

                ForEach(filteredSessions) { session in
                    sessionCard(session)
                }
            }
            .padding(18)
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .sheet(item: $selectedSessionForDetail) { session in
            SessionDetailInspectorSheet(session: session, platformStore: platformStore)
        }
        .sheet(isPresented: $showingComparisonSheet) {
            if let a = compareSessionA ?? filteredSessions.first,
               let b = compareSessionB ?? filteredSessions.dropFirst().first {
                SessionComparisonSheet(sessionA: a, sessionB: b, allSessions: filteredSessions)
            }
        }
        .alert("Delete All Measurement History?", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Sessions", role: .destructive) {
                platformStore.deleteAllMeasurementHistory()
                exportedCSVURL = nil
                exportedJSONURL = nil
            }
        } message: {
            Text("This permanently erases all stored sessions from the encrypted local vault. This action cannot be undone.")
        }
    }

    private var compareSubtitle: String {
        if let a = compareSessionA, let b = compareSessionB {
            return "Selected \(a.id.uuidString.prefix(6)) vs \(b.id.uuidString.prefix(6))"
        }
        return "Compare gain, SPV °/s, calibration fit, and quality gates across any two runs."
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? NeuroTheme.teal : NeuroTheme.background)
                .foregroundStyle(isSelected ? NeuroTheme.background : NeuroTheme.textSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? NeuroTheme.teal : NeuroTheme.border, lineWidth: 1))
        }
    }

    private func sessionCard(_ session: PersistentMeasurementSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.didAbstain ? NeuroTheme.amber : NeuroTheme.teal)
                        .frame(width: 8, height: 8)
                    Text(session.didAbstain ? "ABSTAIN · INSUFFICIENT QUALITY" : "MEASURED · \(session.passedCheckCount)/\(session.totalCheckCount) GATES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(session.didAbstain ? NeuroTheme.amber : NeuroTheme.teal)
                }
                Spacer()
                Text(session.provenanceRaw)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(NeuroTheme.background)
                    .foregroundStyle(session.isRealLiveSession ? NeuroTheme.teal : NeuroTheme.amber)
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                if session.didAbstain {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NO NUMERICAL OUTPUT")
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(NeuroTheme.amber)
                        Text(session.abstentionReasons.first ?? "Failed signal quality gate")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OKN GAIN")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                            Text(String(format: "%.2f", session.oknGain ?? 0.0))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(NeuroTheme.teal)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SLOW PHASE (SPV)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                            Text(String(format: "%.1f °/s", session.slowPhaseVelocityDegPerSec ?? 0.0))
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VALID FRAMES")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                            Text(String(format: "%.0f%%", session.validFramePercentage))
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(NeuroTheme.textPrimary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.testCategory.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(NeuroTheme.textPrimary)
                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
            }

            if !session.userEnteredNotes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(NeuroTheme.textSecondary)
                    Text("User Note (unverified): \(session.userEnteredNotes)")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(8)
                .background(NeuroTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Button {
                    selectedSessionForDetail = session
                } label: {
                    Label("Inspect & Note", systemImage: "magnifyingglass")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NeuroTheme.background)
                        .foregroundStyle(NeuroTheme.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    if compareSessionA == nil || compareSessionA?.id == session.id {
                        compareSessionA = session
                    } else {
                        compareSessionB = session
                        showingComparisonSheet = true
                    }
                } label: {
                    Label("Select for Compare", systemImage: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NeuroTheme.background)
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button(role: .destructive) {
                    platformStore.deleteSession(id: session.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(NeuroTheme.amber)
                }
                .accessibilityLabel("Delete session")
            }
        }
        .padding(14)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NeuroTheme.border, lineWidth: 1))
    }
}

// MARK: - SESSION DETAIL INSPECTOR & USER NOTE EDITOR

struct SessionDetailInspectorSheet: View {
    let session: PersistentMeasurementSession
    let platformStore: PlatformServicesStore
    @Environment(\.dismiss) private var dismiss
    @State private var editableNote: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Provenance & Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SESSION ID · \(session.id.uuidString)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Text(session.testCategory.rawValue)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(NeuroTheme.textPrimary)
                        Text("\(session.timestamp.formatted(date: .complete, time: .standard)) · \(session.deviceModel) · \(session.analysisVersion)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                    }

                    // Compact Eye-Yaw Trace Chart
                    if !session.compactYawTraceDeg.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CALIBRATED EYE-YAW TRACE (DEGREES)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                            Chart {
                                ForEach(Array(session.compactYawTraceDeg.enumerated()), id: \.offset) { idx, deg in
                                    let t = idx < session.compactYawTimeSec.count ? session.compactYawTimeSec[idx] : Double(idx) * 0.08
                                    LineMark(
                                        x: .value("Time (s)", t),
                                        y: .value("Eye Yaw (°)", deg)
                                    )
                                    .foregroundStyle(session.didAbstain ? NeuroTheme.amber : NeuroTheme.teal)
                                }
                            }
                            .frame(height: 150)
                        }
                        .padding(14)
                        .background(NeuroTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Structured Metrics Grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEASURED SIGNAL METRICS (IMMUTABLE)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)

                        metricRow("Outcome", session.didAbstain ? "ABSTAIN (Unreliable Signal)" : "MEASURED")
                        metricRow("Slow-Phase Velocity", session.didAbstain ? "ABSTAIN (Not shown)" : String(format: "%.2f °/s", session.slowPhaseVelocityDegPerSec ?? 0))
                        metricRow("Optokinetic Gain", session.didAbstain ? "ABSTAIN (Not shown)" : String(format: "%.2f", session.oknGain ?? 0))
                        metricRow("Calibration Fit (RMS)", String(format: "%.2f° (Accepted: %@)", session.calibrationRMSDeg, session.calibrationAccepted ? "YES" : "NO"))
                        metricRow("Viewing Distance", String(format: "%.1f cm", session.meanDistanceCm))
                        metricRow("Valid Frame %", String(format: "%.1f%% (%d/%d)", session.validFramePercentage, session.validFrames, session.totalFrames))
                        metricRow("Unsmoothed Tracking Noise", String(format: "%.2f°", session.trackingNoiseDeg))
                        metricRow("Head Stability (95th %)", String(format: "%.2f°", session.maxHeadMotionDeg))
                        if let loc = session.locationTagDescription {
                            metricRow("Contextual Location Tag", loc)
                        }
                    }
                    .padding(14)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Separated User-Entered Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("USER-ENTERED NOTES (SEPARATED FROM MEASURED DATA)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.amber)
                        TextField("Add context (e.g., 'After 14h shift', 'Bright room')", text: $editableNote, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(10)
                            .background(NeuroTheme.background)
                            .foregroundStyle(NeuroTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            platformStore.updateSessionUserNote(sessionID: session.id, newNote: editableNote)
                            dismiss()
                        } label: {
                            Text("Save User Note")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(14)
                    .background(NeuroTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(18)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NeuroTheme.teal)
                }
            }
            .onAppear {
                editableNote = session.userEnteredNotes
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(NeuroTheme.textPrimary)
        }
    }
}

// MARK: - SESSION COMPARISON SHEET

struct SessionComparisonSheet: View {
    @State var sessionA: PersistentMeasurementSession
    @State var sessionB: PersistentMeasurementSession
    let allSessions: [PersistentMeasurementSession]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("SIDE-BY-SIDE SESSION COMPARISON")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)

                    ComparisonRowView(
                        metric: "Timestamp",
                        valA: sessionA.timestamp.formatted(date: .abbreviated, time: .shortened),
                        valB: sessionB.timestamp.formatted(date: .abbreviated, time: .shortened)
                    )
                    ComparisonRowView(
                        metric: "Status",
                        valA: sessionA.didAbstain ? "ABSTAIN" : "MEASURED",
                        valB: sessionB.didAbstain ? "ABSTAIN" : "MEASURED"
                    )
                    ComparisonRowView(
                        metric: "OKN Gain",
                        valA: sessionA.didAbstain ? "—" : String(format: "%.2f", sessionA.oknGain ?? 0),
                        valB: sessionB.didAbstain ? "—" : String(format: "%.2f", sessionB.oknGain ?? 0)
                    )
                    ComparisonRowView(
                        metric: "Slow-Phase Velocity",
                        valA: sessionA.didAbstain ? "—" : String(format: "%.1f °/s", sessionA.slowPhaseVelocityDegPerSec ?? 0),
                        valB: sessionB.didAbstain ? "—" : String(format: "%.1f °/s", sessionB.slowPhaseVelocityDegPerSec ?? 0)
                    )
                    ComparisonRowView(
                        metric: "Calibration RMS",
                        valA: String(format: "%.2f°", sessionA.calibrationRMSDeg),
                        valB: String(format: "%.2f°", sessionB.calibrationRMSDeg)
                    )
                    ComparisonRowView(
                        metric: "Tracking Noise",
                        valA: String(format: "%.2f°", sessionA.trackingNoiseDeg),
                        valB: String(format: "%.2f°", sessionB.trackingNoiseDeg)
                    )
                    ComparisonRowView(
                        metric: "Valid Frames",
                        valA: String(format: "%.0f%%", sessionA.validFramePercentage),
                        valB: String(format: "%.0f%%", sessionB.validFramePercentage)
                    )
                    ComparisonRowView(
                        metric: "Gates Passed",
                        valA: "\(sessionA.passedCheckCount)/\(sessionA.totalCheckCount)",
                        valB: "\(sessionB.passedCheckCount)/\(sessionB.totalCheckCount)"
                    )
                }
                .padding(18)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Compare Sessions")
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

private struct ComparisonRowView: View {
    let metric: String
    let valA: String
    let valB: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.textSecondary)
            HStack {
                Text(valA)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(NeuroTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valB)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(NeuroTheme.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - TAB 4: EXPERIMENTAL DRIVING SAFETY & SIMULATED INTERLOCK RESEARCH MODULE

struct DrivingResearchModuleView: View {
    let platformStore: PlatformServicesStore
    let onLaunchExperimentalScan: (ExperimentalConditionFactor) -> Void

    @State private var selectedCondition: ExperimentalConditionFactor = .baselineWellRested
    @State private var selectedFixture: InterlockSimulationFixture = .cleanPassSignal
    @State private var showingRegulatoryArchitectureSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Explicit Research Banner (Never claims BAC, intoxication diagnosis, or Safe to Drive)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "flask.fill")
                            .foregroundStyle(NeuroTheme.amber)
                        Text("EXPERIMENTAL DRIVING-SAFETY RESEARCH")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.amber)
                    }
                    Text("Oculomotor Research & Safety Architecture")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(NeuroTheme.textPrimary)
                    Text("NeuroAssist is a research prototype. It does NOT determine blood alcohol concentration (BAC), diagnose intoxication, identify specific drugs, or certify that anyone is 'SAFE TO DRIVE'.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.amber.opacity(0.55), lineWidth: 1))

                // Scientific Non-Specificity Disclosure
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCIENTIFIC DISTINCTION · NON-SPECIFICITY OF EYE MOVEMENTS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)
                    Text("Long-term research investigates whether smartphone oculomotor signals (optokinetic slow-phase velocity, pursuit gain, and gaze stability) change across conditions such as:")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        bulletRow("Alcohol-related or drug-related pharmacodynamic studies")
                        bulletRow("Extended wakefulness, fatigue, and circadian drowsiness")
                        bulletRow("Abnormal visual, vestibular, or neurological function")
                        bulletRow("Reduced visual tracking performance or optical glare")
                    }

                    Text("Important: Eye-movement changes are non-specific. An altered measurement or an ABSTAIN result is never proof of intoxication, and a normal-range measurement is never authorization to drive.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(NeuroTheme.amber)
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // Experimental Research Recording Workflow
                VStack(alignment: .leading, spacing: 12) {
                    Text("RUN EXPERIMENTAL RESEARCH CAPTURE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)

                    Picker("Research Condition Tag", selection: $selectedCondition) {
                        ForEach(ExperimentalConditionFactor.allCases) { factor in
                            Text(factor.rawValue).tag(factor)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(NeuroTheme.teal)

                    Button {
                        onLaunchExperimentalScan(selectedCondition)
                    } label: {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Record Research Session (\(selectedCondition.rawValue))")
                                .fontWeight(.bold)
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(NeuroTheme.teal)
                        .foregroundStyle(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Three Explicit Outcome States Legend
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THREE DISTINCT RESEARCH OUTCOME STATES:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        outcomeLegendRow(color: NeuroTheme.teal, title: "1. Measurement Completed", desc: "All 11 signal-quality gates passed; reports SPV (°/s) & 95% CI without a 'Safe to Drive' badge.")
                        outcomeLegendRow(color: NeuroTheme.amber, title: "2. Measurement Unreliable — ABSTAIN", desc: "Signal failed quality gates; zero numbers shown; never interpreted as impairment or normality.")
                        outcomeLegendRow(color: NeuroTheme.textSecondary, title: "3. Research Observation Requiring Validation", desc: "Deviation vs. personal reference band logged for IRB study review only.")
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // Future Ignition-Interlock Simulation Sandbox (Explicitly Simulated, Never Connected to Real Vehicle Controls)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SIMULATED PARTNER & INTERLOCK SANDBOX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.amber)
                        Spacer()
                        Text("SIMULATED FIXTURE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(NeuroTheme.amber.opacity(0.2))
                            .foregroundStyle(NeuroTheme.amber)
                            .clipShape(Capsule())
                    }

                    Text("Tests how a future fleet or automotive partner interface would consume structured readiness payloads. Does NOT connect to real vehicle ignition or immobilize any vehicle.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)

                    Picker("Test Fixture", selection: $selectedFixture) {
                        ForEach(InterlockSimulationFixture.allCases) { fix in
                            Text(fix.rawValue).tag(fix)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(NeuroTheme.amber)

                    interlockFixtureOutputCard(selectedFixture)

                    Button {
                        showingRegulatoryArchitectureSheet = true
                    } label: {
                        Label("View Clinical, Regulatory, Legal & Cybersecurity Requirements", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(NeuroTheme.background)
                            .foregroundStyle(NeuroTheme.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroTheme.border, lineWidth: 1))
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))
            }
            .padding(18)
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showingRegulatoryArchitectureSheet) {
            InterlockRegulatoryRequirementsSheet()
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(NeuroTheme.teal)
            Text(text)
                .font(.system(.caption, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
        }
    }

    private func outcomeLegendRow(color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(NeuroTheme.textPrimary)
                Text(desc)
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(NeuroTheme.textSecondary)
            }
        }
    }

    private func interlockFixtureOutputCard(_ fixture: InterlockSimulationFixture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIMULATED PAYLOAD PREVIEW (NO VEHICLE HARDWARE LINK)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(NeuroTheme.amber)
            switch fixture {
            case .cleanPassSignal:
                Text("status: MEASUREMENT_COMPLETED\ncalibration_rms_deg: 0.29\nokn_gain: 0.81 (95% CI: 0.75–0.86)\nvehicle_action: NONE (Advisory research log only; never displays 'SAFE TO DRIVE')")
            case .uncalibratedOrNoisyAbstain:
                Text("status: ABSTAIN_INSUFFICIENT_SIGNAL\nfailed_gate: HEAD_ROTATION_95TH (3.6° > 2.0°)\nnumeric_output: NULL\nvehicle_action: PROMPT_RETAKE_OR_PAUSE (Never locks ignition on optical/tracking artifact)")
            case .alteredGainObservation:
                Text("status: RESEARCH_OBSERVATION_REQUIRING_VALIDATION\nokn_gain: 0.52 (Below personal reference band 0.68–0.88)\nvehicle_action: SUGGEST_REST_OR_ALTERNATIVE_TRANSPORT (Non-diagnostic)")
            case .emergencyBypassOverride:
                Text("status: EMERGENCY_HUMAN_OVERRIDE_ACTIVE\nreason: User-declared emergency / medical transport\nvehicle_action: IMMEDIATE_UNRESTRICTED_BYPASS (Mandatory safety-critical fail-safe)")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(NeuroTheme.textPrimary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct InterlockRegulatoryRequirementsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    reqSection("1. Clinical & Scientific Validation", "Prospective multi-center trials establishing sensitivity, specificity, and confounder invariance across age, corrective lenses, strabismus, benign congenital nystagmus, and lighting.")
                    reqSection("2. Regulatory & Legal Classification", "FDA De Novo / 510(k) or NHTSA / state ignition-interlock certification (e.g., NHTSA Model Specifications) before any safety-critical claim or vehicle coupling.")
                    reqSection("3. Accessibility & Ophthalmic Accommodations", "Mandatory alternative pathways for drivers with monocular vision, amblyopia, ptosis, scleral lenses, or physiological end-point nystagmus.")
                    reqSection("4. False-Positive & False-Negative Hazard Mitigation", "Optical glare or tracking loss (ABSTAIN) must never strand a driver in an unsafe location; normal eye pursuit must never override breath/blood alcohol interlocks.")
                    reqSection("5. Mandatory Emergency Override", "Unconditional human override in medical or environmental emergencies so a software or camera fault never prevents emergency evacuation.")
                    reqSection("6. Automotive Cybersecurity (ISO/SAE 21434)", "Hardware-isolated secure enclave signing, replay-attack prevention, and zero raw biometric video transmission over CAN/automotive buses.")
                }
                .padding(18)
            }
            .background(NeuroTheme.background.ignoresSafeArea())
            .navigationTitle("Interlock Pre-Requisites")
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

    private func reqSection(_ title: String, _ bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(NeuroTheme.teal)
            Text(bodyText)
                .font(.system(.caption, design: .default))
                .foregroundStyle(NeuroTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
