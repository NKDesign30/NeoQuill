import Foundation

// State Machine für eine Aufnahme. NeoWispr-Pattern: idle → preparing → recording →
// processing → idle. Fehler-Pfad an jeder Stelle möglich.

enum RecordingState: Equatable {
    case idle
    case preparing                    // Permission-Check, Model-Load
    case recording(startedAt: Date)
    case processing                   // Stop gedrückt, finales Transcript+Diarize
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .recording, .preparing, .processing: return true
        default: return false
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}
