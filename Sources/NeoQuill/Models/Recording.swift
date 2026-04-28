import Foundation

// Recording-Domain: was während der Aufnahme entsteht. Wird nach Abschluss vom
// PostProcessor in MeetingDetail überführt (Adapter-Layer kommt in einer späteren Phase).
//
// Schmaler als das alte Quill-Modell — keine AgentAction, keine Atlassian-Credentials,
// keine Babsi-Ausführungslogik. Pures Audio + Transkript.

struct TranscriptSegment: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let speaker: String?
    let isPartial: Bool

    init(text: String, start: TimeInterval, end: TimeInterval, speaker: String? = nil, isPartial: Bool = false) {
        self.id = UUID()
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
        self.isPartial = isPartial
    }
}

enum MeetingType: String, Codable, CaseIterable, Sendable {
    case standup    = "Standup"
    case retro      = "Retrospektive"
    case planning   = "Sprint Planning"
    case review     = "Sprint Review"
    case oneOnOne   = "1:1"
    case interview  = "Interview"
    case workshop   = "Workshop"
    case general    = "Meeting"

    var sfSymbol: String {
        switch self {
        case .standup:   return "bolt.fill"
        case .retro:     return "arrow.counterclockwise"
        case .planning:  return "list.bullet.clipboard"
        case .review:    return "eye.fill"
        case .oneOnOne:  return "person.2.fill"
        case .interview: return "person.badge.plus"
        case .workshop:  return "lightbulb.fill"
        case .general:   return "mic.fill"
        }
    }
}

struct RecordingStatus: Sendable {
    var isRecording: Bool = false
    var meetingName: String? = nil
    var duration: TimeInterval = 0
    var segmentCount: Int = 0
    var isProcessing: Bool = false
    var detectedApp: String? = nil
}

// Eine aktive oder abgeschlossene Aufnahme. Schmal — UI nutzt MeetingDetail/Summary.
struct RecordingSession: Identifiable, Codable {
    let id: UUID
    var name: String
    var date: Date
    var duration: TimeInterval
    var meetingType: MeetingType
    var segments: [TranscriptSegment]
    var analysis: String?
    var isRecording: Bool
    var callApp: String?
    var filename: String?

    init(name: String, meetingType: MeetingType = .general, callApp: String? = nil) {
        self.id = UUID()
        self.name = name
        self.date = Date()
        self.duration = 0
        self.meetingType = meetingType
        self.segments = []
        self.analysis = nil
        self.isRecording = true
        self.callApp = callApp
        self.filename = nil
    }
}

// Helper: Sekunden → "MM:SS" / "H:MM:SS"
enum DurationFormat {
    static func short(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func long(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
