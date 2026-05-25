import Foundation
import Combine

/// Single Source of Truth für den Lizenz-Zustand der App.
///
/// Orchestriert:
///   - `FirstLaunchMarker` (schreibt beim allerersten Start, dann never)
///   - `TrialTracker`       (14-Tage-Countdown)
///   - `BetaGraceResolver`  (auto-grant für Beta-User)
///   - `LicenseValidator`   (LS-API + Persistierung)
///
/// UI liest `snapshot` und bindet sich darüber an Status-Änderungen.
@MainActor
final class LicenseService: ObservableObject {

    @Published private(set) var snapshot: LicenseSnapshot

    // Dependencies — alle Protocol-typed für Tests.
    private let marker: FirstLaunchMarkerStoring
    private let trial: TrialTracking
    private let validator: LicenseValidating
    private let modeProvider: () -> LicenseEnforcementMode
    private let cutoffProvider: () -> Date?

    init(
        marker: FirstLaunchMarkerStoring,
        trial: TrialTracking,
        validator: LicenseValidating,
        modeProvider: @escaping () -> LicenseEnforcementMode = { LicenseEnforcement.currentMode() },
        cutoffProvider: @escaping () -> Date? = { nil }
    ) {
        self.marker = marker
        self.trial = trial
        self.validator = validator
        self.modeProvider = modeProvider
        self.cutoffProvider = cutoffProvider
        self.snapshot = LicenseSnapshot(
            status: .notRequired,
            mode: modeProvider(),
            firstLaunchDate: marker.firstLaunchDate(),
            cutoffDate: cutoffProvider(),
            activation: validator.currentRecord()
        )
    }

    // MARK: - Lifecycle

    /// Wird in `AppState.init` ganz früh aufgerufen.
    /// Schreibt den FirstLaunchMarker und berechnet den initialen Snapshot.
    func bootstrap(now: Date = Date()) async {
        try? marker.ensureMarker(now: now)
        await refresh(now: now)
    }

    /// Neuberechnung des Snapshots — wird vom UI angefordert wenn z.B. ein
    /// Setting geändert wurde oder periodisch beim App-Activate.
    func refresh(now: Date = Date()) async {
        let mode = modeProvider()
        let cutoff = cutoffProvider()
        let firstLaunch = marker.firstLaunchDate()

        // Mode disabled → kein Gate, keine Trial-Start-Side-Effects
        if mode == .disabled {
            snapshot = LicenseSnapshot(
                status: .notRequired,
                mode: mode,
                firstLaunchDate: firstLaunch,
                cutoffDate: cutoff,
                activation: validator.currentRecord()
            )
            return
        }

        // Enforced: Beta-Grace zuerst prüfen
        let graceDecision = BetaGraceResolver.resolve(
            firstLaunchDate: firstLaunch,
            cutoffDate: cutoff
        )
        if graceDecision == .grace {
            snapshot = LicenseSnapshot(
                status: .betaGrace,
                mode: mode,
                firstLaunchDate: firstLaunch,
                cutoffDate: cutoff,
                activation: validator.currentRecord()
            )
            return
        }

        // Aktive Lizenz vorhanden? → validieren
        if validator.currentRecord() != nil {
            let outcome = await validator.validate(now: now)
            let nextStatus = LicenseService.mapValidation(outcome)
            try? trial.touch(now: now)
            snapshot = LicenseSnapshot(
                status: nextStatus,
                mode: mode,
                firstLaunchDate: firstLaunch,
                cutoffDate: cutoff,
                activation: validator.currentRecord()
            )
            return
        }

        // Keine Lizenz → Trial starten oder weiterzählen
        try? trial.start(now: now)
        try? trial.touch(now: now)
        let trialStatus = TrialEvaluator.statusFor(
            startedAt: trial.startedAt(),
            lastSeen: trial.lastSeen(),
            now: now
        ) ?? .trial(daysRemaining: 14)

        snapshot = LicenseSnapshot(
            status: trialStatus,
            mode: mode,
            firstLaunchDate: firstLaunch,
            cutoffDate: cutoff,
            activation: nil
        )
    }

    // MARK: - User-Actions

    /// Vom Aktivierungs-Sheet aufgerufen.
    @discardableResult
    func activate(licenseKey: String, machineName: String, now: Date = Date()) async throws -> ActivationRecord {
        let record = try await validator.activate(
            licenseKey: licenseKey,
            machineName: machineName,
            now: now
        )
        await refresh(now: now)
        return record
    }

    /// Vom Settings-Deaktivieren-Button aufgerufen.
    @discardableResult
    func deactivate(now: Date = Date()) async -> Bool {
        let ok = await validator.deactivate()
        await refresh(now: now)
        return ok
    }

    // MARK: - Mapping

    private static func mapValidation(_ outcome: ValidationOutcome) -> LicenseStatus {
        switch outcome {
        case .noRecord:
            // Sollte hier nicht passieren, weil refresh() vorher record-check macht.
            return .trial(daysRemaining: 14)
        case .stillValid(let record):
            return .activated(tier: record.tier, lastValidatedAt: record.lastValidatedAt)
        case .offlineGrace(let record):
            return .activated(tier: record.tier, lastValidatedAt: record.lastValidatedAt)
        case .invalidated(let reason):
            return .invalidated(reason: reason)
        }
    }
}
