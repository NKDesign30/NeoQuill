import Foundation

/// Besitzt die sprecherübergreifende Identitäts-Logik eines Meetings: kanonische
/// ID-Auflösung, das Festschreiben von Caption-/Platform-Identitäten, das
/// Vorhalten von Meeting-Embeddings und die Rück-Migration bekannter Sprecher in
/// andere Meetings.
///
/// Vorher lag all das verstreut im `RecordingController` (God-Object), nur über
/// `lastEmbeddings`-State zusammengehalten — und die Caption-/Platform-Persister
/// waren bis auf `source`/`externalId` selbst dupliziert. Der Controller behält
/// `labelSpeaker` als Einstieg (er liest `lastEmbeddings` + Lizenz) und delegiert
/// den Kern hierher.
///
/// Speaker-Identity-Korrektheit ist ein harter Produkt-Invariant — dieses Modul
/// macht den Kern ohne den `@MainActor`-Controller testbar.
struct SpeakerIdentityCoordinator {
    let speakerStore: SpeakerStore
    let store: MeetingStore?

    init(speakerStore: SpeakerStore, store: MeetingStore? = nil) {
        self.speakerStore = speakerStore
        self.store = store
    }

    /// Woher die Identität einer Zeile stammt — Plattform-Caption (live im
    /// Meeting getippt) oder Plattform-API (nachträglich importiert). Die einzige
    /// Differenz, die früher zwei fast identische Persister rechtfertigte.
    enum IdentityKind {
        case caption
        case platform

        var lineSource: SpeakerIdentitySource {
            switch self {
            case .caption: return .caption
            case .platform: return .platformApi
            }
        }
        var aliasSource: String {
            switch self {
            case .caption: return "caption"
            case .platform: return "platform"
            }
        }
        func externalId(for who: String) -> String? {
            switch self {
            case .caption: return nil
            case .platform: return who
            }
        }
    }

    // MARK: - Pure Auflösung (ohne Stores testbar)

    /// Eine explizit bekannte ID gewinnt; sonst gewinnt ein bestehender Speaker
    /// per Name-Match; sonst eine neu generierte Slug-ID.
    static func canonicalId(
        name: String,
        knownSpeakerId: String? = nil,
        existingSpeakers: [LabeledSpeaker] = []
    ) -> String {
        if let knownSpeakerId = knownSpeakerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !knownSpeakerId.isEmpty {
            return knownSpeakerId
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedSpeakerName(trimmed)
        if !normalized.isEmpty,
           let existing = existingSpeakers.first(where: { normalizedSpeakerName($0.name) == normalized }) {
            return existing.id
        }
        return generatedSpeakerId(for: trimmed)
    }

    private static func normalizedSpeakerName(_ name: String) -> String {
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func generatedSpeakerId(for name: String) -> String {
        let separator = UnicodeScalar("-")
        let folded = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var scalars: [UnicodeScalar] = []
        var lastWasSeparator = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                scalars.append(separator)
                lastWasSeparator = true
            }
        }
        if scalars.last == separator {
            scalars.removeLast()
        }
        let slug = String(String.UnicodeScalarView(scalars))
        return slug.isEmpty ? "speaker-unknown" : "speaker-\(slug)"
    }

    // MARK: - Persistenz

    /// Schreibt Caption- bzw. Platform-Identitäten + Aliase fest. Pro `who`-ID
    /// nur einmal; lokaler Sprecher und namenlose Zeilen werden übersprungen.
    func persistIdentities(from lines: [TranscriptLine], platform: Platform, kind: IdentityKind) {
        var seen: Set<String> = []
        for line in lines where line.speakerSource == kind.lineSource {
            guard !LocalSpeakerProfile.isLocalSpeakerId(line.who),
                  let displayName = line.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty,
                  !seen.contains(line.who)
            else { continue }
            seen.insert(line.who)
            speakerStore.upsertIdentity(
                id: line.who,
                name: displayName,
                colorHex: SpeakerPalette.color(for: line.who)
            )
            speakerStore.upsertAlias(
                speakerId: line.who,
                alias: displayName,
                source: kind.aliasSource,
                platform: platform,
                externalId: kind.externalId(for: line.who)
            )
        }
    }

    func recordMeetingEmbeddings(meetingId: String, embeddings: [String: [Float]]) {
        guard !embeddings.isEmpty else { return }
        for (internalId, embedding) in embeddings where !embedding.isEmpty {
            speakerStore.recordMeetingEmbedding(
                meetingId: meetingId,
                internalId: internalId,
                embedding: embedding
            )
        }
    }

    /// Sucht Embedding-Treffer in anderen Meetings und migriert sie auf den
    /// jetzt bekannten Speaker. Pro Meeting höchstens ein Treffer (der mit dem
    /// höchsten Score), damit ein Speaker nicht zwei Slots im selben Meeting
    /// belegt. Gibt die Anzahl migrierter Meetings zurück.
    func backfillCrossMeetings(
        embedding: [Float],
        canonicalId: String,
        name: String,
        colorHex: UInt32,
        currentMeetingId: String?
    ) -> Int {
        guard !embedding.isEmpty, let store else { return 0 }
        let matches = speakerStore.meetingMatches(for: embedding, excluding: currentMeetingId)
        var seenMeetings: Set<String> = []
        var migrated = 0
        for match in matches {
            guard !seenMeetings.contains(match.meetingId) else { continue }
            guard match.internalId != canonicalId else {
                seenMeetings.insert(match.meetingId)
                continue
            }
            store.relabelSpeaker(
                meetingId: match.meetingId,
                from: match.internalId,
                to: canonicalId,
                name: name,
                colorHex: colorHex
            )
            speakerStore.renameMeetingInternalId(
                meetingId: match.meetingId,
                from: match.internalId,
                to: canonicalId
            )
            seenMeetings.insert(match.meetingId)
            migrated += 1
        }
        return migrated
    }
}
