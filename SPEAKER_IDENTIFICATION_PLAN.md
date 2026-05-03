# NeoQuill Speaker Identification Plan

Stand: 2026-05-03

Ziel: NeoQuill soll Sprecher in Teams-, Zoom- und Google-Meet-Calls so gut wie möglich mit echten Namen anzeigen. Audio-Diarization bleibt Fallback. Echte Namen kommen bevorzugt aus Meeting-Captions, offiziellen Transkripten oder Plattform-Roster-Daten.

## Kurzentscheidung

Wir bauen es.

Nicht als "Audio errät Namen"-Feature. Das geht technisch nicht zuverlässig. Die robuste Lösung ist eine Prioritätskette:

1. Live-Captions der Meeting-App mit Speaker-Namen lesen.
2. Offizielle Post-Meeting-Transkripte per API nachziehen, wenn Account/Org das erlaubt.
3. Bekannte Stimmen per lokalem SpeakerStore wiedererkennen.
4. Unbekannte Stimmen als `S1`, `S2`, `S3` diarisiert anzeigen und vom User labeln lassen.

MVP: lokale Caption-Erfassung + Merge in NeoQuills Transcript. Danach API-Reconciliation.

## Umsetzungsstatus

- [x] Feature-Branch angelegt: `feat/speaker-identification-mvp`.
- [x] Verkaufstaugliches lokales User-Profil eingeführt: interne Mic-Speaker-ID `ME`, alte `NK`-ID nur noch Legacy-Migration.
- [x] Profil-Onboarding gebaut: erster Start fragt Name/Rolle und speichert lokal.
- [x] Settings erweitert: Name/Rolle editierbar, Live-Caption-Capture Toggle, Accessibility-Status.
- [x] `TranscriptLine` erweitert: stabile UUID, Start-/Endzeit, Quelle, Speaker-Quelle, Confidence, Display-Name.
- [x] Rückwärtskompatibler Decoder für alte Transcript-Daten.
- [x] `FinalSTTTranscriber` und `LiveTranscriber` schreiben Zeitintervalle und Mic/System-Quelle.
- [x] `CaptionEvent` Modell angelegt.
- [x] `CaptionCaptureService` angelegt: macOS Accessibility, App-Erkennung, AX-Tree-Scan, Caption-Dedupe.
- [x] `TranscriptMerger` angelegt: Caption-Namen gewinnen vor Diarization, lokale Mic-Spur bleibt lokal.
- [x] `RecordingController` verdrahtet Caption-Capture Start/Stop und Merge nach Final-STT.
- [x] Recording-UI zeigt Caption-Status und Event-Anzahl.
- [x] Caption-Namen werden als Speaker-Identität/Alias im `SpeakerStore` gespeichert.
- [x] `SpeakerStore` v2 gebaut: Aliase + mehrere Embeddings pro Speaker, Legacy-Embedding-Migration.
- [x] Unit Tests für `TranscriptMerger` und Legacy-`TranscriptLine`-Migration.
- [x] `PlatformTranscriptEvent` Modell angelegt.
- [x] Parser ohne OAuth gebaut: Teams/Zoom WebVTT, Teams `metadataContent`, Google Meet Entries+Participants, Zoom Timeline.
- [x] Spezifische Provider-Parser ergänzt: `TeamsTranscriptParser`, `GoogleMeetTranscriptParser`, `ZoomTranscriptParser`.
- [x] `TranscriptMerger` erweitert: Platform-API-Events gewinnen vor Live-Captions.
- [x] Parser-Fixture-Tests für Teams VTT/metadataContent, Google Meet Entries, Zoom Timeline.
- [x] Caption-Textparser extrahiert und getestet: Speaker-Splitting, UI-Control-Filter, Dedupe-Fingerprint.
- [x] Optionaler AX-Debug-Dump hinter UserDefault `caption_debug_dump`.
- [x] Personenbezogene Demo-/Produktstrings bereinigt.
- [x] `swift build` grün.
- [x] `swift test` grün: 47 Tests, 0 Fehler.
- [ ] Echte Teams/Zoom/Meet Live-QA mit aktiven Captions.
- [x] Dedizierte Unit Tests für AX-Caption-Dedupe.
- [ ] Teams Graph OAuth/API-Abruf.
- [ ] Google Meet OAuth/API-Abruf.
- [ ] Zoom OAuth/API-Abruf.

## Ist-Zustand in NeoQuill

Relevante Dateien:

- `Sources/NeoQuill/Services/RecordingController.swift`
- `Sources/NeoQuill/Services/SpeakerDiarizer.swift`
- `Sources/NeoQuill/Services/SpeakerStore.swift`
- `Sources/NeoQuill/Services/FinalSTTTranscriber.swift`
- `Sources/NeoQuill/Services/AudioCapture.swift`
- `Sources/NeoQuill/Models/Meeting.swift`
- `Sources/NeoQuill/Views/Detail/ParticipantBar.swift`
- `Sources/NeoQuill/Views/Detail/SpeakerLabelSheet.swift`

Was vor diesem Patch schon da war:

- Dual-Stream-Aufnahme: Mic war `NK`, System-Audio ist Remote-Seite.
- Final-STT transkribiert Mic und System getrennt.
- FluidAudio-Diarization läuft optional auf System-Audio.
- `SpeakerStore` persistiert gelabelte Speaker-Embeddings in SQLite.
- UI kann anonyme Speaker über `SpeakerLabelSheet` labeln.

Was dieser Patch geändert hat:

- Mic-Speaker ist jetzt produktneutral `ME`.
- Name/Rolle kommen aus lokalem Onboarding/Settings.
- `NK` bleibt nur als Legacy-ID für alte lokale Daten.

Hauptprobleme:

- `TranscriptLine` hat nur `timestamp: String`, keine `startSeconds`/`endSeconds`.
- `mergeSpeakers` matched aktuell nur den Startzeitpunkt gegen Diarization-Segmente.
- `SpeakerDiarizer.mapToTranscriptSegments` ist noch Stub.
- Captions/Plattformdaten existieren im Modell nicht.
- Ein Speaker kann mehrere Embeddings brauchen, nicht nur eins.
- Echte Namen kommen aktuell nur durch manuelles Labeling.

## Online-Recherche: Quellen und Schlussfolgerungen

### Microsoft Teams

Quelle: Microsoft Graph `callTranscript`  
URL: https://learn.microsoft.com/en-us/graph/api/calltranscript-get?view=graph-rest-1.0

Relevanz:

- Graph kann Teams-Transkripte für Online-Meetings abrufen.
- Content kann als VTT geholt werden.
- `metadataContent` enthält strukturierte Einträge mit `speakerName`, `spokenText`, `startDateTime`, `endDateTime`, `spokenLanguage`.
- Braucht Microsoft-Account, Berechtigungen und hängt an Meeting-/Tenant-Policy.

Nutzen für NeoQuill:

- Post-Meeting-Reconcile für echte Namen.
- Sehr gute Quelle, wenn User/Org Zugriff auf Transcript hat.
- Nicht als einziger MVP geeignet, weil nicht jedes Meeting Transcript aktiviert hat.

Quelle: Teams Live Captions Support  
URL: https://support.microsoft.com/en-us/office/use-live-captions-in-microsoft-teams-meetings-4be2d304-f675-4b57-8347-cbd000a21260

Relevanz:

- Teams zeigt Live-Captions in Meetings.
- Teilnehmer können ihre Identität in Captions/Transkripten verstecken.
- Teams speichert Captions nicht automatisch; für spätere Transkripte muss Transcription aktiv sein.

Nutzen für NeoQuill:

- Live-Caption-Capture ist sinnvoll, weil Captions sonst verschwinden.
- UI muss "Name hidden"/anonym akzeptieren.

Quelle: Teams Real-Time Media Bots  
URL: https://learn.microsoft.com/en-us/microsoftteams/platform/bots/calls-and-meetings/real-time-media-concepts

Relevanz:

- Teams Bots können in Advanced/Compliance-Szenarien Audioframes und aktive/dominante Speaker sehen.
- Microsoft empfiehlt für Meeting-Intelligence eher Graph-Transkripte statt Real-Time-Media-Bots.
- Bots sind komplex, serverseitig, Enterprise-lastig.

Nutzen für NeoQuill:

- Nicht MVP.
- Später Enterprise-Modus möglich, aber zu schwer für lokale Mac-App v1.

Quelle: GitHub `Zerg00s/Live-Captions-Saver`  
URL: https://github.com/Zerg00s/Live-Captions-Saver

Relevanz:

- Chrome Extension für Teams Web.
- Captures Live-Captions lokal.
- Features: Speaker Identification/Aliasing, Attendee Tracking, Export.

Nutzen für NeoQuill:

- Belegt: DOM/Extension-basierter Capture ist machbar.
- Guter Referenzpunkt für Teams-Web-Adapter.

### Google Meet

Quelle: Google Meet API Transcript Entries  
URL: https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords.transcripts.entries

Relevanz:

- `TranscriptEntry` enthält `participant`, `text`, `startTime`, `endTime`, `languageCode`.
- Entries sind strukturierte Transcript-Zeilen.

Nutzen für NeoQuill:

- Post-Meeting-Reconcile ähnlich Teams.
- `participant` muss über Participants API in Namen aufgelöst werden.

Quelle: Google Meet API Participants  
URL: https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords.participants

Relevanz:

- Participants enthalten `displayName` für signed-in, anonymous und phone users.
- Join-/Leave-Zeiten sind verfügbar.

Nutzen für NeoQuill:

- Mapping `TranscriptEntry.participant -> displayName`.
- Hilft auch bei Meeting-Roster/Teilnehmerliste.

Quelle: GitHub / Extension-Beispiel `sughodke/google-meet-transcripts`  
URL: https://github.com/sughodke/google-meet-transcripts

Relevanz:

- Browser-Extension-Ansatz für Google-Meet-Transkripte.
- Belegt, dass lokale Caption-/DOM-Erfassung für Meet praktikabel ist.

Nutzen für NeoQuill:

- Referenz für Meet-Web-Adapter.

### Zoom

Quelle: Zoom Meeting SDK macOS `ZoomSDKMeetingActionController`  
URL: https://marketplacefront.zoom.us/sdk/meeting/macos/interface_zoom_s_d_k_meeting_action_controller.html

Relevanz:

- SDK kann Teilnehmerliste abrufen (`getParticipantsList`) und User-Infos per `getUserByUserID`.
- Gut für Roster-Daten, aber nicht automatisch für Caption-Text im normalen Zoom-Client.

Nutzen für NeoQuill:

- Später möglich, wenn NeoQuill selbst per SDK einem Meeting beitritt oder einen Bot-Modus bekommt.
- Nicht MVP für normale "Zoom läuft schon"-App.

Quelle: Zoom DevForum: Speaker names in transcript  
URL: https://devforum.zoom.us/t/unable-to-get-speaker-names-in-a-transcript/5439

Relevanz:

- Zoom-Transkripte hatten/haben je nach Datei/Export teils IDs statt Namen.
- Forum-Hinweis: TIMELINE-Datei kann Speaker-Namen und Timestamps enthalten, Timestamps alignen aber nicht exakt.

Nutzen für NeoQuill:

- Zoom-Post-Processing braucht tolerantem Time-Alignment.
- Nicht nur `.vtt` blind parsen; Recording-Payload/TIMELINE prüfen.

Quelle: Zoom DevForum: Real-time transcript with speaker names in browser  
URL: https://devforum.zoom.us/t/how-to-extract-zoom-meeting-transcripts-in-real-time-along-with-speaker-names-in-browser/129617

Relevanz:

- Entwickler fragen genau nach DOM/Captions/Speaker-Namen in Zoom Web.
- Zeigt: API-Lösung ist nicht trivial/offensichtlich.

Nutzen für NeoQuill:

- Für Zoom MVP lieber lokale Captions lesen statt auf eine perfekte API warten.

### Plattformübergreifende Belege

Quelle: CaptionSnap  
URL: https://captionsnap.app/

Relevanz:

- macOS-App liest Meeting-Captions lokal.
- Unterstützt Teams, Zoom, Google Meet.
- Verspricht echte Speaker-Namen aus der Meeting-App, ohne Audio/Bot/Cloud.
- Benötigt macOS Accessibility Permission.

Nutzen für NeoQuill:

- Starker Produktbeleg: Genau dieser Ansatz ist für macOS machbar.
- Unser MVP kann denselben Prinzipweg gehen: Accessibility/Window-Caption-Capture.

Quelle: Vexa Open Source Meeting Bot API  
URL: https://github.com/Vexa-ai/vexa  
Docs: https://docs.vexa.ai/

Relevanz:

- Open-source Meeting-Bot/API für Google Meet, Teams und Zoom.
- Realtime Transcripts via REST/WebSocket, per Speaker segmentiert.
- Bot-basierter Ansatz, self-hostbar, stärker Backend-/Infra-lastig.

Nutzen für NeoQuill:

- Gute Inspiration für späteren Bot-/Enterprise-Modus.
- Nicht nötig für lokalen Mac-MVP.

## Zielarchitektur

Neue Pipeline:

```text
Meeting App
  ├─ AudioCapture
  │   ├─ Mic -> FinalSTT -> speaker ME
  │   └─ System Audio -> FinalSTT + FluidAudio -> S1/S2 fallback
  │
  ├─ CaptionCaptureService
  │   └─ Teams/Zoom/Meet captions -> CaptionEvent(speakerName, text, time)
  │
  └─ PlatformTranscriptProvider
      ├─ Teams Graph transcript/metadataContent
      ├─ Google Meet transcript entries + participants
      └─ Zoom cloud/timeline transcript, optional

TranscriptMerger
  ├─ prefers CaptionEvent names
  ├─ reconciles API transcript after meeting
  ├─ maps known SpeakerStore embeddings
  └─ keeps S1/S2 where identity is unknown
```

Speaker-Quelle nach Priorität:

1. `captionSpeakerName` mit Zeit/Text-Match.
2. `apiSpeakerName` aus Teams Graph / Google Meet / Zoom Recording.
3. `knownSpeakerId` aus `SpeakerStore.bestMatch`.
4. `diarizedSpeakerId` aus FluidAudio.
5. `Unknown`.

## Datenmodell ändern

`TranscriptLine` braucht echte Zeitintervalle und Metadaten.

Vorschlag:

```swift
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
    var who: String
    var displayName: String?
    var timestamp: String
    var startSeconds: TimeInterval
    var endSeconds: TimeInterval
    var body: String
    var source: TranscriptSource
    var speakerSource: SpeakerIdentitySource
    var confidence: Double
    var highlight: Bool
}
```

Kompatibilität:

- Alte JSON/SQLite-Daten per Decoder-Defaults migrieren.
- Wenn nur `timestamp` existiert: `startSeconds = parseTimestampSeconds(timestamp)`, `endSeconds = startSeconds`.
- `id` nicht mehr aus `who-timestamp` ableiten, weil mehrere Lines gleiche Sekunde haben können.

Zusätzlich:

```swift
struct CaptionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let platform: Platform
    let appBundleIdentifier: String?
    let speakerName: String?
    let speakerHandle: String?
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval?
    let observedAt: Date
    let confidence: Double
    let rawPayload: String?
}
```

`SpeakerStore` erweitern:

- Mehrere Embeddings pro Speaker speichern.
- Aliase speichern (`Thorsten`, `Thorsten K.`, Teams Display Name).
- `platformIdentity` speichern, z.B. Microsoft AAD ID, Google participant resource, Zoom user ID.
- `lastSeenPlatform`, `lastSeenMeetingId`.

Tabellen-Idee:

```sql
speaker(id, canonical_name, color_hex, created_at, last_seen_at)
speaker_embedding(id, speaker_id, embedding_json, duration, quality, created_at)
speaker_alias(id, speaker_id, alias, source, platform, external_id, created_at)
```

## Neue Services

### `CaptionCaptureService`

Aufgabe:

- Beobachtet aktive Meeting-App.
- Erkennt Teams/Zoom/Meet Caption-UI.
- Emits `CaptionEvent`.
- Läuft lokal, ohne Netzwerk.

Implementierung v1:

- macOS Accessibility API.
- Benötigt Accessibility Permission.
- Polling + AXObserver:
  - aktive App vom `MeetingDetector`
  - Window-Titel/Bundle-ID erkennen
  - Caption-Text nodes extrahieren
  - Dedupe über `(speakerName, normalizedText, timeWindow)`

Warum Accessibility zuerst:

- Funktioniert auch für native Desktop-Apps.
- CaptionSnap belegt das als macOS-Produktansatz.
- Keine Browser-Extension-Installation nötig.

Fallback v1.5:

- Browser-DOM Adapter für Teams Web / Meet / Zoom Web über Extension oder lokalem Companion.
- Referenzen: `Live-Captions-Saver`, `google-meet-transcripts`.

### `PlatformTranscriptProvider`

Aufgabe:

- Nach Meeting-Ende offizielle Plattform-Transkripte importieren.
- Events in ein gemeinsames Format normalisieren.

Provider:

- `TeamsGraphTranscriptProvider`
- `GoogleMeetTranscriptProvider`
- `ZoomRecordingTranscriptProvider`

MVP erst als Interface + Mock/Import von Datei bauen, OAuth später.

### `TranscriptMerger`

Aufgabe:

- Audio-STT, Captions, Plattform-Transcript und Diarization zu einem finalen Transcript zusammenführen.

Input:

- `[TranscriptLine]` aus Mic/System STT.
- `[CaptionEvent]` live.
- `[PlatformTranscriptEvent]` post-meeting.
- `[DiarizationSegment]`.

Merge-Regeln:

1. Mic-Lines bleiben `ME`, außer User stellt das explizit um.
2. Caption-Event mit Speaker-Name gewinnt gegen Diarization, wenn Text ähnlich und Zeit nah ist.
3. API-Transcript gewinnt gegen Caption-Capture, wenn Zeit/Text besser segmentiert ist.
4. Diarization füllt nur fehlende Speaker.
5. Manual Label gewinnt dauerhaft.

Text-Match:

- Normalisieren: lowercased, Whitespace, Satzzeichen reduzieren.
- Similarity: Token-Jaccard oder Levenshtein-Ratio.
- Window: ±3 Sekunden für Captions, ±8 Sekunden für Zoom Timeline.
- Bei Overlap: größter Intersection-over-Union auf Zeitintervall.

Pseudocode:

```swift
for line in audioLines {
    if line.source == .mic {
        keepLocalSpeaker(line)
        continue
    }

    if let caption = bestCaptionMatch(line, captions) {
        applySpeaker(caption.speakerName, source: .caption, confidence: caption.confidence)
        continue
    }

    if let api = bestApiMatch(line, platformTranscript) {
        applySpeaker(api.speakerName, source: .platformApi, confidence: api.confidence)
        continue
    }

    if let known = bestKnownVoiceMatch(line, diarization, speakerStore) {
        applySpeaker(known.name, source: .knownVoice, confidence: known.score)
        continue
    }

    if let diarized = bestDiarizationMatch(line, diarization) {
        applySpeaker(diarized.id, source: .diarization, confidence: diarized.confidence)
    }
}
```

## Umsetzung von Anfang bis Ende

### Phase 0: Safety, Consent, Settings

Ziel:

- Feature sauber aktivierbar machen.
- Kein heimliches Capturing.

Tasks:

- Setting `Capture live captions` hinzufügen.
- Permission-Flow für Accessibility bauen/anzeigen.
- Meeting-Start-Hinweis: "Captions werden lokal aus der Meeting-App gelesen."
- Privacy-Text in Settings: keine Caption-Daten verlassen den Mac.
- Wenn Plattform "Identity hidden" liefert: als `Unknown` respektieren.

Akzeptanz:

- Ohne aktiviertes Setting läuft kein Caption-Capture.
- Ohne Accessibility Permission zeigt NeoQuill einen klaren Status.

### Phase 1: Datenmodell und Migration

Tasks:

- `TranscriptLine` um `id`, `startSeconds`, `endSeconds`, `source`, `speakerSource`, `confidence`, `displayName` erweitern.
- Decoder rückwärtskompatibel machen.
- `FinalSTTTranscriber` soll Whisper-Segment-Endzeiten übernehmen, nicht nur Startzeit.
- `LiveTranscriber`/WhisperKit-Pfad ebenfalls anpassen.
- `MeetingExporter` prüfen, damit Markdown/JSON alte und neue Felder sauber exportiert.

Akzeptanz:

- Alte Meetings öffnen weiter.
- Neue Lines haben stabile UUIDs und Sekundenintervalle.

### Phase 2: Caption-Capture MVP

Tasks:

- `CaptionCaptureService.swift` anlegen.
- `CaptionEvent` Modell anlegen.
- Teams/Zoom/Meet Fenster anhand Bundle-ID und Window-Titel erkennen.
- AX-Tree lesen und Caption-Kandidaten extrahieren.
- Dedupe bauen.
- Capture-Events temporär im `RecordingController` sammeln.

Start mit Teams:

- Teams hat die beste Quellenlage durch Graph + Live-Captions-Saver.
- Danach Meet.
- Zoom zuletzt, weil native App/Browser/Recording-Varianten stärker auseinanderlaufen.

Akzeptanz:

- Bei laufendem Teams-Call mit aktivierten Captions erscheinen `CaptionEvent`s mit Namen/Text/Zeit.
- Duplicate Captions werden nicht mehrfach gespeichert.
- CPU bleibt niedrig.

### Phase 3: Merge in Recording Flow

Tasks:

- `TranscriptMerger.swift` bauen.
- `RecordingController.persistMeeting` nach `transcribeFinalAudio` den Merger aufrufen lassen.
- `mergeSpeakers` ersetzen oder intern auf `TranscriptMerger` umleiten.
- `participants = collectParticipants(...)` soll `displayName` und `speakerSource` respektieren.
- Participant-Bar zeigt echte Namen aus Captions.

Akzeptanz:

- Teams-Caption "Thorsten: ..." wird im finalen Transcript als Thorsten angezeigt.
- System-Audio ohne Caption bleibt `S1/S2`.
- `ME` bleibt stabil auf Mic.

### Phase 4: SpeakerStore v2

Tasks:

- Schema migrieren auf Speaker, Embeddings, Aliases.
- Beim Caption-Match Alias speichern: `displayName -> speakerId`.
- Beim manuellen Labeln:
  - Alias hinzufügen.
  - Alle vorhandenen Embeddings des anonymen Speakers übernehmen.
  - Bestehende Meetings rückwirkend aktualisieren.
- `bestMatch` gegen mehrere Embeddings pro Speaker laufen lassen.

Akzeptanz:

- Wenn Thorsten einmal aus Captions erkannt wurde, kann seine Stimme später auch ohne Captions erkannt werden.
- Manuelles Labeling überschreibt Caption-Namen nicht blind, sondern legt Alias/Kanon-Namen fest.

### Phase 5: Offizielle APIs als Post-Meeting-Reconcile

Teams zuerst:

- OAuth/Microsoft Graph einrichten.
- Meeting-ID aus Kalender/Teams-Link/Detector ableiten.
- `/transcripts/{id}/metadataContent` importieren.
- `speakerName` + `spokenText` + Zeiten in `PlatformTranscriptEvent` mappen.

Google Meet:

- OAuth Google Workspace.
- `conferenceRecords.transcripts.entries` importieren.
- `participant` per `conferenceRecords.participants` zu `displayName` auflösen.

Zoom:

- Cloud Recording/Transcript Import.
- Timeline-Datei berücksichtigen, weil Speaker-Namen dort eher stehen können.
- Timestamps tolerant alignen.

Akzeptanz:

- Nach Meeting-Ende kann NeoQuill "Namen verbessern" ausführen.
- Änderungen sind nachvollziehbar, nicht still kaputt.

### Phase 6: UI

Tasks:

- Settings:
  - Live Captions Capture Toggle.
  - Accessibility Permission Status.
  - Plattform-API Connect Buttons später.
- Recording Status:
  - "Captions erkannt: Teams"
  - "Captions aktiv, aber keine Speaker-Namen"
  - "Captions nicht sichtbar"
- Detail:
  - Speaker Source Badge optional: Caption/API/Voice/Manual.
  - Confidence nur im Debug/Inspector, nicht prominent.
- Label Sheet:
  - Aliase anzeigen.
  - "Diesen Namen als kanonisch speichern".

Akzeptanz:

- User versteht, warum Speaker echt/unknown sind.
- Kein Debug-Lärm in der Haupt-UI.

### Phase 7: Diarization-Qualität fixen

Tasks:

- `SpeakerDiarizer.mapToTranscriptSegments` entfernen oder implementieren.
- FluidAudio Offline-Diarizer prüfen, falls verfügbar/stabiler als `DiarizerManager`.
- Diarization-Segmente mit Mindestdauer/Qualität filtern.
- Overlap-Matching statt nur Startzeit.
- Speaker-Durations korrekt aus Segmenten berechnen, nicht `baseDuration` für alle.

Akzeptanz:

- `S1/S2` wechseln weniger zufällig.
- Sprechanteil-Bar zeigt echte Zeiten.
- Reprocess nutzt dieselbe Merge-Logik wie neue Aufnahmen.

### Phase 8: Tests

Unit Tests:

- Timestamp parsing.
- Caption dedupe.
- Text similarity.
- Merge-Prioritäten.
- Migration alter `TranscriptLine`.
- SpeakerStore multi-embedding best match.

Fixture Tests:

- Teams VTT/metadataContent Sample.
- Google Meet TranscriptEntry + Participant Sample.
- Zoom VTT + Timeline Sample.
- CaptionEvent stream mit Duplikaten.

Manual QA:

- Teams native app, Captions an.
- Teams web, Captions an.
- Google Meet Chrome, Captions an.
- Zoom native app, Captions an.
- Captions aus.
- Speaker versteckt/anonym.
- Zwei Remote-Speaker sprechen schnell nacheinander.
- Lokaler User spricht über Mic während Remote spricht.

## Empfohlene Reihenfolge für Neo

1. [x] Branch: `feat/speaker-identification-mvp`.
2. [x] `TranscriptLine` Modell + Migration.
3. [x] `CaptionEvent` + `CaptionCaptureService` Skeleton.
4. [x] Accessibility Adapter für Teams/Zoom/Meet-Bundle-Erkennung.
5. [x] `TranscriptMerger` mit Tests.
6. [x] Recording Flow an Merger anschließen.
7. [x] UI-Status minimal anzeigen.
8. [x] SpeakerStore v2.
9. [x] Parser-Grundlage für Teams Graph Import.
10. [x] Parser-Grundlage für Meet Import.
11. [x] Parser-Grundlage für Zoom Import.

## Risiken

- Accessibility UI-Strukturen ändern sich je nach App-Version.
- Captions müssen in der Meeting-App aktiviert sein.
- Teams erlaubt versteckte Identität.
- API-Zugriff hängt an Tenant/OAuth/Policies.
- Zoom liefert je nach Recording/Transcript-Format unterschiedliche Speaker-Daten.
- Caption-Zeitstempel sind Beobachtungszeit, nicht zwingend exakte Sprachzeit.

Mitigation:

- Caption-Capture als "best effort" anzeigen.
- API-Reconcile später verbessert Namen.
- Audio-Diarization bleibt Fallback.
- Manuelles Labeling bleibt immer möglich.

## Definition of Done

MVP ist fertig, wenn:

- NeoQuill in einem Teams-Call Live-Captions lokal erkennt.
- Finales Transcript echte Speaker-Namen aus Captions nutzt.
- `ME` bleibt sauber vom Mic getrennt.
- Unbekannte Remote-Speaker bleiben diarisiert als `S1/S2`.
- User kann `S1/S2` weiterhin manuell labeln.
- Alte Meetings öffnen weiter.
- Quellen und Feature-Limits sind in Settings/Docs klar.

V1 ist fertig, wenn:

- Teams, Meet und Zoom Captions unterstützt sind.
- SpeakerStore Aliase + mehrere Embeddings kann.
- Teams Graph Reconcile funktioniert.
- Google Meet Reconcile funktioniert.
- Zoom Import ist tolerant gegen VTT/Timeline-Abweichungen.

## Warum das der richtige Weg ist

Audio-Diarization beantwortet nur: "Welche Stimme ist das?"  
Plattform-Captions/API beantworten: "Wie heißt diese Person?"

NeoQuill braucht beides. Captions/API liefern echte Namen. FluidAudio liefert Fallback und Wiedererkennung. Zusammen wird daraus ein belastbares Speaker-System.
