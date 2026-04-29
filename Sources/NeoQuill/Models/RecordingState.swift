import Foundation

// State Machine für eine Aufnahme.
// idle → detected → preparing → recording → processing → idle
// Detected: Auto-Detector hat eine Call-App erkannt, Pille fragt User ob aufnehmen.

enum RecordingState: Equatable {
    case idle
    case detected(app: CallApp)       // Pille zeigt "Aufnehmen?" + ✓ ✗
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

    var isDetected: Bool {
        if case .detected = self { return true }
        return false
    }
}
