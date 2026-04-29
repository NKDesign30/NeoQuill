import Foundation
import SwiftUI

// Shared State zwischen AudioPlayer und Sub-Views (z.B. ChaptersPane).
// Erlaubt Cross-View-Aktionen wie "springe zu Chapter-Timestamp" ohne dass
// die Player-State (AVAudioPlayer-Referenz) aus AudioPlayer raus muss.
//
// Pattern: ChaptersPane setzt `seekTo`, AudioPlayer reagiert in `.onChange`
// auf den neuen Wert und seekt + spielt ab. Wert wird nach Konsum auf nil
// zurueckgesetzt damit das gleiche Chapter erneut klickbar bleibt.

@MainActor
final class AudioPlaybackController: ObservableObject {
    /// Wenn != nil, soll der AudioPlayer auf diese Sekunde springen.
    /// Nach dem Seek setzt der AudioPlayer den Wert zurueck auf nil.
    @Published var seekTo: TimeInterval?

    /// Konsumiert vom AudioPlayer nachdem der Seek ausgefuehrt wurde.
    func clearSeek() {
        seekTo = nil
    }
}

// Parser fuer Chapter-Timestamps wie "02:14", "2:14" oder "1:23:45".
// Robust gegenueber fehlender fuehrender Null (Whisper liefert "2:14" bei
// einstelligen Minuten).
enum TimestampParser {
    static func seconds(from text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        switch parts.count {
        case 2:
            guard let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
            return TimeInterval(m * 60 + s)
        case 3:
            guard let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
            return TimeInterval(h * 3600 + m * 60 + s)
        default:
            return nil
        }
    }
}
