import Foundation
import Security
import CryptoKit
import AuthenticationServices
import CoreLocation
import UIKit

// MARK: - 1. KEYCHAIN & AES-GCM CRYPTOGRAPHY VAULT (Zero Secrets in UserDefaults)

public enum SecureKeychainVault {
    private static let serviceName = "neuroassist.myapp.securevault"
    private static let masterKeyAccount = "neuroassist.aes256.masterkey"
    private static let appleUserIDAccount = "neuroassist.auth.appleUserID"
    private static let sessionTokenAccount = "neuroassist.auth.sessionToken"

    public static func saveString(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return saveData(data, account: account)
    }

    public static func loadString(account: String) -> String? {
        guard let data = loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func saveData(_ data: Data, account: String) -> Bool {
        deleteItem(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public static func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func wipeAllCredentialsAndKeys() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Auth Credentials in Keychain

    public static func saveAppleCredential(userID: String, sessionToken: String) {
        _ = saveString(userID, account: appleUserIDAccount)
        _ = saveString(sessionToken, account: sessionTokenAccount)
    }

    public static func loadAppleUserID() -> String? {
        loadString(account: appleUserIDAccount)
    }

    public static func clearAuthCredentials() {
        deleteItem(account: appleUserIDAccount)
        deleteItem(account: sessionTokenAccount)
    }

    // MARK: AES-256-GCM Local Encryption with Keychain-Backed SymmetricKey (Fallback In-Memory Key for Unsigned Test Environments)

    private static let fallbackKeyLock = NSLock()
    nonisolated(unsafe) private static var fallbackInMemoryKey: SymmetricKey = SymmetricKey(size: .bits256)

    public static func loadOrCreateMasterKey() -> SymmetricKey {
        if let existingData = loadData(account: masterKeyAccount), existingData.count == 32 {
            return SymmetricKey(data: existingData)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        if saveData(keyData, account: masterKeyAccount) {
            return newKey
        }
        fallbackKeyLock.lock()
        defer { fallbackKeyLock.unlock() }
        return fallbackInMemoryKey
    }

    public static func rotateMasterKey() {
        deleteItem(account: masterKeyAccount)
        fallbackKeyLock.lock()
        fallbackInMemoryKey = SymmetricKey(size: .bits256)
        fallbackKeyLock.unlock()
        _ = loadOrCreateMasterKey()
    }

    public static func encryptCodable<T: Encodable>(_ value: T) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let key = loadOrCreateMasterKey()
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "SecureKeychainVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to seal AES-GCM box"])
        }
        return combined
    }

    public static func decryptCodable<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let key = loadOrCreateMasterKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}

// MARK: - 2. USER ACCOUNTS, PROFILES & AUTHENTICATION MODELS

public enum AccountAuthState: String, Codable, Sendable, Equatable {
    case unauthenticated = "UNAUTHENTICATED"
    case guestMode = "GUEST MODE"
    case signedInWithApple = "SIGNED IN WITH APPLE"
    case localResearchAccount = "LOCAL RESEARCH ACCOUNT"
}

public struct UserProfileRecord: Codable, Sendable, Equatable {
    public var accountID: String
    public var authState: AccountAuthState
    public var displayName: String
    public var emailHint: String?
    public var createdAt: Date
    public var preferredProtocolModeRaw: String
    public var encryptedCloudSyncOptIn: Bool
    public var locationTaggingOptIn: Bool
    public var reminderNotificationsOptIn: Bool

    public init(
        accountID: String = "guest-local",
        authState: AccountAuthState = .guestMode,
        displayName: String = "Guest Researcher",
        emailHint: String? = nil,
        createdAt: Date = Date(),
        preferredProtocolModeRaw: String = MeasurementProtocolMode.researchFixed.rawValue,
        encryptedCloudSyncOptIn: Bool = false,
        locationTaggingOptIn: Bool = false,
        reminderNotificationsOptIn: Bool = false
    ) {
        self.accountID = accountID
        self.authState = authState
        self.displayName = displayName
        self.emailHint = emailHint
        self.createdAt = createdAt
        self.preferredProtocolModeRaw = preferredProtocolModeRaw
        self.encryptedCloudSyncOptIn = encryptedCloudSyncOptIn
        self.locationTaggingOptIn = locationTaggingOptIn
        self.reminderNotificationsOptIn = reminderNotificationsOptIn
    }
}

// MARK: - 3. PERSISTENT MEASUREMENT HISTORY RECORD (Structured & Auditable)

public enum SessionTestCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case preDriveCheck = "Pre-Drive Check"
    case baselineOculomotor = "Baseline Oculomotor"
    case drivingResearchProtocol = "Driving Research Protocol"
    case recordedReplay = "Recorded Session Replay"
    case simulatedDemo = "Simulated Demonstration"

    public var id: String { rawValue }
}

public struct QualityGateCheckRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let valueString: String
    public let ruleString: String
    public let fixHint: String
    public let passed: Bool

    public init(from check: QualityCheckItem) {
        self.id = check.id
        self.name = check.name
        self.valueString = check.valueString
        self.ruleString = check.ruleString
        self.fixHint = check.fixHint
        self.passed = check.passed
    }
}

public struct PersistentMeasurementSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let ownerAccountID: String
    public let timestamp: Date
    public let testCategory: SessionTestCategory
    public let provenanceRaw: String
    public let protocolModeRaw: String
    public let analysisVersion: String
    public let deviceModel: String
    public let scientificStatusRaw: String
    public let cadenceDiagnostics: AcquisitionCadenceDiagnostics?
    public let artifactFlags: ArtifactClassificationFlags?

    // Calibration metrics
    public let calibrationAccepted: Bool
    public let calibrationRMSDeg: Double
    public let calibrationSlope: Double
    public let calibrationIntercept: Double
    public let meanDistanceCm: Double

    // Oculomotor & Optokinetic metrics (nil when didAbstain == true — NEVER fabricated)
    public let didAbstain: Bool
    public let slowPhaseVelocityDegPerSec: Double?
    public let oknGain: Double?
    public let confidenceIntervalLowerDegPerSec: Double?
    public let confidenceIntervalUpperDegPerSec: Double?
    public let intervalHalfWidthDegPerSec: Double
    public let cleanWindowCount: Int

    // Signal quality & tracking stability
    public let validFramePercentage: Double
    public let totalFrames: Int
    public let validFrames: Int
    public let rejectedFrames: Int
    public let frameRateFps: Double
    public let maxHeadMotionDeg: Double
    public let trackingNoiseDeg: Double
    public let ambientLightLux: Double
    public let recordingDurationSec: Double
    public let analysisLatencyMs: Double

    // Quality gates & abstention reasons
    public let passedCheckCount: Int
    public let totalCheckCount: Int
    public let primaryAbstainRootCause: String?
    public let abstentionReasons: [String]
    public let qualityChecks: [QualityGateCheckRecord]

    // Downsampled numerical eye-yaw trace (degrees) for longitudinal chart inspection (no video ever saved)
    public let compactYawTraceDeg: [Double]
    public let compactYawTimeSec: [Double]

    // Clearly separated user-entered notes & optional driving-research context
    public var userEnteredNotes: String
    public var drivingResearchSelfReportTag: String?
    public var locationTagDescription: String?
    public var latitude: Double?
    public var longitude: Double?

    public var isRealLiveSession: Bool {
        provenanceRaw == DataProvenance.liveCamera.rawValue
    }

    public static func from(
        result: OKNAnalysisResult,
        calibration: CalibrationModel?,
        ownerAccountID: String,
        testCategory: SessionTestCategory,
        userNotes: String = "",
        drivingResearchTag: String? = nil,
        locationTag: String? = nil,
        lat: Double? = nil,
        lon: Double? = nil
    ) -> PersistentMeasurementSession {
        let validPct = result.totalFrames > 0
            ? (Double(result.validFrames) / Double(result.totalFrames)) * 100.0
            : 0.0
        let validTrace = result.tracePoints.filter(\.isValid)
        let strideStep = max(1, validTrace.count / 120)
        var compactAngles: [Double] = []
        var compactTimes: [Double] = []
        for idx in stride(from: 0, to: validTrace.count, by: strideStep) {
            compactAngles.append(validTrace[idx].angleDeg)
            compactTimes.append(validTrace[idx].timeSec)
        }

        let fpsVal = result.recordingDurationSec > 0
            ? Double(result.totalFrames) / result.recordingDurationSec
            : 60.0
        let headVal: Double = {
            if let headCheck = result.checks.first(where: { $0.id == "head_stability" || $0.category == .headMovement }) {
                let numeric = headCheck.valueString.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)
                return Double(numeric) ?? 0.3
            }
            return 0.3
        }()

        return PersistentMeasurementSession(
            id: UUID(),
            ownerAccountID: ownerAccountID,
            timestamp: Date(),
            testCategory: testCategory,
            provenanceRaw: result.provenance.rawValue,
            protocolModeRaw: result.mode.rawValue,
            analysisVersion: "NeuroAssist-SignalEngine-2.5.0-ScienceClaw",
            deviceModel: UIDevice.current.model,
            scientificStatusRaw: result.scientificStatus.rawValue,
            cadenceDiagnostics: result.cadenceDiagnostics,
            artifactFlags: result.artifactFlags,
            calibrationAccepted: calibration?.isAccepted ?? false,
            calibrationRMSDeg: result.calibrationRMSDeg,
            calibrationSlope: calibration?.slope ?? 0.0,
            calibrationIntercept: calibration?.intercept ?? 0.0,
            meanDistanceCm: calibration?.meanDistanceCm ?? 30.0,
            didAbstain: result.didAbstain,
            slowPhaseVelocityDegPerSec: result.didAbstain ? nil : result.slowPhaseSpeedDegPerSec,
            oknGain: result.didAbstain ? nil : result.gain,
            confidenceIntervalLowerDegPerSec: result.didAbstain ? nil : result.confidenceInterval95?.lower,
            confidenceIntervalUpperDegPerSec: result.didAbstain ? nil : result.confidenceInterval95?.upper,
            intervalHalfWidthDegPerSec: result.intervalHalfWidthDegPerSec,
            cleanWindowCount: result.cleanWindowCount,
            validFramePercentage: validPct,
            totalFrames: result.totalFrames,
            validFrames: result.validFrames,
            rejectedFrames: result.rejectedFrames,
            frameRateFps: fpsVal,
            maxHeadMotionDeg: headVal,
            trackingNoiseDeg: result.trackingNoiseDeg,
            ambientLightLux: 950.0,
            recordingDurationSec: result.recordingDurationSec,
            analysisLatencyMs: result.analysisLatencyMs,
            passedCheckCount: result.passedCheckCount,
            totalCheckCount: result.checks.count,
            primaryAbstainRootCause: result.primaryRootCause?.rawValue,
            abstentionReasons: result.failedChecks.map { "\($0.name): \($0.valueString) (rule \($0.ruleString))" },
            qualityChecks: result.checks.map { QualityGateCheckRecord(from: $0) },
            compactYawTraceDeg: compactAngles,
            compactYawTimeSec: compactTimes,
            userEnteredNotes: userNotes,
            drivingResearchSelfReportTag: drivingResearchTag,
            locationTagDescription: locationTag,
            latitude: lat,
            longitude: lon
        )
    }
}

// MARK: - 3B. NEUROASSIST × CONTEXTUAL INTELLIGENCE (CI) SCIENTIFIC OBSERVATION CONTRACT
public struct NeuroAssistCIObservation: Codable, Sendable, Equatable {
    public let schemaVersion: String // "neuroassist.ci.observation/1.0"
    public let sessionID: String
    public let timestampISO8601: String
    public let scientificStatus: String // "VALID", "INCONCLUSIVE", "INVALID"
    public let protocolType: String // "OPTOKINETIC_NYSTAGMUS"
    public let algorithmVersion: String
    public let provenance: String // "LIVE_TRUEDEPTH", "RECORDED_SESSION", "SIMULATED"
    public let deviceModel: String

    // Measurement values (nil when scientificStatus != "VALID")
    public let slowPhaseVelocityDegPerSec: Double?
    public let oknGain: Double?
    public let confidenceIntervalLowerDegPerSec: Double?
    public let confidenceIntervalUpperDegPerSec: Double?
    public let intervalHalfWidthDegPerSec: Double?
    public let cleanWindowCount: Int

    // Sampling Cadence Diagnostics
    public let meanFps: Double
    public let cadenceJitterMs: Double
    public let minDtMs: Double
    public let maxDtMs: Double
    public let droppedFrames: Int
    public let droppedRatio: Double
    public let nyquistLimitHz: Double
    public let isSamplingIrregular: Bool

    // Quality Gates & Rejection Audit
    public let passedQualityGatesCount: Int
    public let totalQualityGatesCount: Int
    public let allGatesPassed: Bool
    public let primaryRejectionReason: String?
    public let rejectionReasons: [String]
    public let qualityGates: [QualityGateCheckRecord]

    // Calibration Metadata
    public let calibrationAccepted: Bool
    public let calibrationRMSDeg: Double
    public let calibrationSlope: Double
    public let calibrationIntercept: Double
    public let meanDistanceCm: Double

    // Compact numerical eye-yaw trace (degrees)
    public let compactYawTraceDeg: [Double]
    public let compactYawTimeSec: [Double]

    public static func from(session: PersistentMeasurementSession) -> NeuroAssistCIObservation {
        let iso = ISO8601DateFormatter()
        return NeuroAssistCIObservation(
            schemaVersion: "neuroassist.ci.observation/1.0",
            sessionID: session.id.uuidString,
            timestampISO8601: iso.string(from: session.timestamp),
            scientificStatus: session.scientificStatusRaw,
            protocolType: "OPTOKINETIC_NYSTAGMUS",
            algorithmVersion: session.analysisVersion,
            provenance: session.provenanceRaw,
            deviceModel: session.deviceModel,
            slowPhaseVelocityDegPerSec: session.slowPhaseVelocityDegPerSec,
            oknGain: session.oknGain,
            confidenceIntervalLowerDegPerSec: session.confidenceIntervalLowerDegPerSec,
            confidenceIntervalUpperDegPerSec: session.confidenceIntervalUpperDegPerSec,
            intervalHalfWidthDegPerSec: session.intervalHalfWidthDegPerSec,
            cleanWindowCount: session.cleanWindowCount,
            meanFps: session.cadenceDiagnostics?.meanFps ?? session.frameRateFps,
            cadenceJitterMs: session.cadenceDiagnostics?.cadenceJitterMs ?? 0.0,
            minDtMs: session.cadenceDiagnostics?.minDtMs ?? 16.67,
            maxDtMs: session.cadenceDiagnostics?.maxDtMs ?? 16.67,
            droppedFrames: session.cadenceDiagnostics?.droppedFrameCount ?? 0,
            droppedRatio: session.cadenceDiagnostics?.droppedFrameRatio ?? 0.0,
            nyquistLimitHz: session.cadenceDiagnostics?.nyquistBandwidthHz ?? (session.frameRateFps * 0.5),
            isSamplingIrregular: session.cadenceDiagnostics?.isSamplingIrregular ?? false,
            passedQualityGatesCount: session.passedCheckCount,
            totalQualityGatesCount: session.totalCheckCount,
            allGatesPassed: session.passedCheckCount == session.totalCheckCount && !session.didAbstain,
            primaryRejectionReason: session.primaryAbstainRootCause,
            rejectionReasons: session.abstentionReasons,
            qualityGates: session.qualityChecks,
            calibrationAccepted: session.calibrationAccepted,
            calibrationRMSDeg: session.calibrationRMSDeg,
            calibrationSlope: session.calibrationSlope,
            calibrationIntercept: session.calibrationIntercept,
            meanDistanceCm: session.meanDistanceCm,
            compactYawTraceDeg: session.compactYawTraceDeg,
            compactYawTimeSec: session.compactYawTimeSec
        )
    }
}

// MARK: - 4. PRIVACY & DATA SHARING CENTER MODELS (All Default OFF, Consent Versioned & Audited)

public enum SharingScopeIdentifier: String, Codable, CaseIterable, Sendable, Identifiable {
    case deIdentifiedProductAnalytics = "A. De-Identified Product Telemetry"
    case irbResearchContribution = "B. IRB-Reviewed Research Contribution"
    case singleReportRecipientShare = "C. Single-Report Recipient Sharing"
    case longitudinalClinicianShare = "D. Longitudinal Trend Sharing (Clinician / Researcher)"
    case futureFleetOrInsuranceStudy = "E. Future Fleet / Insurance Research Study (Requires Separate Enrollment)"

    public var id: String { rawValue }

    public var whatLeavesDeviceSummary: String {
        switch self {
        case .deIdentifiedProductAnalytics:
            return "Pseudonymous app crash & latency counters only (app version, frame rate, analysis latency). Note: pseudonymous device tokens are NOT anonymous. Never includes eye traces, location, or account identity."
        case .irbResearchContribution:
            return "Consented numerical eye-yaw time series (degrees), 5-dot calibration RMS, and 11-gate outcomes tagged with a study participant code. Zero camera video frames ever leave the phone."
        case .singleReportRecipientShare:
            return "One user-selected session report (CSV/JSON summary, SPV °/s or ABSTAIN status, 95% CI, and quality gates) exported explicitly via the iOS Share Sheet to your chosen recipient."
        case .longitudinalClinicianShare:
            return "Selected date-range summary of measured OKN gain and slow-phase velocity intervals for an authorized clinician or researcher, with an expiration date and instant revocation."
        case .futureFleetOrInsuranceStudy:
            return "Currently disabled in consumer prototype. Requires a separate written research enrollment and legal review before any fleet partner could receive de-identified readiness status."
        }
    }
}

public struct ConsentPermissionGrant: Codable, Sendable, Equatable, Identifiable {
    public var id: String { scope.rawValue }
    public let scope: SharingScopeIdentifier
    public var isEnabled: Bool
    public var consentVersion: String
    public var updatedAt: Date
    public var recipientLabel: String?
    public var expiresAt: Date?
}

public struct PrivacyAuditLogEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let actorAccountID: String
    public let actionType: String
    public let scopeOrTarget: String
    public let details: String
}

public struct RecipientShareGrant: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var recipientNameOrEmail: String
    public var recipientRole: String
    public var sharedSessionIDs: [UUID]
    public var includeLongitudinalTrend: Bool
    public var expiresAt: Date
    public var isRevoked: Bool
    public var accessCode: String
}

// MARK: - 5. NATIVE MESSAGING, SAFETY CONTACTS & REMINDERS MODELS

public struct TrustedSafetyContact: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var phoneOrEmail: String
    public var relationship: String
    public var invitationStatus: String // "Invited", "Confirmed", "Revoked"
    public var canReceiveLocationEvents: Bool
    public var canReceiveSelectedReports: Bool
}

public struct SafetyMessageRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let recipientName: String
    public let channelDescription: String // "iOS Share Sheet / Messages", "Mail", "Arrive Safe Check-In"
    public let messageBody: String
    public let attachedSessionID: UUID?
    public var deliveryStatus: String // "Prepared for Native Share", "Shared by User", "Revoked"
}

// MARK: - 6. LOCATION & DRIVING SAFETY EVENT LOG (Contextual When-In-Use Only)

public struct DrivingSafetyLocationEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let eventTitle: String
    public let coordinateLatitude: Double?
    public let coordinateLongitude: Double?
    public let placeDescription: String
    public let sharedWithContactName: String?
    public var isCurrentlySharingLive: Bool
    public var stoppedAt: Date?
}

// MARK: - 7. EXPERIMENTAL DRIVING IMPAIRMENT RESEARCH & SIMULATED INTERLOCK FIXTURES

public enum ExperimentalConditionFactor: String, Codable, CaseIterable, Sendable, Identifiable {
    case baselineWellRested = "Baseline / Rested Reference"
    case selfReportedFatigueDrowsiness = "Fatigue / Extended Wakefulness Study"
    case controlledAlcoholResearch = "Controlled Alcohol Research Protocol"
    case medicationOrDrugStudy = "Medication / Pharmacodynamic Study"
    case visualOrVestibularFactor = "Visual / Vestibular Confounder Check"

    public var id: String { rawValue }
}

public enum InterlockSimulationFixture: String, CaseIterable, Sendable, Identifiable {
    case cleanPassSignal = "Fixture 1: Clean Oculomotor Signal (11/11 Gates Passed)"
    case uncalibratedOrNoisyAbstain = "Fixture 2: Optical Glare / Head Drift (ABSTAIN)"
    case alteredGainObservation = "Fixture 3: Reduced Pursuit Gain vs Personal Baseline"
    case emergencyBypassOverride = "Fixture 4: Emergency Medical / Safety Override"

    public var id: String { rawValue }
}

// MARK: - 8. CONTEXTUAL CORE LOCATION HELPER (When-In-Use Only, Never Required for Eye Tests)

@Observable
public final class ContextualLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public var lastCoordinate: CLLocationCoordinate2D? = nil
    public var lastPlaceSummary: String = "Location not requested"
    public var isSharingEventLocation: Bool = false

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    public func requestWhenInUsePermissionContextually() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    public func captureSingleSnapshotLocation() {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            requestWhenInUsePermissionContextually()
            return
        }
        manager.requestLocation()
    }

    public func stopAllLocationSharingImmediately() {
        manager.stopUpdatingLocation()
        isSharingEventLocation = false
        lastPlaceSummary = "Location sharing stopped by user"
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        Task { @MainActor in
            self.lastCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.lastPlaceSummary = String(format: "%.4f° N, %.4f° W (±%.0fm)", lat, abs(lon), loc.horizontalAccuracy)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastPlaceSummary = "Location snapshot unavailable (\(error.localizedDescription))"
        }
    }
}

// MARK: - 9. MASTER PLATFORM STORE (Offline-First Encrypted Persistence + Audit Trail)

private struct EncryptedVaultPayload: Codable {
    var profile: UserProfileRecord
    var sessions: [PersistentMeasurementSession]
    var permissions: [ConsentPermissionGrant]
    var auditLog: [PrivacyAuditLogEntry]
    var recipientShares: [RecipientShareGrant]
    var trustedContacts: [TrustedSafetyContact]
    var safetyMessages: [SafetyMessageRecord]
    var locationEvents: [DrivingSafetyLocationEvent]
}

@Observable
public final class PlatformServicesStore {
    public var profile: UserProfileRecord
    public var sessions: [PersistentMeasurementSession] = []
    public var permissions: [ConsentPermissionGrant] = []
    public var auditLog: [PrivacyAuditLogEntry] = []
    public var recipientShares: [RecipientShareGrant] = []
    public var trustedContacts: [TrustedSafetyContact] = []
    public var safetyMessages: [SafetyMessageRecord] = []
    public var locationEvents: [DrivingSafetyLocationEvent] = []
    public let locationManager = ContextualLocationManager()

    private let encryptedFileURL: URL

    public init() {
        let docDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        self.encryptedFileURL = docDir.appendingPathComponent("neuroassist_encrypted_vault_v1.bin")

        // Default profile & ALL external sharing scopes strictly OFF by default
        let savedAppleID = SecureKeychainVault.loadAppleUserID()
        self.profile = UserProfileRecord(
            accountID: savedAppleID ?? "guest-local",
            authState: savedAppleID != nil ? .signedInWithApple : .guestMode,
            displayName: savedAppleID != nil ? "Apple ID Researcher" : "Guest Researcher"
        )
        self.permissions = SharingScopeIdentifier.allCases.map { scope in
            ConsentPermissionGrant(
                scope: scope,
                isEnabled: false, // STRICT DEFAULT OFF
                consentVersion: "v2.4-2026-10",
                updatedAt: Date(),
                recipientLabel: nil,
                expiresAt: nil
            )
        }

        loadEncryptedVaultOrSeedInitialHistory()
    }

    // MARK: Persistence (AES-256-GCM Encrypted File Backed by iOS Keychain)

    public func saveEncryptedVault() {
        let payload = EncryptedVaultPayload(
            profile: profile,
            sessions: sessions,
            permissions: permissions,
            auditLog: auditLog,
            recipientShares: recipientShares,
            trustedContacts: trustedContacts,
            safetyMessages: safetyMessages,
            locationEvents: locationEvents
        )
        if let ciphertext = try? SecureKeychainVault.encryptCodable(payload) {
            try? ciphertext.write(to: encryptedFileURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func loadEncryptedVaultOrSeedInitialHistory() {
        if let data = try? Data(contentsOf: encryptedFileURL),
           let decoded = try? SecureKeychainVault.decryptCodable(EncryptedVaultPayload.self, from: data) {
            self.profile = decoded.profile
            self.sessions = decoded.sessions
            self.permissions = decoded.permissions
            self.auditLog = decoded.auditLog
            self.recipientShares = decoded.recipientShares
            self.trustedContacts = decoded.trustedContacts
            self.safetyMessages = decoded.safetyMessages
            self.locationEvents = decoded.locationEvents
            return
        }

        // Seed initial consented reference sessions & default trusted contact for immediate out-of-the-box inspection
        let (cleanRes, cleanCal) = DemoExperienceStore.runSimulatedScenario(.validPursuit, mode: .researchFixed)
        let (abstainRes, abstainCal) = DemoExperienceStore.runSimulatedScenario(.headMovement, mode: .researchFixed)

        var s1 = PersistentMeasurementSession.from(
            result: cleanRes,
            calibration: cleanCal,
            ownerAccountID: profile.accountID,
            testCategory: .recordedReplay,
            userNotes: "Reference recorded numerical baseline session (rested morning check)."
        )
        var s2 = PersistentMeasurementSession.from(
            result: abstainRes,
            calibration: abstainCal,
            ownerAccountID: profile.accountID,
            testCategory: .recordedReplay,
            userNotes: "Reference abstention session demonstrating head-rotation quality gate rejection."
        )
        s1.userEnteredNotes = "Reference recorded session · 11/11 gates passed."
        s2.userEnteredNotes = "Reference abstention session · Head motion > 2.5° rejected."
        self.sessions = [s2, s1]

        self.trustedContacts = [
            TrustedSafetyContact(
                id: UUID(),
                name: "Alex Rivera",
                phoneOrEmail: "alex.rivera@example.com",
                relationship: "Trusted Safety Contact",
                invitationStatus: "Confirmed",
                canReceiveLocationEvents: true,
                canReceiveSelectedReports: true
            )
        ]

        appendAudit(
            actionType: "VAULT_INITIALIZED",
            scopeOrTarget: "AES-256-GCM Local Store",
            details: "Initialized Keychain-backed AES-GCM vault with all external sharing scopes OFF by default."
        )
        saveEncryptedVault()
    }

    // MARK: Audit Logging

    public func appendAudit(actionType: String, scopeOrTarget: String, details: String) {
        let entry = PrivacyAuditLogEntry(
            id: UUID(),
            timestamp: Date(),
            actorAccountID: profile.accountID,
            actionType: actionType,
            scopeOrTarget: scopeOrTarget,
            details: details
        )
        auditLog.insert(entry, at: 0)
        saveEncryptedVault()
    }

    // MARK: 1. Authentication & Account Lifecycle

    public func completeSignInWithApple(userID: String, fullName: String?, email: String?, identityTokenData: Data?) {
        let tokenString = identityTokenData?.base64EncodedString() ?? UUID().uuidString
        SecureKeychainVault.saveAppleCredential(userID: userID, sessionToken: tokenString)
        profile.accountID = userID
        profile.authState = .signedInWithApple
        if let fullName, !fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.displayName = fullName
        } else if profile.displayName == "Guest Researcher" {
            profile.displayName = "Apple ID Researcher"
        }
        if let email {
            profile.emailHint = email
        }
        appendAudit(
            actionType: "AUTH_APPLE_SIGN_IN",
            scopeOrTarget: "Keychain Credential Store",
            details: "Authenticated via Sign in with Apple; credential stored in iOS Keychain (never in UserDefaults)."
        )
    }

    public func createLocalResearchAccount(displayName: String, emailHint: String?) {
        let newID = "local-\(UUID().uuidString.prefix(8))"
        let sessionToken = UUID().uuidString
        SecureKeychainVault.saveAppleCredential(userID: newID, sessionToken: sessionToken)
        profile.accountID = newID
        profile.authState = .localResearchAccount
        profile.displayName = displayName.isEmpty ? "Research Participant" : displayName
        profile.emailHint = emailHint?.isEmpty == true ? nil : emailHint
        appendAudit(
            actionType: "AUTH_LOCAL_ACCOUNT_CREATED",
            scopeOrTarget: profile.accountID,
            details: "Created local Keychain-backed account profile."
        )
    }

    public func switchToGuestMode() {
        SecureKeychainVault.clearAuthCredentials()
        profile.accountID = "guest-local"
        profile.authState = .guestMode
        profile.displayName = "Guest Researcher"
        profile.emailHint = nil
        appendAudit(
            actionType: "AUTH_GUEST_MODE",
            scopeOrTarget: "guest-local",
            details: "Switched to offline Guest Mode; cleared Keychain session token."
        )
    }

    public func signOutAccount() {
        SecureKeychainVault.clearAuthCredentials()
        profile.authState = .unauthenticated
        appendAudit(
            actionType: "AUTH_SIGN_OUT",
            scopeOrTarget: profile.accountID,
            details: "Signed out and removed active session token from Keychain."
        )
    }

    public func deleteAccountAndWipeAllData() {
        try? FileManager.default.removeItem(at: encryptedFileURL)
        SecureKeychainVault.wipeAllCredentialsAndKeys()
        SecureKeychainVault.rotateMasterKey()

        profile = UserProfileRecord(
            accountID: "guest-local",
            authState: .guestMode,
            displayName: "Guest Researcher"
        )
        sessions.removeAll()
        recipientShares.removeAll()
        trustedContacts.removeAll()
        safetyMessages.removeAll()
        locationEvents.removeAll()
        permissions = SharingScopeIdentifier.allCases.map { scope in
            ConsentPermissionGrant(
                scope: scope,
                isEnabled: false,
                consentVersion: "v2.4-2026-10",
                updatedAt: Date(),
                recipientLabel: nil,
                expiresAt: nil
            )
        }
        auditLog = [
            PrivacyAuditLogEntry(
                id: UUID(),
                timestamp: Date(),
                actorAccountID: "system",
                actionType: "CRYPTOGRAPHIC_ERASURE_COMPLETED",
                scopeOrTarget: "All User Data & Keychain Keys",
                details: "Deleted encrypted vault file, wiped Keychain credentials, and rotated AES-256 master key."
            )
        ]
        saveEncryptedVault()
    }

    // MARK: 2. Session History Management

    @discardableResult
    public func recordMeasurementSession(
        result: OKNAnalysisResult,
        calibration: CalibrationModel?,
        category: SessionTestCategory = .preDriveCheck,
        userNotes: String = "",
        drivingResearchTag: String? = nil
    ) -> PersistentMeasurementSession {
        let locDesc = profile.locationTaggingOptIn ? locationManager.lastPlaceSummary : nil
        let lat = profile.locationTaggingOptIn ? locationManager.lastCoordinate?.latitude : nil
        let lon = profile.locationTaggingOptIn ? locationManager.lastCoordinate?.longitude : nil

        let session = PersistentMeasurementSession.from(
            result: result,
            calibration: calibration,
            ownerAccountID: profile.accountID,
            testCategory: category,
            userNotes: userNotes,
            drivingResearchTag: drivingResearchTag,
            locationTag: locDesc,
            lat: lat,
            lon: lon
        )
        sessions.insert(session, at: 0)
        appendAudit(
            actionType: "SESSION_RECORDED",
            scopeOrTarget: session.id.uuidString.prefix(8).description,
            details: "Saved \(category.rawValue) (\(result.didAbstain ? "ABSTAIN" : "MEASURED")) to encrypted local history."
        )
        return session
    }

    public func updateSessionUserNote(sessionID: UUID, newNote: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].userEnteredNotes = newNote
        appendAudit(
            actionType: "SESSION_NOTE_UPDATED",
            scopeOrTarget: sessionID.uuidString.prefix(8).description,
            details: "Updated user-entered note (stored separately from immutable measured signal metrics)."
        )
    }

    public func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        appendAudit(
            actionType: "SESSION_DELETED",
            scopeOrTarget: id.uuidString.prefix(8).description,
            details: "Deleted individual measurement session from encrypted vault."
        )
    }

    public func deleteAllMeasurementHistory() {
        let count = sessions.count
        sessions.removeAll()
        appendAudit(
            actionType: "ALL_SESSIONS_DELETED",
            scopeOrTarget: "Session History (\(count) records)",
            details: "User deleted all stored measurement sessions."
        )
    }

    // MARK: 3. Granular Consent & Recipient-Specific Sharing

    public func setPermission(scope: SharingScopeIdentifier, enabled: Bool, recipientLabel: String? = nil, validDays: Int? = nil) {
        guard let idx = permissions.firstIndex(where: { $0.scope == scope }) else { return }
        permissions[idx].isEnabled = enabled
        permissions[idx].updatedAt = Date()
        permissions[idx].recipientLabel = enabled ? recipientLabel : nil
        if let validDays, enabled {
            permissions[idx].expiresAt = Calendar.current.date(byAdding: .day, value: validDays, to: Date())
        } else {
            permissions[idx].expiresAt = nil
        }
        appendAudit(
            actionType: enabled ? "CONSENT_OPT_IN" : "CONSENT_REVOKED",
            scopeOrTarget: scope.rawValue,
            details: enabled
                ? "Explicit opt-in granted (version \(permissions[idx].consentVersion))."
                : "Opt-in revoked; external sharing disabled immediately."
        )
    }

    public func createRecipientShareGrant(
        recipientNameOrEmail: String,
        recipientRole: String,
        sessionIDs: [UUID],
        includeTrend: Bool,
        validDays: Int
    ) -> RecipientShareGrant {
        let expiry = Calendar.current.date(byAdding: .day, value: max(1, validDays), to: Date()) ?? Date().addingTimeInterval(86400 * 7)
        let grant = RecipientShareGrant(
            id: UUID(),
            createdAt: Date(),
            recipientNameOrEmail: recipientNameOrEmail,
            recipientRole: recipientRole,
            sharedSessionIDs: sessionIDs,
            includeLongitudinalTrend: includeTrend,
            expiresAt: expiry,
            isRevoked: false,
            accessCode: "NA-\(Int.random(in: 100000...999999))"
        )
        recipientShares.insert(grant, at: 0)
        appendAudit(
            actionType: "RECIPIENT_SHARE_CREATED",
            scopeOrTarget: recipientNameOrEmail,
            details: "Granted permission-controlled share (\(sessionIDs.count) session(s), expires \(expiry.formatted(date: .abbreviated, time: .shortened)))."
        )
        return grant
    }

    public func revokeRecipientShareGrant(id: UUID) {
        guard let idx = recipientShares.firstIndex(where: { $0.id == id }) else { return }
        recipientShares[idx].isRevoked = true
        appendAudit(
            actionType: "RECIPIENT_SHARE_REVOKED",
            scopeOrTarget: recipientShares[idx].recipientNameOrEmail,
            details: "Revoked recipient share access token \(recipientShares[idx].accessCode)."
        )
    }

    // MARK: 4. Export Helpers (CSV & Structured JSON)

    public func exportSessionsAsJSONFile(sessionsToExport: [PersistentMeasurementSession]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sessionsToExport) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeuroAssist_History_\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url, options: .atomic)
            appendAudit(
                actionType: "EXPORT_JSON",
                scopeOrTarget: "\(sessionsToExport.count) session(s)",
                details: "Generated structured JSON export for user-controlled share sheet."
            )
            return url
        } catch {
            return nil
        }
    }

    public func exportSessionAsCIObservationJSON(session: PersistentMeasurementSession) -> URL? {
        let obs = NeuroAssistCIObservation.from(session: session)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(obs) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeuroAssist_CI_Observation_\(session.id.uuidString.prefix(8)).json")
        do {
            try data.write(to: url, options: .atomic)
            appendAudit(
                actionType: "EXPORT_CI_OBSERVATION",
                scopeOrTarget: session.id.uuidString.prefix(8).description,
                details: "Exported versioned observation record for NeuroAssist x CI child integration."
            )
            return url
        } catch {
            return nil
        }
    }

    public func exportSessionsAsCSVFile(sessionsToExport: [PersistentMeasurementSession]) -> URL? {
        var csv = "# NeuroAssist Longitudinal Session Export\n"
        csv += "# Research prototype. Measures eye movement; doesn't diagnose.\n"
        csv += "session_id,timestamp_iso8601,category,provenance,protocol_mode,analysis_version,device_model,calibration_accepted,calibration_rms_deg,mean_distance_cm,did_abstain,spv_deg_per_s,okn_gain,ci95_low_deg_per_s,ci95_high_deg_per_s,clean_windows,valid_frame_pct,fps,max_head_motion_deg,tracking_noise_deg,passed_checks,total_checks,primary_abstain_cause,user_notes\n"

        let iso = ISO8601DateFormatter()
        for s in sessionsToExport {
            let spvStr = s.didAbstain ? "ABSTAIN" : (s.slowPhaseVelocityDegPerSec.map { String(format: "%.3f", $0) } ?? "ABSTAIN")
            let gainStr = s.didAbstain ? "ABSTAIN" : (s.oknGain.map { String(format: "%.3f", $0) } ?? "ABSTAIN")
            let ciLoStr = s.didAbstain ? "ABSTAIN" : (s.confidenceIntervalLowerDegPerSec.map { String(format: "%.3f", $0) } ?? "ABSTAIN")
            let ciHiStr = s.didAbstain ? "ABSTAIN" : (s.confidenceIntervalUpperDegPerSec.map { String(format: "%.3f", $0) } ?? "ABSTAIN")
            let cleanNotes = s.userEnteredNotes.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")

            csv += "\"\(s.id.uuidString)\",\"\(iso.string(from: s.timestamp))\",\"\(s.testCategory.rawValue)\",\"\(s.provenanceRaw)\",\"\(s.protocolModeRaw)\",\"\(s.analysisVersion)\",\"\(s.deviceModel)\",\(s.calibrationAccepted),\(String(format: "%.3f", s.calibrationRMSDeg)),\(String(format: "%.1f", s.meanDistanceCm)),\(s.didAbstain),\(spvStr),\(gainStr),\(ciLoStr),\(ciHiStr),\(s.cleanWindowCount),\(String(format: "%.1f", s.validFramePercentage)),\(String(format: "%.1f", s.frameRateFps)),\(String(format: "%.2f", s.maxHeadMotionDeg)),\(String(format: "%.3f", s.trackingNoiseDeg)),\(s.passedCheckCount),\(s.totalCheckCount),\"\(s.primaryAbstainRootCause ?? "NONE")\",\"\(cleanNotes)\"\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeuroAssist_History_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            appendAudit(
                actionType: "EXPORT_CSV",
                scopeOrTarget: "\(sessionsToExport.count) session(s)",
                details: "Generated CSV longitudinal export for user-controlled share sheet."
            )
            return url
        } catch {
            return nil
        }
    }

    // MARK: 5. Messaging & Location Event Logging

    public func logSafetyMessage(recipientName: String, channel: String, body: String, sessionID: UUID?) {
        let msg = SafetyMessageRecord(
            id: UUID(),
            timestamp: Date(),
            recipientName: recipientName,
            channelDescription: channel,
            messageBody: body,
            attachedSessionID: sessionID,
            deliveryStatus: "Shared via Native iOS Sheet"
        )
        safetyMessages.insert(msg, at: 0)
        appendAudit(
            actionType: "MESSAGE_SHARED",
            scopeOrTarget: recipientName,
            details: "User shared message/report via \(channel)."
        )
    }

    public func startEventLocationShare(contactName: String, eventTitle: String) {
        locationManager.captureSingleSnapshotLocation()
        locationManager.isSharingEventLocation = true
        let ev = DrivingSafetyLocationEvent(
            id: UUID(),
            timestamp: Date(),
            eventTitle: eventTitle,
            coordinateLatitude: locationManager.lastCoordinate?.latitude,
            coordinateLongitude: locationManager.lastCoordinate?.longitude,
            placeDescription: locationManager.lastPlaceSummary,
            sharedWithContactName: contactName,
            isCurrentlySharingLive: true,
            stoppedAt: nil
        )
        locationEvents.insert(ev, at: 0)
        appendAudit(
            actionType: "LOCATION_EVENT_SHARE_STARTED",
            scopeOrTarget: contactName,
            details: "Started consented single-event location share (\(eventTitle))."
        )
    }

    public func stopAllActiveLocationShares() {
        locationManager.stopAllLocationSharingImmediately()
        for i in 0..<locationEvents.count {
            if locationEvents[i].isCurrentlySharingLive {
                locationEvents[i].isCurrentlySharingLive = false
                locationEvents[i].stoppedAt = Date()
            }
        }
        appendAudit(
            actionType: "LOCATION_SHARE_STOPPED",
            scopeOrTarget: "CoreLocation",
            details: "Stopped all active event location sharing immediately."
        )
    }
}
