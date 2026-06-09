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
