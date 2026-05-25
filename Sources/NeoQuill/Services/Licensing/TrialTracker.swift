import Foundation
import Security

/// 14-Tage-Trial mit minimaler Tamper-Resistance.
///
/// Persistiert in Keychain: `trialStartedAt` (immutable nach erstem Schreiben)
/// und `lastSeenAt` (wird forward-only aktualisiert).
///
/// Tamper-Pattern: wenn die System-Uhr zurückgedreht wird (also `now < lastSeenAt`),
/// nimmt `status(now:)` `lastSeenAt` als reale "jetzt"-Zeit an. So kann der User
/// die Trial-Dauer nicht durch Uhrendrehen verlängern.
///
/// Was wir NICHT abdecken: TPM-/Secure-Enclave-Signaturen. Dafür ist 14 Tage zu
/// kurz und die Mühe zu groß. Beta-User-Frust kostet mehr als die paar Tamper-Fälle.
protocol TrialTracking {
    func startedAt() -> Date?
    func lastSeen() -> Date?
    func start(now: Date) throws
    func touch(now: Date) throws
    func reset()
}

enum TrialTrackerError: Error, Equatable {
    case encodingFailed
    case keychainStatus(OSStatus)
}

/// Reine Domäne — keine Persistierung. Berechnet aus drei Datumswerten den
/// `LicenseStatus`-Anteil für Trial.
struct TrialEvaluator {
    static let trialLength: TimeInterval = 14 * 24 * 60 * 60   // 14 Tage

    /// Liefert effektives "jetzt": `max(now, lastSeenAt)`.
    static func effectiveNow(now: Date, lastSeen: Date?) -> Date {
        guard let lastSeen else { return now }
        return now > lastSeen ? now : lastSeen
    }

    /// Wieviele Tage bleiben — auf Zellen-Anzeige aufgerundet damit "1 Tag verbleibt"
    /// nicht zu früh auf 0 springt. Negativ wird auf 0 geklemmt.
    static func remainingDays(startedAt: Date, effectiveNow: Date) -> Int {
        let expiresAt = startedAt.addingTimeInterval(trialLength)
        let secondsLeft = expiresAt.timeIntervalSince(effectiveNow)
        if secondsLeft <= 0 { return 0 }
        let days = Int(ceil(secondsLeft / 86_400))
        return max(0, days)
    }

    /// Konvertiert Tracker-State + Wall-Clock in `LicenseStatus`.
    /// `nil` → noch nicht gestartet, wird vom Aufrufer als "starten" behandelt.
    static func statusFor(
        startedAt: Date?,
        lastSeen: Date?,
        now: Date
    ) -> LicenseStatus? {
        guard let startedAt else { return nil }
        let effective = effectiveNow(now: now, lastSeen: lastSeen)
        let remaining = remainingDays(startedAt: startedAt, effectiveNow: effective)
        return remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }
}

/// Keychain-Implementierung. Speichert beide Datumswerte als JSON in einem Item.
final class KeychainTrialTracker: TrialTracking {
    private let service = "com.neon.quill.licensing.trial"
    private let account = "tracker"

    private struct Payload: Codable {
        var startedAt: Date
        var lastSeenAt: Date
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func read() -> Payload? {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
            kSecReturnData: kCFBooleanTrue,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? decoder.decode(Payload.self, from: data)
    }

    private func write(_ payload: Payload) throws {
        let data = try encoder.encode(payload)
        let base: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(base as CFDictionary)
        var insert = base
        insert[kSecValueData] = data as CFData
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TrialTrackerError.keychainStatus(status)
        }
    }

    func startedAt() -> Date? { read()?.startedAt }
    func lastSeen() -> Date? { read()?.lastSeenAt }

    func start(now: Date) throws {
        if read() != nil { return }
        try write(Payload(startedAt: now, lastSeenAt: now))
    }

    func touch(now: Date) throws {
        guard var payload = read() else { return }
        if now > payload.lastSeenAt {
            payload.lastSeenAt = now
            try write(payload)
        }
    }

    func reset() {
        let q: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// In-Memory-Variante für Tests.
final class InMemoryTrialTracker: TrialTracking {
    private var _startedAt: Date?
    private var _lastSeen: Date?

    init(startedAt: Date? = nil, lastSeen: Date? = nil) {
        self._startedAt = startedAt
        self._lastSeen = lastSeen
    }

    func startedAt() -> Date? { _startedAt }
    func lastSeen() -> Date? { _lastSeen }

    func start(now: Date) throws {
        guard _startedAt == nil else { return }
        _startedAt = now
        _lastSeen = now
    }

    func touch(now: Date) throws {
        guard let prev = _lastSeen else { return }
        if now > prev { _lastSeen = now }
    }

    func reset() {
        _startedAt = nil
        _lastSeen = nil
    }
}
