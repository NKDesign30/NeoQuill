import Foundation

/// Entscheidet pro Feature ob es benutzt werden darf.
///
/// Quelle des Master-Switches in Reihenfolge:
///   1. UserDefaults-Override (`license_enforcement_mode`) — für QA-Builds
///   2. Build-Default aus `Info.plist` (`NeoQuillLicenseEnforcement`)
///   3. Hard-Default: `.disabled` (Beta-Phase)
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

    static func currentMode(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> LicenseEnforcementMode {
        if let raw = defaults.string(forKey: userDefaultsKey),
           let mode = LicenseEnforcementMode(rawValue: raw) {
            return mode
        }
        if let raw = bundle.infoDictionary?[infoPlistKey] as? String,
           let mode = LicenseEnforcementMode(rawValue: raw) {
            return mode
        }
        return .disabled
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
