import Foundation

/// Entscheidet pro Feature ob es benutzt werden darf.
///
/// Version-Policy:
///   - < 1.0.0: immer `.disabled` — Beta-Builds bleiben vollständig frei
///   - >= 1.0.0: `Info.plist`-Mode, sonst `.enforced`
///
/// Feature-Matrix nach Trial-Ablauf:
///   - Recording:                 IMMER frei
///   - Lokale Transkription:      IMMER frei
///   - AI-Summary/TLDR/Actions:   geblockt
///   - Speaker-ID cross-meeting:  geblockt
///   - Platform-Import:           geblockt
enum LicenseEnforcement {

    static let userDefaultsKey = "license_enforcement_mode"
    static let infoPlistKey = "NeoQuillLicenseEnforcement"
    static let appVersionKey = "CFBundleShortVersionString"

    static func currentMode(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        allowUserDefaultsOverride: Bool = false
    ) -> LicenseEnforcementMode {
        currentMode(
            defaults: defaults,
            configuredModeRaw: bundle.infoDictionary?[infoPlistKey] as? String,
            appVersionRaw: bundle.infoDictionary?[appVersionKey] as? String,
            allowUserDefaultsOverride: allowUserDefaultsOverride
        )
    }

    static func currentMode(
        defaults: UserDefaults = .standard,
        configuredModeRaw: String?,
        appVersionRaw: String?,
        allowUserDefaultsOverride: Bool = false
    ) -> LicenseEnforcementMode {
        guard ReleaseVersionPolicy.isPaidVersion(appVersionRaw) else {
            return .disabled
        }
        if allowUserDefaultsOverride,
           let raw = defaults.string(forKey: userDefaultsKey),
           let mode = LicenseEnforcementMode(rawValue: raw) {
            return mode
        }
        if let raw = configuredModeRaw,
           let mode = LicenseEnforcementMode(rawValue: raw) {
            return mode
        }
        return .enforced
    }

    // MARK: - Feature-Gates

    /// Recording bleibt immer frei. Trial-User haben es eh schon gemacht.
    static func canRecord(_ snapshot: LicenseSnapshot) -> Bool {
        true
    }

    /// Lokale WhisperKit-Transkription bleibt immer frei — kein Compute auf
    /// Niko-Seite, kein API-Aufruf nach außen.
    static func canTranscribeLocally(_ snapshot: LicenseSnapshot) -> Bool {
        true
    }

    /// Summaries (TL;DR, Actions, Highlights, Chapters) sind das Pro-Feature.
    /// Geblockt nach Trial-Ablauf oder bei ungültiger Lizenz.
    static func canUseSummary(_ snapshot: LicenseSnapshot) -> Bool {
        snapshot.hasActiveEntitlement
    }

    /// Speaker-ID cross-meeting ist das "magische" Feature und Pro.
    static func canCrossMeetingSpeakerID(_ snapshot: LicenseSnapshot) -> Bool {
        snapshot.hasActiveEntitlement
    }

    /// Platform-Imports (Teams/Meet/Zoom) sind Pro.
    static func canImportTranscript(_ snapshot: LicenseSnapshot) -> Bool {
        snapshot.hasActiveEntitlement
    }
}

enum ReleaseVersionPolicy {
    private struct SemanticVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }

    private static let paidFloor = SemanticVersion(major: 1, minor: 0, patch: 0)

    static func isPaidVersion(_ raw: String?) -> Bool {
        guard let version = parse(raw) else { return false }
        return version >= paidFloor
    }

    private static func parse(_ raw: String?) -> SemanticVersion? {
        guard let raw else { return nil }
        let core = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
        guard let core else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        return SemanticVersion(
            major: numbers[0] ?? 0,
            minor: parts.count > 1 ? numbers[1] ?? 0 : 0,
            patch: parts.count > 2 ? numbers[2] ?? 0 : 0
        )
    }
}
