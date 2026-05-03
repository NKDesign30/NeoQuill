# Speaker-Identification Parallel-Track — Handoff-Notiz

Stand: 2026-05-03
Branch: `feat/platform-transcript-parsers`
Author: Neo (Parallel zu Chatys MVP auf `main`)

## TL;DR

- Plattform-Parser für Teams (VTT + Graph metadataContent), Google Meet (entries + participants) und Zoom (VTT + Timeline) sind als pure Swift-Funktionen gebaut.
- Diagnose-Helfer `CaptionDebugDumper` schreibt AX-Tree-Snapshots als JSON, hinter UserDefault-Flag, ohne sichtbare UI.
- 43 neue Unit-Tests, `swift test` grün (47 Tests gesamt, vorher 4).
- Keine Änderung an `RecordingController`, `CaptionCaptureService`, `TranscriptMerger` oder `SpeakerStore`.
- Kein Merge nach `main`. Branch wartet auf Chatys Integration.

## Was funktioniert ohne Live-Call

- `TeamsTranscriptParser.fromVTT(_:)` — voice-tag (`<v Name>...</v>`) und Colon-Prefix-Cues, Sub-Sekunden-Genauigkeit.
- `TeamsTranscriptParser.fromMetadataContent(_:referenceDate:)` — Microsoft Graph JSON. Nimmt `value`-Wrapper, `entries`-Wrapper oder Top-Level-Array. ISO8601 mit/ohne Sub-Sekunden. Berechnet relative Sekunden vom frühesten Eintrag oder externer Reference-Date.
- `GoogleMeetTranscriptParser.parse(entriesJSON:participantsJSON:referenceDate:)` — `conferenceRecords/.../entries[]` + Participant-Resolution gegen `user.displayName`, `signedinUser.displayName`, `anonymousUser.displayName`, `phoneUser.displayName`.
- `ZoomTranscriptParser.fromVTT(_:)` — indexed VTT mit Speaker-Colon-Prefix.
- `ZoomTranscriptParser.fromTimeline(_:referenceDate:)` — Cloud-Recording-Timeline, mit `talking`-Flag, Fallback auf ersten User. Synthetisiert Platzhalter-Text wenn Timeline keine Worte enthält.
- `CaptionDebugDumper.snapshotMeetingApps()` / `writeSnapshot(to:)` — AX-Walking aller Meeting-App-Bundles aus `CallApp.allKnownBundleIdentifiers`, Tiefe 11, Limit 600 Nodes pro App, JSON-Output.

## Was bei Live-QA noch unklar bleibt

Live-QA gegen echte Teams/Zoom/Meet-Sessions ist nicht in dieser Iteration gelaufen — keine aktive Meeting-Session zur Hand, und ich wollte nicht gegen leere Fenster polieren. Die Parser sind fixture-getestet, der Dumper ist roundtrip-getestet. Was Niko / Chaty live verifizieren müssen:

1. **Teams native (`com.microsoft.teams2`)**: Live-Captions on, sieht der `CaptionCaptureService` echte Caption-Nodes? Ist die `<v Speaker>...</v>` Erkennung im Parser deckungsgleich mit dem AX-Tree-Output?
2. **Teams Web (Chrome / Edge)**: Caption-Container ist üblicherweise `[role="region"][aria-label*="caption"]` mit `<span>`-Kindern pro Speaker. Browser-Bundle-IDs sind im `CallApp.browser` enthalten.
3. **Google Meet (Chrome)**: Captions stehen in einer Liste mit Avatar + Name + Text. AX-Tree-Dump zeigt ob `AXStaticText` mit Name + Text auseinandergeschnitten oder zusammen serviert wird.
4. **Zoom native (`us.zoom.xos`)**: Caption-Window ist eigenes Top-Level-Window. Sehen wir es im AX-Tree der Zoom-App?

Empfohlenes Vorgehen für Live-QA (siehe Abschnitt "QA-Workflow" unten).

## Geänderte Dateien (auf Branch, nicht main)

```
Sources/NeoQuill/Models/PlatformTranscriptEvent.swift          (neu — war als Stub vorhanden, jetzt produktiv)
Sources/NeoQuill/Services/Platform/PlatformParserError.swift   (neu)
Sources/NeoQuill/Services/Platform/VTTCueParser.swift          (neu)
Sources/NeoQuill/Services/Platform/TeamsTranscriptParser.swift (neu)
Sources/NeoQuill/Services/Platform/GoogleMeetTranscriptParser.swift (neu)
Sources/NeoQuill/Services/Platform/ZoomTranscriptParser.swift  (neu)
Sources/NeoQuill/Services/CaptionDebugDumper.swift             (neu)

Tests/NeoQuillTests/VTTCueParserTests.swift                    (neu)
Tests/NeoQuillTests/TeamsTranscriptParserTests.swift           (neu)
Tests/NeoQuillTests/GoogleMeetTranscriptParserTests.swift      (neu)
Tests/NeoQuillTests/ZoomTranscriptParserTests.swift            (neu)
Tests/NeoQuillTests/CaptionDebugDumperTests.swift              (neu)
Tests/NeoQuillTests/PlatformTranscriptMergeTests.swift         (neu)

claudedocs/SPEAKER_ID_HANDOFF.md                               (diese Datei)
```

Keine Änderungen an:
- `Sources/NeoQuill/Services/RecordingController.swift`
- `Sources/NeoQuill/Services/CaptionCaptureService.swift`
- `Sources/NeoQuill/Services/TranscriptMerger.swift`
- `Sources/NeoQuill/Services/SpeakerStore.swift`

Auch nicht an `App.swift`, `AppState.swift`, `Package.swift`. Der Dumper bleibt damit komplett isoliert — Chaty entscheidet wo/wann er instanziiert wird.

## Build + Tests

- `swift build` grün (Debug, macOS 15).
- `swift test` 47 Tests, 0 Failures, ~1.2 s.
- Zerlegung: 4 Tests waren vorher (TranscriptMerger + Migration), 43 sind neu.

## Diagnose-Helfer aktivieren

Der `CaptionDebugDumper` ist absichtlich nicht in `App.swift` verdrahtet — kein UI, kein automatischer Start. Drei Wege ihn zu nutzen:

### A) Snapshot ad-hoc aus dem Code

```swift
// z.B. nach Recording-Start
_ = try? CaptionDebugDumper.writeSnapshot()
// Schreibt nach: ~/Library/Application Support/NeoQuill/debug-axdumps/axdump-YYYYMMDD-HHMMSS.json
```

### B) Live-Polling über UserDefault

```bash
defaults write com.neon.quill caption_debug_dump -bool true
defaults write com.neon.quill caption_debug_dump_interval -float 5
```

Dann irgendwo am Boot (z.B. `App.init()`):

```swift
import SwiftUI

@main
struct NeoQuillApp: App {
    init() {
        FontRegistrar.registerAll()
        AppSettings.registerDefaults()
        Task { @MainActor in CaptionDebugDumper.installIfEnabled() }   // <-- ein Liner
        _state = StateObject(wrappedValue: AppState())
    }
    // ...
}
```

Solange der UserDefault `false` ist, passiert genau gar nichts. Solange er `true` ist, dumpt der Dumper alle 5 s alle Meeting-App-Trees.

### C) Aus Tests

Die Test-Suite zeigt einen Snapshot-Roundtrip in `CaptionDebugDumperTests.testWriteSnapshotCreatesFileAndOverrideDirectoryRespected` — gleiche API kann in einem Debug-Build aus einem Menüpunkt heraus aufgerufen werden.

## QA-Workflow (für Live-Verifikation)

### 1. Teams native, Captions an

```bash
defaults write com.neon.quill caption_debug_dump -bool true
open -a NeoQuill.app          # nach build-app.sh
```

- Meeting starten, "Show live captions" aktivieren.
- 30 s laufen lassen, dann:

```bash
ls -lt ~/Library/Application\ Support/NeoQuill/debug-axdumps/ | head -5
jq '.apps[] | {bundleIdentifier, processName, nodes: (.nodes | length)}' \
   ~/Library/Application\ Support/NeoQuill/debug-axdumps/axdump-*.json
```

- Im Dump nach Caption-Texten suchen (Speaker:Body oder zwei Zeilen):

```bash
jq '.apps[] | .nodes[] | select(.value | length > 0) | {role, value, path}' \
   ~/Library/Application\ Support/NeoQuill/debug-axdumps/axdump-*.json | less
```

Erkenntnisse hier zurück in `CaptionCaptureService.parseCaptionCandidate` rein. Aktuelle Heuristik:
- Speaker = erste Zeile von zweizeiligem Text, ODER vor erstem `:`.
- 2 .. 64 Zeichen, max 5 Wörter, mind. ein Buchstabe.
- Body = mind. 4 Zeichen, mind. 3 Wörter ODER Punkt/Frage/Ausruf.

### 2. Teams Web (Chrome/Edge)

Browser-Bundle ist `com.google.Chrome` oder `com.microsoft.edgemac` — in `CallApp.browser.bundleIdentifiers`. Beim AX-Tree-Walk wird im Browser primär `AXWebArea` gescannt; Teams Web hängt Captions als `aria-live`-Region rein. Im Dump sollten Caption-Texte als `AXStaticText` mit `value` auftauchen, darüber ein `AXGroup` mit `description` = Speaker-Name.

Wenn der Caption-Text Speaker und Body in derselben `value`-Property hat (Teams Web rendert das oft so), dann läuft der Colon-Split sauber. Wenn Speaker und Body in unterschiedlichen Nodes stehen, müssen wir entweder:
- AX-Sibling-Walk im `CaptionCaptureService` ergänzen (Core-File-Change → Chaty entscheidet),
- oder den Browser-Modus über DOM-Bridge (Companion-Extension) angehen (Phase 1.5 im Plan).

### 3. Google Meet (Chrome)

Meet rendert Captions als geordnete Liste am unteren Bildschirmrand. AX-Tree-Pattern:
```
AXList (caption container)
  └─ AXListItem
       ├─ AXImage (Avatar)
       ├─ AXStaticText "Sarah Ebner"
       └─ AXStaticText "Hallo zusammen."
```

Aktuelle CaptionCaptureService-Heuristik fasst Texte einer Window-Hierarchie zusammen und joined sie mit `\n`. Wenn die zwei Texte Geschwister sind, landen sie zusammen im Multi-Line-Pfad — dann greift `splitSpeakerAndText` mit Multi-Line-Branch. Im Dump verifizieren ob der gemeinsame Parent-Knoten gefunden wird. Falls Meet die Knoten zu weit auseinander hängt, brauchen wir einen separaten Sibling-Walk.

### 4. Zoom native

Zoom hat oft ein eigenes Caption-Floating-Window. Im AX-Dump muss Zoom mehrere Top-Level-Windows zeigen. `CaptionCaptureService.poll()` iteriert via `kAXWindowsAttribute` über alle Windows der App — sollte funktionieren, sofern Zoom das Caption-Window dem App-AX-Element zuordnet.

Im Dump nach `processName == "zoom.us"` suchen und prüfen ob Caption-Window vorkommt. Wenn nicht, könnte Zoom das Window an die Window-Server-Hierarchie hängen statt an die App — dann brauchen wir AX-Walk via `kAXChildrenAttribute` auf System-Wide AX-Element (anderes Pattern als heute).

## Welche AX-Rollen / Attribute sind relevant?

Aus Erfahrung mit Caption-Apps und der Heuristik im aktuellen `CaptionCaptureService`:

| Rolle | Wofür | Wo wir gucken |
|---|---|---|
| `AXStaticText` | Reine Text-Nodes | Caption-Body |
| `AXGroup` | Speaker+Caption-Container | Parent-Node mit Speaker im Description |
| `AXList` / `AXListItem` | Caption-Stream (Meet) | Geordnete Caption-History |
| `AXWebArea` | Browser-Inhalt | Teams Web, Meet, Zoom Web |
| `AXWindow` | Top-Level-Fenster | Zoom Caption-Floating |
| `AXScrollArea` | Scrollender Caption-Container | Teams native |

Attribute mit Speaker-/Caption-Daten:

| Attribut | Wofür |
|---|---|
| `kAXValueAttribute` | Static-Text-Body |
| `kAXTitleAttribute` | Button-Beschriftung, manchmal Speaker |
| `kAXDescriptionAttribute` | Aria-Label-Pendant, oft Speaker-Name in Web-Apps |
| `kAXIdentifierAttribute` | DOM-id/test-id im Browser, hilft beim gezielten Filtern |
| `kAXSubroleAttribute` | Detailrolle (z.B. `AXSecureTextField`) |

`CaptionDebugDumper` capturt all diese Attribute.

## Was bricht, was als nächstes ansteht

- **Browser-Bundle-Erkennung im CaptionCaptureService**: aktuell ist `CallApp.browser` für Caption-Capture freigegeben (`supportsCaptionCapture == true`), aber der Service prüft nur Bundle-ID-Prefix gegen alle Browser. Wenn mehrere Browser laufen (z.B. Chrome für Meet UND Edge für Teams), wird nicht differenziert — beide werden gepollt. Das ist gewollt, sollte aber im Live-Test verifiziert werden.
- **`Platform.call`** als Fallback im CaptionCaptureService: führt zu `state = .listening(.call)` was im UI etwas generisch aussieht. Niedrigprio.
- **AX-Polling-Frequenz** ist 0.8 s. Bei vielen Apps kann das CPU drücken. Snapshot zeigt `truncated`-Flag wenn 600-Node-Limit pro App erreicht — falls das oft auftritt, sollte das Limit konfigurierbar werden.
- **Zoom-VTT mit Lookahead**: Manche Zoom-VTT-Files haben auch `<v ...>` Voice-Tags (für KI-generierte Transkripte). Aktueller `ZoomTranscriptParser.fromVTT` fällt nur auf Colon zurück. Wenn das Live in Niko's Zoom-Subscription so kommt, kann ich die Voice-Tag-Erkennung trivial nachziehen (eine Zeile in `ZoomTranscriptParser`).

## Wenn etwas live nicht klappt

1. AX-Dump generieren: `defaults write com.neon.quill caption_debug_dump -bool true`, App neu starten, Meeting starten.
2. Dump-File analysieren (jq-Snippets oben).
3. Wenn Caption-Nodes im Dump auftauchen aber `CaptionCaptureService.events` leer bleibt: `parseCaptionCandidate` greift nicht — Heuristik anpassen (Core-File-Change, mit Chaty abstimmen).
4. Wenn Caption-Nodes überhaupt nicht im Dump auftauchen: AX-Tree der App reicht nicht aus, Browser-Companion-Extension wird nötig (Plan-Phase 1.5).

## Was ich bewusst NICHT angefasst habe

- `RecordingController.persistMeeting` — ruft heute `TranscriptMerger.merge(...)` mit den Caption-Events auf. Mein Verdacht: Wenn die Plattform-Parser produktiv werden, läuft das gleiche Pattern, nur mit `platformTranscriptEvents:` befüllt. Chaty oder ich als Folge-Sprint.
- `CaptionCaptureService` — der Dumper ergänzt hier ohne den Service zu modifizieren. Wenn die AX-Heuristik live nicht reicht, ist das der Ort für Anpassungen.
- `SpeakerStore` v2 — Aliase und Multi-Embedding sind laut Plan schon drin. Plattform-Events sollten beim Persistieren auch als Alias landen, parallel zum heutigen Caption-Pfad.
- Bestehende Tests — alle 4 ursprünglichen Tests laufen unverändert grün.

## Quick-Reference

```bash
# Build + Tests
cd /Users/nikoknez/neon-projects/NeoQuill
swift build && swift test

# Branch
git checkout feat/platform-transcript-parsers

# Diff zu main
git diff main..feat/platform-transcript-parsers --stat

# Dump aktivieren
defaults write com.neon.quill caption_debug_dump -bool true
defaults write com.neon.quill caption_debug_dump_interval -float 5
# (App neustarten)

# Dump deaktivieren
defaults write com.neon.quill caption_debug_dump -bool false
rm -rf ~/Library/Application\ Support/NeoQuill/debug-axdumps/
```
