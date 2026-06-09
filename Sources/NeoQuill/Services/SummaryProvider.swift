import Foundation

/// Ein KI-Backend, das aus einem Transkript eine strukturierte Meeting-Summary
/// macht (Titel, TL;DR, Highlights, Tasks, Chapters).
///
/// Der Aufrufer (`PostProcessor`) kennt nur dieses Interface, nicht den konkreten
/// Anbieter. Neue Provider (OpenAI, Anthropic, Ollama, Claude CLI) docken hier an,
/// die Auswahl + Config-Beschaffung passiert in `AIProviderSettings.makeProvider`.
/// Ergebnis eines Verbindungstests. Trennt "erreichbar" von "Grund, warum nicht",
/// damit die UI dem Nutzer einen konkreten Fehler statt nur "ging nicht" zeigt.
enum ProviderProbeResult: Equatable, Sendable {
    case ok(String)
    case failed(String)

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

protocol SummaryProvider: Sendable {
    /// `nil` heißt: kein Ergebnis (Netzwerkfehler, fehlende Tools, ungültige
    /// Antwort). Der Aufrufer fällt dann auf einen Transkript-Fallback zurück.
    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI?

    /// Leichtgewichtiger Erreichbarkeits-Check für den "Verbindung testen"-Button.
    /// Validiert Endpoint, Auth und Modell mit einem minimalen Aufruf.
    func probe() async -> ProviderProbeResult
}

/// Lokaler Claude-Login über die `claude` CLI. Braucht keine Config und keinen
/// API-Key, setzt aber eine installierte und eingeloggte CLI voraus.
struct ClaudeCLISummaryProvider: SummaryProvider {
    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? {
        await ClaudeCLIClient.summarize(transcript: transcript, locale: locale)
    }

    func probe() async -> ProviderProbeResult {
        guard let path = ClaudeCLIClient.claudeBinaryPath() else {
            return .failed("claude CLI nicht gefunden. Installiere die Claude CLI und logge dich ein.")
        }
        return .ok("claude CLI gefunden: \(path)")
    }
}
