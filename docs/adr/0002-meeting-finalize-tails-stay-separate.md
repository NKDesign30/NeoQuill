# Die vier Meeting-Finalize-Schwänze bleiben getrennt

Die vier Pipelines, die ein Meeting-Detail nach der Transkription fertigstellen —
`persistMeeting`, `persistImportedMeeting`, `mergeAudioIntoMeeting`,
`reprocessMeetingAsync` in `RecordingController` — teilen das Skelett
„Provisional `.summarizing` → `MeetingSummarizer.summarize` → Final `.done`". Die
zwei echten Drift-Quellen daraus sind bereits in eigene Module gezogen: das
Highlights/Tasks/Chapters-Mapping (`MeetingSummarizer`, parametrisiert per
`idPrefix`) und das Zeit-/Datums-Präludium (`MeetingTimeline`).

Wir extrahieren den verbleibenden Finalize-Schwanz **bewusst nicht** in einen
gemeinsamen `MeetingFinalizer`. Was bleibt, ist keine Duplikation, sondern
fachliche Divergenz: zwei Pfade bauen ein `MeetingDetail(...)` neu, zwei nutzen
`rebuiltDetail(from:)` von **unterschiedlichen** Basen (`detail` vs. dem bereits
transkribierten Zwischen-Detail); die audioURL-Quelle, der Title-/TLDR-Fallback
und die empty-Branches unterscheiden sich pro Pfad; und `mergeAudioIntoMeeting`
darf das Audio nie löschen, während die anderen drei der
`deleteAudioAfterTranscription`-Policy folgen.

Ein gemeinsames Template müsste das über fünf bis sechs Closures und Flags
parametrisieren — es würde die Divergenz verstecken statt Komplexität
konzentrieren und wäre selbst ein Shallow-Wrapper-Finding. Der Deletion-Test ist
negativ: der Closure-Inhalt wäre exakt der Code, der heute inline steht.

## Konsequenz

Architektur-Reviews werden „vier ähnliche Finalize-Pipelines" sehen. Das ist
gewollt: die Ähnlichkeit ist Skelett, nicht Substanz. Erst wenn sich die vier
Pfade fachlich angleichen (gleiche Detail-Basis, gleiche Audio-Policy), lohnt ein
gemeinsames Finalize — bis dahin bleibt jeder Schwanz bei seiner Pipeline.
