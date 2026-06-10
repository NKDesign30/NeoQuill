import Foundation

/// Wert-Snapshot einer beendeten Live-Aufnahme. `RecordingController.stop()`
/// baut ihn genau einmal aus AudioCapture, CaptionCapture und der beim Start
/// eingefrorenen Plattform — danach hängt die Persist-Pipeline an diesem Wert
/// statt an geteiltem mutablem Zustand.
///
/// Warum ein Wert statt Rückgriffe:
/// - Kein Reach-back in `audioCapture.collectFinalAudio()` aus einem detachten
///   Task — das hing an der MainActor-Enqueue-Reihenfolge gegen das nächste
///   `start()`/`clearRecording()` und war nirgends als Invariante kodiert.
/// - Keine Persist-Zeit-Lesung von `detector.detectedApp`: der Detector
///   resettet die App beim Call-Ende sofort auf `.unknown`, der Auto-Stop
///   läuft aber asynchron — auto-gestoppte Teams/Zoom-Meetings wurden dadurch
///   als `.call` persistiert. Die Plattform wird jetzt beim `start()`
///   eingefroren und reist als Teil dieses Werts.
struct CapturedSession {
    /// 16 kHz Mono-Stems (ASR-Pfad) plus deren zeit-alignter Mix.
    let mic: [Float]
    let sys: [Float]
    let mixed: [Float]
    /// 48 kHz Mono-Stems für das Stereo-Playback-Archiv (leer wenn keine HQ-Samples).
    let micHQ: [Float]
    let sysHQ: [Float]
    let captionEvents: [CaptionEvent]
    let startedAt: Date
    let runtime: TimeInterval
    /// Plattform der Aufnahme — beim Start erfasst, nicht zur Persist-Zeit.
    let platform: Platform
}
