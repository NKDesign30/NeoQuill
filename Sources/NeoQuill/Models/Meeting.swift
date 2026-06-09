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
    let id: String          // stabile Speaker-ID, z.B. "ME" oder "S1"
    let name: String
    let role: String
    let colorHex: UInt32
    let spoke: String       // "11m 47s"

    var color: Color { Color(hex: colorHex) }
}

enum TranscriptSource: String, Codable, Hashable {
    case mic
    case system
    case caption
    case platformApi
    case merged
}

enum SpeakerIdentitySource: String, Codable, Hashable {
    case microphoneOwner
    case caption
    case platformApi
    case knownVoice
    case diarization
    case manual
    case unknown
}

struct TranscriptLine: Identifiable, Codable, Hashable {
    let id: UUID
    var who: String         // Participant.id
    var displayName: String?
    var timestamp: String   // "00:14"
    var startSeconds: TimeInterval
    var endSeconds: TimeInterval
    var body: String
    var source: TranscriptSource
    var speakerSource: SpeakerIdentitySource
    var confidence: Double
    var highlight: Bool

    init(
        id: UUID = UUID(),
        who: String,
        displayName: String? = nil,
        timestamp: String,
        startSeconds: TimeInterval? = nil,
        endSeconds: TimeInterval? = nil,
        body: String,
        source: TranscriptSource = .merged,
        speakerSource: SpeakerIdentitySource = .unknown,
        confidence: Double = 1.0,
        highlight: Bool = false
    ) {
        let resolvedStart = startSeconds ?? (TranscriptTimecode.parse(timestamp) ?? 0)
        self.id = id
        self.who = who
        self.displayName = displayName
        self.timestamp = timestamp
        self.startSeconds = resolvedStart
        self.endSeconds = max(endSeconds ?? resolvedStart, resolvedStart)
        self.body = body
        self.source = source
        self.speakerSource = speakerSource
        self.confidence = confidence
        self.highlight = highlight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try c.decode(String.self, forKey: .timestamp)
        let start = try c.decodeIfPresent(TimeInterval.self, forKey: .startSeconds) ?? (TranscriptTimecode.parse(timestamp) ?? 0)
        let source = try c.decodeIfPresent(TranscriptSource.self, forKey: .source) ?? .merged
        let who = try c.decode(String.self, forKey: .who)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.who = who
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.timestamp = timestamp
        self.startSeconds = start
        self.endSeconds = max(try c.decodeIfPresent(TimeInterval.self, forKey: .endSeconds) ?? start, start)
        self.body = try c.decode(String.self, forKey: .body)
        self.source = source
        self.speakerSource = try c.decodeIfPresent(SpeakerIdentitySource.self, forKey: .speakerSource)
            ?? (LocalSpeakerProfile.isLocalSpeakerId(who) ? .microphoneOwner : .unknown)
        self.confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        self.highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
    }
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
    var audioURL: String? = nil    // Pfad zur WAV-Datei in Application Support
    var lifecycle: MeetingLifecycle = .done   // Single Source of Truth für den Verarbeitungsstand

    /// Abgeleitete "läuft gerade etwas?"-Sicht für die UI. Früher ein eigenes
    /// gespeichertes Feld; jetzt aus `lifecycle` abgeleitet, damit beide nie
    /// auseinanderlaufen können.
    var processing: Bool { lifecycle.isBusy }

    var participantCount: Int { participants.count }
    var openTasks: Int { tasks.filter { $0.status == .open }.count }

    /// Kopiert das Detail und ersetzt nur die übergebenen Felder; alles andere
    /// bleibt unverändert. Identität und Zeitfelder (`id`, `dateLong`,
    /// `timeRange`, `duration`, `platform`) sind bewusst nicht änderbar — sie
    /// gehören zur Aufnahme, nicht zum Verarbeitungsstand.
    ///
    /// Single Source der „ein Feld ändern"-Kopie: vorher hatte `RecordingController`
    /// dafür einen privaten Helfer, während `MeetingStore` denselben 15-Felder-Copy
    /// von Hand nachbaute — beim Hinzufügen von `audioURL`/`lifecycle` musste jede
    /// Hand-Kopie separat nachgezogen werden.
    ///
    /// `audioURL` folgt der bestehenden Semantik (`nil` = unverändert lassen); ein
    /// Detail mit gelöschtem Audio wird weiterhin über den vollen Initializer gebaut.
    func with(
        title: String? = nil,
        wordCount: Int? = nil,
        participants: [Participant]? = nil,
        tldr: String? = nil,
        highlights: [Highlight]? = nil,
        tasks: [ActionItem]? = nil,
        chapters: [Chapter]? = nil,
        transcript: [TranscriptLine]? = nil,
        audioURL: String? = nil,
        lifecycle: MeetingLifecycle? = nil
    ) -> MeetingDetail {
        MeetingDetail(
            id: id,
            title: title ?? self.title,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: duration,
            platform: platform,
            wordCount: wordCount ?? self.wordCount,
            participants: participants ?? self.participants,
            tldr: tldr ?? self.tldr,
            highlights: highlights ?? self.highlights,
            tasks: tasks ?? self.tasks,
            chapters: chapters ?? self.chapters,
            transcript: transcript ?? self.transcript,
            audioURL: audioURL ?? self.audioURL,
            lifecycle: lifecycle ?? self.lifecycle
        )
    }
}

struct LiveSession: Codable, Hashable {
    let startedAt: Date
    let device: String       // "Built-in Mic"
    let model: String        // "WhisperKit ANE"
    var lines: [TranscriptLine]
}
