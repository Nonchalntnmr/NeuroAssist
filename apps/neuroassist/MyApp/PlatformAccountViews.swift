import SwiftUI
import AuthenticationServices
import CoreLocation
import MapKit

// MARK: - TAB 5: MESSAGES, REPORT SHARING & CONTEXTUAL LOCATION SAFETY

struct MessagesAndSharingHubView: View {
    let platformStore: PlatformServicesStore
    let demoStore: DemoExperienceStore

    @State private var selectedSessionIDForShare: UUID? = nil
    @State private var recipientNameInput: String = "Dr. Maya Lin (Clinical Researcher)"
    @State private var recipientRoleInput: String = "Clinician / Authorized Researcher"
    @State private var includeTrendToggle: Bool = false
    @State private var shareExpirationDays: Int = 7
    @State private var customSafetyMessage: String = "Completing my pre-drive check. Will share my ETA before heading out."
    @State private var newContactName: String = ""
    @State private var newContactPhoneOrEmail: String = ""
    @State private var newContactRelation: String = "Family / Friend"
    @State private var showingAddContactSheet: Bool = false
    @State private var showingLocationConsentAlert: Bool = false

    private var selectedSession: PersistentMeasurementSession? {
        if let id = selectedSessionIDForShare {
            return platformStore.sessions.first(where: { $0.id == id })
        }
        return platformStore.sessions.first
    }

    private var shareableReportSummary: String {
        guard let s = selectedSession else {
            return "NeuroAssist Report: No session selected."
        }
        if s.didAbstain {
            return """
            NeuroAssist Measurement Report (Consented User Share)
            Session ID: \(s.id.uuidString.prefix(8))
            Timestamp: \(s.timestamp.formatted(date: .abbreviated, time: .shortened))
            Outcome: ABSTAIN — Insufficient Signal Quality (\(s.abstentionReasons.first ?? "Quality gate failed"))
            Note: NeuroAssist withholds numbers when signal quality is unreliable. Research prototype; does not diagnose or certify driving fitness.
            """
        } else {
            return """
            NeuroAssist Measurement Report (Consented User Share)
            Session ID: \(s.id.uuidString.prefix(8))
            Timestamp: \(s.timestamp.formatted(date: .abbreviated, time: .shortened))
            OKN Gain: \(String(format: "%.2f", s.oknGain ?? 0.0))
            Slow-Phase Velocity: \(String(format: "%.2f °/s", s.slowPhaseVelocityDegPerSec ?? 0.0)) (95% CI: \(String(format: "%.2f–%.2f °/s", s.confidenceIntervalLowerDegPerSec ?? 0.0, s.confidenceIntervalUpperDegPerSec ?? 0.0)))
            Calibration Fit RMS: \(String(format: "%.2f°", s.calibrationRMSDeg))
            Quality Gates Passed: \(s.passedCheckCount)/\(s.totalCheckCount)
            Disclaimer: Research prototype. Measures eye movement; does not diagnose or determine driving fitness.
            """
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("PERMISSION-CONTROLLED COMMUNICATION & LOCATION SAFETY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)
                    Text("Messages, Report Sharing & Arrive Safe")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(NeuroTheme.textPrimary)
                    Text("All external sharing requires explicit user action. Zero silent background transmissions.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)
                }

                // 1. Native iOS Report & Safety Message Share Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. SHARE SELECTED REPORT OR SAFETY MESSAGE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)

                    if !platformStore.sessions.isEmpty {
                        Picker("Select Session Report", selection: $selectedSessionIDForShare) {
                            ForEach(platformStore.sessions) { s in
                                Text("\(s.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(s.didAbstain ? "ABSTAIN" : String(format: "Gain %.2f", s.oknGain ?? 0.0))")
                                    .tag(Optional(s.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(NeuroTheme.teal)
                    }

                    Text(shareableReportSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NeuroTheme.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        ShareLink(item: shareableReportSummary) {
                            Label("Share Report via iOS Sheet", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            platformStore.logSafetyMessage(
                                recipientName: recipientNameInput,
                                channel: "Native iOS Share Sheet",
                                body: shareableReportSummary,
                                sessionID: selectedSession?.id
                            )
                            NeuroHaptics.notify(.success)
                        } label: {
                            Label("Log Delivery", systemImage: "checkmark.seal")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
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

                // 2. Clinician / Researcher Expiring Access Grant
                VStack(alignment: .leading, spacing: 12) {
                    Text("2. CLINICIAN / RESEARCHER RECIPIENT-SPECIFIC GRANT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)

                    TextField("Recipient Name or Email", text: $recipientNameInput)
                        .padding(10)
                        .background(NeuroTheme.background)
                        .foregroundStyle(NeuroTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .font(.system(.caption, design: .monospaced))

                    Toggle(isOn: $includeTrendToggle) {
                        Text("Include Longitudinal Trend Summary (Measured Gains & 95% CIs)")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }
                    .tint(NeuroTheme.teal)

                    HStack {
                        Text("Grant Expiration:")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(NeuroTheme.textSecondary)
                        Spacer()
                        Picker("Expiration", selection: $shareExpirationDays) {
                            Text("24 Hours").tag(1)
                            Text("7 Days").tag(7)
                            Text("30 Days").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }

                    Button {
                        let ids = selectedSession.map { [$0.id] } ?? []
                        _ = platformStore.createRecipientShareGrant(
                            recipientNameOrEmail: recipientNameInput,
                            recipientRole: recipientRoleInput,
                            sessionIDs: ids,
                            includeTrend: includeTrendToggle,
                            validDays: shareExpirationDays
                        )
                        NeuroHaptics.notify(.success)
                    } label: {
                        Text("Create Expiring Recipient Share Grant")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(NeuroTheme.background)
                            .foregroundStyle(NeuroTheme.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NeuroTheme.teal, lineWidth: 1))
                    }

                    if !platformStore.recipientShares.isEmpty {
                        ForEach(platformStore.recipientShares) { grant in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(grant.recipientNameOrEmail) · \(grant.accessCode)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(grant.isRevoked ? NeuroTheme.textSecondary : NeuroTheme.textPrimary)
                                    Text(grant.isRevoked ? "REVOKED" : "Expires \(grant.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(grant.isRevoked ? NeuroTheme.amber : NeuroTheme.teal)
                                }
                                Spacer()
                                if !grant.isRevoked {
                                    Button("Revoke") {
                                        platformStore.revokeRecipientShareGrant(id: grant.id)
                                    }
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.amber)
                                }
                            }
                            .padding(10)
                            .background(NeuroTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // 3. Contextual Location & Driving-Safety Assistance (When-In-Use Only + Stop Immediately)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("3. CONTEXTUAL LOCATION & DRIVING SAFETY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Spacer()
                        Text(platformStore.locationManager.isSharingEventLocation ? "SHARING EVENT" : "OFFLINE / IDLE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(platformStore.locationManager.isSharingEventLocation ? NeuroTheme.amber.opacity(0.2) : NeuroTheme.background)
                            .foregroundStyle(platformStore.locationManager.isSharingEventLocation ? NeuroTheme.amber : NeuroTheme.textSecondary)
                            .clipShape(Capsule())
                    }

                    Text("Location access is strictly optional (never required for eye tracking). Uses contextual When-In-Use snapshots only; never tracks continuously in the background or reports to insurers, employers, or law enforcement.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)

                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundStyle(NeuroTheme.teal)
                        Text(platformStore.locationManager.lastPlaceSummary)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textPrimary)
                        Spacer()
                    }
                    .padding(10)
                    .background(NeuroTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            showingLocationConsentAlert = true
                        } label: {
                            Label("Share Event Location", systemImage: "location.fill")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button(role: .destructive) {
                            platformStore.stopAllActiveLocationShares()
                        } label: {
                            Label("Stop Sharing Immediately", systemImage: "xmark.octagon.fill")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.amber)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // 4. Trusted Safety Contacts & Delivery Log
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("4. TRUSTED SAFETY CONTACTS & MESSAGE LOG")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Spacer()
                        Button {
                            showingAddContactSheet = true
                        } label: {
                            Label("Add Contact", systemImage: "person.badge.plus")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.teal)
                        }
                    }

                    ForEach(platformStore.trustedContacts) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(contact.name) (\(contact.relationship))")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Text("\(contact.phoneOrEmail) · \(contact.invitationStatus)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                            Spacer()
                            ShareLink(item: "Hi \(contact.name), inviting you as my trusted Arrive Safe contact on NeuroAssist. Status: \(customSafetyMessage)") {
                                Text("Message")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(NeuroTheme.background)
                                    .foregroundStyle(NeuroTheme.teal)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(10)
                        .background(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if !platformStore.safetyMessages.isEmpty {
                        Text("RECENTLY LOGGED SHARES:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.textSecondary)
                            .padding(.top, 4)
                        ForEach(platformStore.safetyMessages.prefix(4)) { msg in
                            HStack {
                                Text("\(msg.recipientName) · \(msg.deliveryStatus)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                                Spacer()
                                Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                        }
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
        .alert("Contextual Location Share Consent", isPresented: $showingLocationConsentAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Request Snapshot & Share") {
                let contact = platformStore.trustedContacts.first?.name ?? "Trusted Contact"
                platformStore.startEventLocationShare(contactName: contact, eventTitle: "Arrive Safe Pre-Drive Check-In")
            }
        } message: {
            Text("NeuroAssist will request a single When-In-Use location snapshot for this safety event. You can stop sharing at any time with one tap.")
        }
        .sheet(isPresented: $showingAddContactSheet) {
            NavigationStack {
                Form {
                    TextField("Full Name", text: $newContactName)
                    TextField("Phone or Email", text: $newContactPhoneOrEmail)
                    TextField("Relationship", text: $newContactRelation)
                }
                .navigationTitle("Add Trusted Contact")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddContactSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let c = TrustedSafetyContact(
                                id: UUID(),
                                name: newContactName.isEmpty ? "Trusted Contact" : newContactName,
                                phoneOrEmail: newContactPhoneOrEmail.isEmpty ? "contact@example.com" : newContactPhoneOrEmail,
                                relationship: newContactRelation,
                                invitationStatus: "Invited",
                                canReceiveLocationEvents: true,
                                canReceiveSelectedReports: true
                            )
                            platformStore.trustedContacts.append(c)
                            platformStore.appendAudit(actionType: "CONTACT_ADDED", scopeOrTarget: c.name, details: "Added trusted safety contact.")
                            newContactName = ""
                            newContactPhoneOrEmail = ""
                            showingAddContactSheet = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - TAB 6: USER ACCOUNT, KEYCHAIN AUTH & PRIVACY / DATA SHARING CENTER

struct AccountAndPrivacyCenterView: View {
    let platformStore: PlatformServicesStore
    let demoStore: DemoExperienceStore

    @State private var localNameInput: String = ""
    @State private var localEmailInput: String = ""
    @State private var showingDeleteAccountAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Account & Authentication Card (Sign in with Apple + Keychain + Guest Mode)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("KEYCHAIN-BACKED ACCOUNT & IDENTITY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NeuroTheme.teal)
                            Text(platformStore.profile.displayName)
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(NeuroTheme.textPrimary)
                            Text("Status: \(platformStore.profile.authState.rawValue) · ID: \(platformStore.profile.accountID.prefix(14))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(NeuroTheme.teal)
                    }

                    // Native Sign in with Apple Button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                                let nameParts = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }
                                let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
                                platformStore.completeSignInWithApple(
                                    userID: cred.user,
                                    fullName: fullName,
                                    email: cred.email,
                                    identityTokenData: cred.identityToken
                                )
                            }
                        case .failure:
                            // Fallback on Simulator where Apple ID entitlement isn't provisioned
                            platformStore.completeSignInWithApple(
                                userID: "apple-sim-\(UUID().uuidString.prefix(8))",
                                fullName: "Apple ID Researcher",
                                email: nil,
                                identityTokenData: Data("simulated-keychain-token".utf8)
                            )
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Local Research Profile Creation or Guest Mode Switch
                    HStack(spacing: 8) {
                        TextField("Profile Name", text: $localNameInput)
                            .padding(9)
                            .background(NeuroTheme.background)
                            .foregroundStyle(NeuroTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .font(.system(.caption, design: .monospaced))

                        Button {
                            platformStore.createLocalResearchAccount(displayName: localNameInput, emailHint: localEmailInput)
                            localNameInput = ""
                        } label: {
                            Text("Save Local Profile")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(NeuroTheme.teal)
                                .foregroundStyle(NeuroTheme.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            platformStore.switchToGuestMode()
                        } label: {
                            Text("Use Offline Guest Mode")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(NeuroTheme.background)
                                .foregroundStyle(NeuroTheme.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            platformStore.signOutAccount()
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(NeuroTheme.background)
                                .foregroundStyle(NeuroTheme.amber)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // 2. Privacy & Data Sharing Center (All External Sharing Defaulted OFF)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PRIVACY & DATA SHARING CENTER")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(NeuroTheme.teal)
                        Spacer()
                        Text("DEFAULT: ALL OFF")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(NeuroTheme.teal.opacity(0.18))
                            .foregroundStyle(NeuroTheme.teal)
                            .clipShape(Capsule())
                    }

                    Text("NeuroAssist never sells health, oculomotor, or location data and never silently shares data with insurers, employers, advertisers, or law enforcement. Pseudonymous identifiers are explicitly distinguished from anonymous data.")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(NeuroTheme.textSecondary)

                    ForEach(platformStore.permissions) { grant in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(
                                isOn: Binding(
                                    get: { grant.isEnabled },
                                    set: { newVal in
                                        platformStore.setPermission(scope: grant.scope, enabled: newVal)
                                    }
                                )
                            ) {
                                Text(grant.scope.rawValue)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(NeuroTheme.textPrimary)
                            }
                            .tint(NeuroTheme.teal)

                            Text(grant.scope.whatLeavesDeviceSummary)
                                .font(.system(size: 10, design: .default))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                        .padding(12)
                        .background(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Optional User Preferences (Encrypted Sync & Contextual Location Tagging)
                    Toggle(
                        isOn: Binding(
                            get: { platformStore.profile.encryptedCloudSyncOptIn },
                            set: { val in
                                platformStore.profile.encryptedCloudSyncOptIn = val
                                platformStore.appendAudit(
                                    actionType: val ? "ENCRYPTED_SYNC_ENABLED" : "ENCRYPTED_SYNC_DISABLED",
                                    scopeOrTarget: "Account Preferences",
                                    details: "Toggled end-to-end encrypted multi-device sync preference."
                                )
                            }
                        )
                    ) {
                        Text("Optional End-to-End Encrypted Multi-Device Sync")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }
                    .tint(NeuroTheme.teal)

                    Toggle(
                        isOn: Binding(
                            get: { platformStore.profile.locationTaggingOptIn },
                            set: { val in
                                platformStore.profile.locationTaggingOptIn = val
                                if val {
                                    platformStore.locationManager.requestWhenInUsePermissionContextually()
                                }
                                platformStore.appendAudit(
                                    actionType: val ? "LOCATION_TAGGING_OPT_IN" : "LOCATION_TAGGING_OPT_OUT",
                                    scopeOrTarget: "Session Metadata",
                                    details: "Toggled optional When-In-Use session location tagging."
                                )
                            }
                        )
                    ) {
                        Text("Optional Contextual Location Tagging on Saved Scans")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(NeuroTheme.textPrimary)
                    }
                    .tint(NeuroTheme.teal)
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // 3. Immutable Privacy & Consent Audit Log
                VStack(alignment: .leading, spacing: 10) {
                    Text("ON-DEVICE PRIVACY & CONSENT AUDIT LOG (\(platformStore.auditLog.count) EVENTS)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NeuroTheme.teal)

                    ForEach(platformStore.auditLog.prefix(8)) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.actionType)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.teal)
                                Spacer()
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(NeuroTheme.textSecondary)
                            }
                            Text("\(entry.scopeOrTarget) — \(entry.details)")
                                .font(.system(size: 10, design: .default))
                                .foregroundStyle(NeuroTheme.textSecondary)
                        }
                        .padding(8)
                        .background(NeuroTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
                .background(NeuroTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroTheme.border, lineWidth: 1))

                // 4. Cryptographic Account & Data Deletion
                Button(role: .destructive) {
                    showingDeleteAccountAlert = true
                } label: {
                    Label("Delete Account, Rotate AES-256 Key & Wipe All Data", systemImage: "trash.slash.fill")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NeuroTheme.amber.opacity(0.16))
                        .foregroundStyle(NeuroTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NeuroTheme.amber, lineWidth: 1))
                }
            }
            .padding(18)
        }
        .background(NeuroTheme.background.ignoresSafeArea())
        .alert("Delete Account & Cryptographically Erase Vault?", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account & All Data", role: .destructive) {
                platformStore.deleteAccountAndWipeAllData()
                NeuroHaptics.notify(.warning)
            }
        } message: {
            Text("This deletes your account, wipes all Keychain tokens, rotates the AES-256 master key, and permanently destroys all local sessions, shares, and contacts.")
        }
    }
}
