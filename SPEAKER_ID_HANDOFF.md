# Speaker-Identification — Handoff-Notiz

Stand: 2026-05-03
Branch: `feat/platform-transcript-import` (zum Mergen auf `main`)

## TL;DR

Plattform-Transkripte (Teams, Google Meet, Zoom) werden jetzt End-to-End in NeoQuill verarbeitet. User hat zwei Wege:

1. **Manuell**: Toolbar-Button "Importieren" → File-Picker → erkennt Format → Re-Merge
2. **Auto-Watch**: Settings-Toggle "Transkripte im Downloads-Ordner automatisch erkennen" → macOS-Notification bei neuer Datei → Klick → Match-Sheet → Apply

Echte Speaker-Namen aus offiziellen Cloud-Transkripten ersetzen `S1/S2`-Diarization-Stubs. Aliase landen im `SpeakerStore` (source=`platform`), werden in zukünftigen Meetings via Stimm-Embedding wiedererkannt.

`swift build` + `swift test` grün, 57 Tests (vorher 4).

## Voraussetzungen pro Plattform

| Plattform | User-Aktion im Meeting | Org-Anforderung | Quelle der Datei |
|---|---|---|---|
| **Teams** | "Aufzeichnung + Transkription starten" Button im Meeting-Menü | Tenant erlaubt Cloud-Recording | VTT/JSON-Download aus Teams-Chat oder OneDrive nach Meeting-Ende |
| **Meet** | Während Meeting: "Aktivitäten" → "Transkript starten" | Google Workspace Business Standard+ | JSON-Download aus Google Drive nach Meeting-Ende |
| **Zoom** | Cloud-Recording starten + "Audio Transcript" Toggle aktiv | Zoom Pro/Business Plan | VTT + Timeline-JSON aus Zoom Cloud-Recording-Liste |

Wenn Org/Plan das verbietet: Plattform-Transkripte sind nicht verfügbar — NeoQuill bleibt bei Live-Captions + lokaler Diarization. Das ist KEIN Downgrade, sondern der USP von NeoQuill.

## Architektur

```
File-Picker  ──┐
               ├──> PlatformImportService.detectAndParse(url:)
Auto-Watcher ──┘    │
                    ├──> PlatformTranscriptParser.parseWebVTT / parseTeamsMetadataContent
                    │     parseGoogleMeetEntries / parseZoomTimeline
                    │
                    └──> [PlatformTranscriptEvent]
                                │
                                v
              RecordingController.applyPlatformImport(meetingId:events:)
                                │
                                v
              reprocessMeetingAsync(meetingId, platformEvents:)
                                │
                ┌───────────────┼───────────────┐
                v               v               v
       transcribeFinalAudio  Diarizer      Captions=[]
                │               │               │
                └─────────┬─────┴───────────────┘
                          v
              TranscriptMerger.merge(audioLines:captionEvents:platformTranscriptEvents:diarization:)
                          │
                          ├──> persistPlatformIdentities (source=platform, externalId=who)
                          │
                          v
              MeetingStore.updateDetail
```

## Geänderte Dateien

**Neu:**
- `Sources/NeoQuill/Services/PlatformImportService.swift` — Format-Sniff + Parser-Routing
- `Sources/NeoQuill/Services/TranscriptDownloadWatcher.swift` — Background-Watcher auf ~/Downloads
- `Sources/NeoQuill/Views/Detail/ImportTranscriptSheet.swift` — manueller Picker mit Live-Preview
- `Sources/NeoQuill/Views/Detail/MatchTranscriptSheet.swift` — Watcher-Klick → Meeting-Wahl
- `Tests/NeoQuillTests/PlatformImportServiceTests.swift` (9 Tests)
- `Tests/NeoQuillTests/TranscriptDownloadWatcherTests.swift` (12 Tests)

**Modifiziert:**
- `Sources/NeoQuill/Services/PlatformTranscriptParser.swift` — `parseZoomTimeline` mit `end_ts` + `users[]`-Branch
- `Sources/NeoQuill/Services/RecordingController.swift` — `mergeSpeakers` mit `platformEvents`, `reprocessMeetingAsync`-Overload, `persistPlatformIdentities`, `applyPlatformImport`
- `Sources/NeoQuill/AppState.swift` — `importPlatformTranscript`, Detection-Notification-Bridge, `pendingTranscriptDetection`
- `Sources/NeoQuill/AppSettings.swift` — `autoWatchDownloadsForTranscripts` Konstante + Default
- `Sources/NeoQuill/Chrome/Icons.swift` — `Glyph.Name.download`
- `Sources/NeoQuill/Views/SettingsView.swift` — neue Section "Plattform-Transkripte"
- `Sources/NeoQuill/Views/Detail/DetailToolbar.swift` — "Importieren"-Button
- `Sources/NeoQuill/Views/DetailEditorial.swift` — Banner "Echte Speaker-Namen importieren?"
- `Sources/NeoQuill/App.swift` — `.sheet(item:)` für Match-Detection
- `Tests/NeoQuillTests/PlatformTranscriptParserTests.swift` — 2 neue Zoom-Cases, alter Teams-Test entfernt

**Gelöscht (siehe A.2):**
- `Sources/NeoQuill/Services/Platform/TeamsTranscriptParser.swift` (Chatys generischer Parser ist jetzt single source)
- `Sources/NeoQuill/Services/Platform/GoogleMeetTranscriptParser.swift`
- `Tests/NeoQuillTests/TeamsTranscriptParserTests.swift`
- `Tests/NeoQuillTests/GoogleMeetTranscriptParserTests.swift`

**Behalten in `Services/Platform/`:**
- `VTTCueParser.swift` (shared zwischen beiden Parser-Tracks)
- `PlatformParserError.swift` (genutzt von Zoom-Parser)
- `ZoomTranscriptParser.swift` (eindeutige Behaviors: `users[]`/`end_ts`/Placeholder)

## End-to-End-Test (manueller Pfad)

1. App via `scripts/build-app.sh` bauen + starten
2. Bestehendes Meeting mit `S1/S2`-Diarization öffnen
3. Toolbar → "Importieren" → File-Picker
4. Test-VTT/JSON wählen (z.B. aus Teams Cloud-Recording)
5. Sheet zeigt erkanntes Format + Event-Count → Anwenden
6. Detail-View aktualisiert: `S1/S2` → echte Namen
7. SpeakerStore-Sheet zeigt neue Aliase mit `source=platform`

## End-to-End-Test (Auto-Watcher)

1. Settings → "Transkripte im Downloads-Ordner automatisch erkennen" aktivieren
2. macOS fragt einmalig nach Notification-Permission → erlauben
3. Teams/Meet/Zoom-Transkriptdatei in `~/Downloads` legen (Mtime sollte zu existierendem Meeting passen)
4. Binnen 2-5s: macOS-Notification "Transkript erkannt"
5. Klick auf Notification → MatchTranscriptSheet öffnet sich (auch wenn App im Hintergrund war)
6. Match-Kandidaten (±2h Window) sind sortiert nach zeitlicher Nähe
7. Apply → Re-Merge läuft → Detail-View aktualisiert
8. Datei erneut nach `~/Downloads` schieben → keine Re-Trigger (in `processed_transcript_files`)

## Edge-Cases (alle getestet)

- Leere Datei → klare Fehlermeldung im Sheet (`PlatformImportService.ImportError.empty`)
- Format-Mismatch → fallback auf generic VTT, dann auf `unsupportedFormat`
- Hidden-Identity in Teams-Metadata → Merger fällt automatisch auf Caption/Diarization zurück
- Re-Import derselben Datei → SpeakerStore-Aliase werden nicht dupliziert (UNIQUE-Constraint im Schema)
- Aktives Meeting `nil` → Toolbar-Button disabled
- Garbage-JSON → `unsupportedFormat`
- Unbekanntes File-Pattern im Watcher → ignoriert

## Was UNVERÄNDERT bleibt

Auto-Recording-Pipeline läuft 1:1 wie heute:
1. `MeetingDetector` erkennt Calls
2. `RecordingController.start()` startet Aufnahme
3. `AudioCapture` + `SCKAudioCapture` für Dual-Stream
4. `LiveTranscriber` für Live-Captions
5. `CaptionCaptureService` liest UI-Captions via Accessibility
6. `FinalSTTTranscriber` (whisper-cli) finalisiert
7. `SpeakerDiarizer` (FluidAudio) clustert Stimmen
8. `TranscriptMerger.merge` kombiniert alles (jetzt MIT optional `platformTranscriptEvents`)
9. `MeetingStore.updateDetail` persistiert
10. `PostProcessor` + Claude für Auto-Chapters + Summary

Plattform-Events sind eine **vierte Quelle** zusätzlich zu Captions, STT und Diarization. Wenn keine Plattform-Datei importiert wird, läuft alles wie bisher.

## Diagnose-Helfer (unverändert verfügbar)

`CaptionDebugDumper` für AX-Tree-Snapshots:

```bash
defaults write com.neon.quill caption_debug_dump -bool true
defaults write com.neon.quill caption_debug_dump_interval -float 5
# App neustarten
ls -lt ~/Library/Application\ Support/NeoQuill/debug-axdumps/ | head -5
jq '.apps[] | .nodes[] | select(.value | length > 0) | {role, value, path}' \
   ~/Library/Application\ Support/NeoQuill/debug-axdumps/axdump-*.json | less
```

## Bewusst NICHT in diesem Sprint

- **OAuth/API-Abruf** für Teams Graph, Google Workspace, Zoom Cloud (Phase 5 später)
- **Confidence-UI-Surface** im Transcript (optional, Plan-Phase 6)
- **Folge-Sprint "Speaker-Erkennung OHNE Plattform-STT"** — separate USP-Diskussion (Niko 2026-05-03)
