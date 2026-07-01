import Foundation

/// Besitzt die sprecherübergreifende Identitäts-Logik eines Meetings: kanonische
/// ID-Auflösung, das Festschreiben von Caption-/Platform-Identitäten, das
/// Vorhalten von Meeting-Embeddings und die Rück-Migration bekannter Sprecher in
/// andere Meetings.
///
/// Vorher lag all das verstreut im `RecordingController` (God-Object), nur über
/// `lastEmbeddings`-State zusammengehalten — und die Caption-/Platform-Persister
/// waren bis auf `source`/`externalId` selbst dupliziert. Der Controller behält
/// `labelSpeaker` als Ein-Zeilen-Forward (er liefert seinen Embedding-Cache als
/// Fallback plus das Lizenz-Gate); der komplette Use-Case lebt in `label(...)`.
///
/// Speaker-Identity-Korrektheit ist ein harter Produkt-Invariant — dieses Modul
/// macht den Kern ohne den `@MainActor`-Controller testbar.
struct SpeakerIdentityCoordinator {
    let speakerStore: SpeakerStore

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

    // MARK: - Label-Use-Case

    /// Der komplette "User labelt S1 → Morgan"-Flow: Embedding auflösen,
    /// kanonische ID bestimmen, Profil upserten, das aktuelle Meeting migrieren
    /// und — wenn erlaubt — bekannte Stimmen in andere Meetings zurückschreiben.
    ///
    /// Embedding-Vorrang ist Teil des Kontrakts: das meeting-bezogen
    /// persistierte Embedding gewinnt IMMER vor `cachedEmbedding` (dem
    /// In-Memory-Cache der letzten Aufnahme). Andersherum würde das Labeln
    /// eines älteren Meetings das Embedding der neuesten Aufnahme ins Profil
    /// schreiben und cross-meeting backfillen — der historische Bug.
    ///
    /// Gibt zurück, wie viele weitere Meetings migriert wurden (UI-Feedback).
    ///
    /// `migratingIn` ist die EINE Stelle, die den MeetingStore braucht — nur
    /// Relabel/Backfill schreiben in Meetings. `nil` heißt bewusst: Profil
    /// upserten, aber keine Meeting-Migration (0 als Rückgabewert). Vorher hing
    /// diese Fähigkeit an einem optionalen Konstruktor-Argument, das drei von
    /// vier Call-Sites still wegließen.
    @discardableResult
    func label(
        meetingId: String?,
        internalId: String,
        name: String,
        colorHex: UInt32,
        knownSpeakerId: String? = nil,
        cachedEmbedding: [Float]? = nil,
        allowCrossMeetingBackfill: Bool,
        migratingIn store: MeetingStore?
    ) -> Int {
        let embedding = meetingId.flatMap { speakerStore.meetingEmbedding(meetingId: $0, internalId: internalId) }
            ?? cachedEmbedding
            ?? []
        let canonicalId = Self.canonicalId(
            name: name,
            knownSpeakerId: knownSpeakerId,
            existingSpeakers: speakerStore.speakers
        )
        if !embedding.isEmpty {
            speakerStore.upsert(id: canonicalId, name: name, embedding: embedding, colorHex: colorHex)
        } else {
            speakerStore.upsertIdentity(id: canonicalId, name: name, colorHex: colorHex)
        }
        if let meetingId, let store {
            migrate(meetingId: meetingId, from: internalId, to: canonicalId, name: name, colorHex: colorHex, in: store)
        }
        guard allowCrossMeetingBackfill, let store else { return 0 }
        return backfillCrossMeetings(
            embedding: embedding,
            canonicalId: canonicalId,
            name: name,
            colorHex: colorHex,
            currentMeetingId: meetingId,
            in: store
        )
    }

    /// Das Relabel+Rename-Paar — die EINE Stelle, die ein Meeting auf eine
    /// kanonische Speaker-ID migriert: Transcript-/Summary-Felder im
    /// MeetingStore plus die Embedding-Zeile im SpeakerStore. Vorher lag das
    /// Paar zweimal im Code (inline im Controller für das aktuelle Meeting,
    /// hier für den Backfill) — ein Fix musste zweimal gemacht werden.
    private func migrate(
        meetingId: String,
        from internalId: String,
        to canonicalId: String,
        name: String,
        colorHex: UInt32,
        in store: MeetingStore
    ) {
        store.relabelSpeaker(
            meetingId: meetingId,
            from: internalId,
            to: canonicalId,
            name: name,
            colorHex: colorHex
        )
        speakerStore.renameMeetingInternalId(meetingId: meetingId, from: internalId, to: canonicalId)
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
        currentMeetingId: String?,
        in store: MeetingStore
    ) -> Int {
        guard !embedding.isEmpty else { return 0 }
        let matches = speakerStore.meetingMatches(for: embedding, excluding: currentMeetingId)
        var seenMeetings: Set<String> = []
        var migrated = 0
        for match in matches {
            guard !seenMeetings.contains(match.meetingId) else { continue }
            guard match.internalId != canonicalId else {
                seenMeetings.insert(match.meetingId)
                continue
            }
            migrate(
                meetingId: match.meetingId,
                from: match.internalId,
                to: canonicalId,
                name: name,
                colorHex: colorHex,
                in: store
            )
            seenMeetings.insert(match.meetingId)
            migrated += 1
        }
        return migrated
    }
}
