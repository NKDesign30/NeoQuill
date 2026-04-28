import Foundation
import SwiftUI

// Domain-Modelle. 1:1-Reflex auf Bundle-data.js, Swift-idiomatisiert.
// Werden später vom MeetingStore (SQLite WAL) gefüllt; aktuell aus MockData.

enum Platform: String, Codable, CaseIterable, Hashable {
    case teams = "TEAMS"
    case zoom  = "ZOOM"
    case meet  = "MEET"
    case call  = "CALL"

    var accent: Color {
        switch self {
        case .teams: return Neon.Speaker.indigo
        case .zoom:  return Neon.Speaker.blue
        case .meet:  return Neon.brandBright
        case .call:  return Neon.textTertiary
        }
    }
}

enum HighlightTone: String, Codable, CaseIterable {
    case brand     // grün (Entscheidung)
    case warning   // amber (Risiko)
    case info      // indigo (Termin)
}

enum TaskStatus: String, Codable, CaseIterable {
    case open
    case done
}

struct Participant: Identifiable, Codable, Hashable {
    let id: String          // Initialen, "NK"
    let name: String
    let role: String
    let colorHex: UInt32
    let spoke: String       // "11m 47s"

    var color: Color { Color(hex: colorHex) }
}

struct TranscriptLine: Identifiable, Codable, Hashable {
    var id: String { "\(who)-\(timestamp)" }
    let who: String         // Participant.id
    let timestamp: String   // "00:14"
    let body: String
    var highlight: Bool = false
}

struct Highlight: Identifiable, Codable, Hashable {
    let id: UUID
    let label: String
    let text: String
    let tone: HighlightTone

    init(id: UUID = UUID(), label: String, text: String, tone: HighlightTone) {
        self.id = id
        self.label = label
        self.text = text
        self.tone = tone
    }
}

struct ActionItem: Identifiable, Codable, Hashable {
    let id: String
    let who: String         // Participant.id
    let task: String
    let due: String         // "15. Mai"
    var status: TaskStatus
}

struct Chapter: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: String   // "02:14"
    let label: String
    let duration: String    // "6m"
}

struct MeetingSummary: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let date: String        // "10. Apr."
    let time: String        // "10:50"
    let duration: String    // "32m"
    let platform: Platform
    let wordCount: Int
    let group: String       // "Diesen Monat" / "Früher"
    let participantIds: [String]
    var unread: Bool = false
}

struct MeetingDetail: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let dateLong: String     // "Donnerstag, 10. April"
    let timeRange: String    // "10:50 – 11:22"
    let duration: String     // "32m 14s"
    let platform: Platform
    let wordCount: Int
    let participants: [Participant]
    let tldr: String
    let highlights: [Highlight]
    let tasks: [ActionItem]
    let chapters: [Chapter]
    let transcript: [TranscriptLine]

    var participantCount: Int { participants.count }
    var openTasks: Int { tasks.filter { $0.status == .open }.count }
}

struct LiveSession: Codable, Hashable {
    let startedAt: Date
    let device: String       // "Built-in Mic"
    let model: String        // "WhisperKit ANE"
    var lines: [TranscriptLine]
}
