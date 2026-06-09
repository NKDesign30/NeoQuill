import Foundation

/// Gemeinsamer Vertrag der System-Audio-Quellen: liefert 16-kHz-Mono-Samples für
/// die Transkription und 48-kHz-Mono-Samples fürs Archiv und lässt sich starten
/// und stoppen.
///
/// Zwei reale Adapter erfüllen ihn — `ProcessAudioTap` (CoreAudio Process Tap,
/// primär) und `SCKAudioCapture` (ScreenCaptureKit, Fallback). Vorher hatten
/// beide dieselbe Oberfläche, aber keinen gemeinsamen Typ, und `AudioCapture`
/// verdrahtete ihre Callbacks an zwei Stellen wortgleich. Dieser Seam macht die
/// Austauschbarkeit explizit und erlaubt eine einzige Verdrahtungs-Stelle.
///
/// `start`/`stop` sind als `async` deklariert; `ProcessAudioTap` erfüllt sie mit
/// synchronen Methoden (Swift erlaubt einen synchronen Witness für eine
/// asynchrone Anforderung).
protocol SystemAudioSource: AnyObject {
    /// 16-kHz-Mono-Float32-Samples für die ASR-Pipeline.
    var onSamples: (([Float]) -> Void)? { get set }
    /// 48-kHz-Mono-Float32-Samples für das hochauflösende Archiv.
    var onSamplesHQ: (([Float]) -> Void)? { get set }

    func start(bundleIdentifiers: [String]) async throws
    func stop() async
}
