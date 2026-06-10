import Foundation

/// Entscheidet, was mit einem Meeting passiert, dessen Transkription
/// unterbrochen wurde (App-Quit/Crash während STT): erneut versuchen oder
/// endgültig als gescheitert markieren.
///
/// Vorher war die Invariante gesplittet: der Zähler lebte im `MeetingStore`
/// (`transcribe_attempts`-Spalte), die 3-Strikes-Politik samt
/// `.failed`-Formulierung im `RecordingController` — ein Schwellen-Fix musste
/// beide Dateien kennen. Der Store persistiert weiterhin nur den Zähler;
/// die Entscheidung hat hier ihr einziges Zuhause.
enum TranscriptionRecoveryPolicy {

    /// Maximale automatische Wiederanläufe, bevor ein Meeting aufgegeben wird.
    static let maxAttempts = 3

    enum Decision: Equatable {
        case retry
        /// Lifecycle, der das Meeting sichtbar als gescheitert markiert —
        /// `.failed` ist nicht busy, also greift die Recovery es beim nächsten
        /// Start nicht wieder auf.
        case markFailed(MeetingLifecycle)
    }

    /// `attempts` ist der bereits hochgezählte Versuchsstand (inklusive des
    /// gerade anlaufenden Versuchs).
    static func decision(forAttempt attempts: Int) -> Decision {
        guard attempts <= maxAttempts else {
            return .markFailed(.failed(
                reason: "Transkription mehrfach unterbrochen",
                attempts: attempts - 1
            ))
        }
        return .retry
    }
}
