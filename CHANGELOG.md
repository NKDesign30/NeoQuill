# Changelog

Alle relevanten Änderungen an NeoQuill werden hier dokumentiert.

Format: newest first, nutzerverständlich, releasefähig. `VERSION`, Git-Tag,
GitHub Release und dieser Changelog müssen für jedes Release zusammenpassen.

## [Unreleased]

- Nächste Änderungen werden hier gesammelt, bis `VERSION` erhöht wird.

## [0.13.1] - 2026-07-02

- Changed: Einstellungen haben jetzt genau eine Default-Quelle — Key und
  Vorbelegung sind eine typisierte Definition. Widersprüchliche Vorbelegungen
  zwischen Einstellungs-UI, Registrierung und internen Lesepfaden (z. B. bei
  der Sprechererkennung) sind damit konstruktiv ausgeschlossen.
- Changed: Meeting-Auswahl der Sidebar (Einzel-, Cmd- und Shift-Selektion,
  Workspace-Filter-Abgleich) und das Start-Gate der Sprechererkennung sind
  eigenständige, getestete Module — 21 neue Tests sichern das Verhalten ab.
- Changed: Interne Aufräumarbeiten ohne Verhaltensänderung: Summary-Gate in
  den PostProcessor gefaltet, Provider-Key-Zuordnung als eine Wahrheit am
  Provider-Modell, Lizenz-Banner beobachtet den Lizenz-Service direkt.

## [0.13.0] - 2026-07-01

- Added: Neuer Meeting-Menüpunkt „An KI übergeben" kopiert einen fertigen
  Übergabe-Prompt ins Clipboard, mit dem Neo, Chaty oder eine generische KI die
  projektrelevanten Erkenntnisse aus dem Meeting herauspickt und ins passende
  Projekt-Memory überträgt.
- Added: Zwei Prompt-Varianten je Ziel-KI: ein schlanker Referenz-Prompt, der
  die KI das Meeting selbst per lokaler `quill`-CLI laden lässt, und ein
  Voll-Prompt mit komplettem Transkript für KIs ohne Datenbankzugriff.

## [0.12.2] - 2026-06-29

- Added: Meetings können jetzt in Workspaces organisiert werden: Projekt, Team
  oder Organisation mit eigenem Kontext.
- Added: Aufnahmen und Audio-Importe landen direkt im aktuell gewählten
  Workspace, und der Workspace-Kontext fließt in die KI-Zusammenfassung ein.
- Added: Die Sidebar unterstützt Rechtsklick-Aktionen auf Meetings inklusive
  Workspace-Zuordnung, Markdown-Export, Final-STT und Audio ergänzen.
- Added: Mehrere Meetings lassen sich per Cmd-/Shift-Auswahl gemeinsam in einen
  Workspace verschieben oder aus einem Workspace entfernen.

## [0.12.1] - 2026-06-19

- Fixed: Die In-App-Einstellungen stürzen auf Installationen mit fehlendem
  oder anders aufgelöstem Lokalisierungs-Bundle nicht mehr ab.
- Added: Das Installationspaket bringt jetzt die benötigte finale
  Transkriptions-Runtime mit: `whisper-cli`, `ggml-large-v3-turbo.bin` und die
  passenden GGML-/Whisper-Bibliotheken inklusive Metal- und CPU-Fallbacks.
- Changed: Onboarding und Einstellungen erklären klarer, dass Claude/Codex nur
  mit eigener CLI-/OAuth- oder API-Konfiguration genutzt werden können.

## [0.12.0] - 2026-06-19

- Added: Einstellungen sind jetzt direkt in der App — ein Sidebar-Overlay im
  Hauptfenster löst das alte Tab-Fenster ab und bündelt Audio, KI, Aktionen,
  Cloud, Daten, Berechtigungen, Lizenz und Version an einer Stelle.
- Added: Der KI-Anbieter für Zusammenfassungen ist frei wählbar — neben
  OpenAI-kompatiblen Endpoints stehen Anthropic, lokales Ollama und die lokale
  Claude CLI zur Auswahl.
- Changed: Die Action-Inbox-Anbindung nutzt einen frei konfigurierbaren
  Endpoint aus den Einstellungen statt einer fest verdrahteten lokalen Adresse
  und meldet Verbindungsfehler verständlich.
- Changed: Das Onboarding führt durch die neue Anbieter- und Einstellungs-
  Struktur.
- Changed: Release-Tooling gehärtet — die Notarisierungs-Skripte finden ein
  vorhandenes `neoquill-notary` Keychain-Profil automatisch und ein neuer
  Download-Smoke-Test prüft den echten Update-Pfad (GitHub-DMG, SHA256, Mount,
  Codesign, Gatekeeper, Start).

## [0.11.0] - 2026-06-10

- Added: Freie Wahl des KI-Anbieters für Zusammenfassungen — neben
  OpenAI-kompatiblen Endpoints werden jetzt Anthropic und lokales Ollama
  unterstützt, inklusive Verbindungstest in den Einstellungen.
- Added: Die App-Sprache ist umschaltbar (Deutsch/Englisch) und wechselt live
  ohne Neustart.
- Changed: Integrationen (Action-Inbox, Jira) sind jetzt ein bewusstes Opt-in
  mit neutralen Labels und frei konfigurierbarem Inbox-Endpoint — frische
  Installationen starten ohne vorbelegte Anbindung.
- Fixed: Automatisch gestoppte Teams-/Zoom-Meetings wurden als allgemeiner
  "Call" gespeichert. Die erkannte Plattform wird jetzt beim Aufnahme-Start
  eingefroren und übersteht den Auto-Stop.
- Fixed: Beim Benennen von Sprechern direkt nach einer Aufnahme konnte in
  seltenen Fällen ein Stimm-Abdruck der vorherigen Aufnahme verwendet werden.
  Meeting-eigene Stimm-Abdrücke haben jetzt immer Vorrang.
- Fixed: Sprechanteil-Balken zeigten bei sehr kurzen Meetings (unter einer
  Minute) für alle Teilnehmer 0 % an. Die Dauer-Labels laufen jetzt über eine
  gemeinsame, getestete Umrechnung, die auch die Sekunden-Form ("45s") korrekt
  zurückrechnet.
- Fixed: Die "Auto ×"-Anzeige im Player zeigt bei korrigierter Wiedergabe die
  echte Korrektur-Rate statt des technischen Mindestwerts.
- Changed: Das Onboarding fragt nicht mehr nach einer Organisation — das Feld
  wurde gesammelt, aber nie verwendet.
- Changed: Interne Architektur über mehrere Runden konsolidiert und vertieft.
  Zeitstempel- und Dauer-Formatierung, Meeting-ID-Vergabe, Erkennung
  wiederholter Transkript-Zeilen, Call-App-Routing, Aufnahme-Session,
  Speaker-Identität, Summary-Pipeline, Diarisierungs-Auflösung,
  Transcript-Heuristiken und Playback-Korrektur laufen jetzt über jeweils eine
  getestete Quelle. Toter Code wurde entfernt. 422 Tests.

## [0.10.0] - 2026-05-30

- Added: Audio-Soak- und Sample-Rate-Invariant-Tests sichern den getrennten
  48kHz-Stereo-HQ-Pfad und den 16kHz-ASR-Pfad über lange Converter-Läufe ab.
- Added: Support-Diagnostics exportiert privacy-safe WAV-Metadaten und
  Codesign-Status ohne Audio- oder Transcript-Inhalte.
- Changed: Release-Pipeline und Market-Readiness-Gate prüfen DMG-primary
  Distribution, Sparkle-Appcast, ZIP-Fallback, SHA256-Sidecars und Manifest als
  zusammengehörigen Artefakt-Satz.

## [0.9.16] - 2026-05-25

- Fixed: Installed app builds no longer crash at launch during font and icon
  registration when SwiftPM's generated `Bundle.module` accessor cannot resolve
  the resource bundle.

## [0.9.15] - 2026-05-25

- Added: Canonical Transcript JSON export with engine metadata, audio
  fingerprint, quality report, segments and word timings for reproducible
  reprocessing.
- Added: XcodeGen project support so NeoQuill can be opened and run from Xcode
  without losing the SwiftPM build path.
- Changed: Beta builds stay free for all `0.9.x` versions; paid license
  enforcement starts only with `1.0.0`.
- Fixed: Large transcript views now page and collapse repeated runs so meetings
  with thousands of transcript rows do not freeze the app.
- Fixed: Final-STT rejects repeated hallucination transcripts before they are
  persisted as final meeting text.
- Fixed: Sparkle is embedded in the app bundle so installed builds no longer
  crash at launch because the framework is missing.
- Changed: The app surfaces its current version in the UI for support and
  tester feedback.

## [0.9.14] - 2026-05-24

- Added: First public release. Source-available under proprietary LICENSE
  (All Rights Reserved). Hosted on github.com/NKDesign30/NeoQuill.
- Added: Branded DMG installer (`scripts/build-dmg.sh`) with retina
  drag-to-Applications layout, Developer ID signature, Apple notarization
  and stapled ticket. Hides APFS housekeeping so users with
  `AppleShowAllFiles=1` see only the app and the Applications shortcut.
- Added: Sparkle 2 auto-updater wired into the SwiftUI app. The updater
  polls the EdDSA-signed appcast at the repository root and exposes
  `Nach Updates suchen…` from the app menu plus an `Updates`-Section in
  Settings (Auto-Check-Toggle + Manual-Check-Button).
- Added: `scripts/publish-update.sh` generates and signs the appcast,
  commits it on the current branch and creates the matching GitHub Release
  with both the DMG (primary) and the ZIP (legacy fallback) as assets.
- Added: Marketing README with Claude-Design hero, sales positioning and
  badge row.
- Changed: `scripts/build-app.sh` reads `NEOQUILL_PREFERRED_DEV_EMAIL`
  from the environment instead of a hardcoded email when picking a
  development cert.

## [0.9.13] - 2026-05-24

- Added: Public Builds werden mit Developer ID Application (G2, Niko Knez 6QW75N66YP) signiert und über `xcrun notarytool` bei Apple notarisiert.
- Added: Notary-Profile `neoquill-notary` für die Release-Pipeline; Konfiguration via `NEOQUILL_NOTARY_PROFILE` in `.env`.
- Changed: `market-readiness.sh` läuft jetzt grün für Direct-Sale-Distribution.

## [0.9.12] - 2026-05-24

- Changed: README als ehrlichen Produkt-, Architektur-, Build- und Release-Einstieg neu geschrieben.

## [0.9.11] - 2026-05-24

- Added: Market-Readiness-Preflight für GitHub Release, Changelog, Manifest, SHA256, Signing und Notarization.
- Added: Distribution-Doku mit klarem Developer-ID- und Notary-Blocker für Direct-Sale.

## [0.9.10] - 2026-05-24

- Added: Release-Changelog als verpflichtenden Teil des Release-Flows eingeführt.
- Added: `scripts/verify-changelog.sh` prüft vor dem Packaging, dass die aktuelle `VERSION` im Changelog dokumentiert ist.
- Changed: Release-Manifest verweist jetzt auf den passenden Changelog-Abschnitt.

## [0.9.9] - 2026-05-24

- Fixed: Playback für zu kurze/high-pitched Aufnahmen rendert eine korrigierte WAV-Kopie, statt nur auf `AVAudioPlayer.rate` zu setzen.
- Added: Regressionstests für severe Duration-Ratios und begrenzte Playback-Expansion.
- Changed: Produktplan um professionellen Operating Standard, `dev` -> `main` Release-Policy und reproduzierbare Build-Wahrheit ergänzt.

## [0.9.8] - 2026-05-24

- Fixed: Speaker-Matches werden abgelehnt, wenn bekannte Stimmen zu ähnlich scoren und die Zuordnung nicht belastbar ist.

## [0.9.7] - 2026-05-24

- Fixed: Speaker-Relabels bleiben in Transkript, Summary, Highlights, Tasks und Kapiteln konsistent.

## [0.9.6] - 2026-05-24

- Fixed: Speaker-IDs kollidieren nicht mehr über identische Initialen.

## [0.9.5] - 2026-05-24

- Fixed: Bekannte Speaker-Identitäten bleiben beim manuellen Labeln erhalten.

## [0.9.4] - 2026-05-24

- Added: Privacy-safe Diagnostics Export für Support und Release-Debugging.

## [0.9.3] - 2026-05-24

- Changed: macOS Distribution Gate für Developer-ID- und Notarization-Flows gehärtet.

## [0.9.2] - 2026-05-24

- Added: Release-Packaging mit ZIP, SHA256 und Manifest.

## [0.9.1] - 2026-05-24

- Added: Bekannte Speaker-Labels werden wiederverwendet.

## [0.9.0] - 2026-05-24

- Added: App-Version, Build-Nummer, Commit, Branch und Dirty-State im Bundle verankert.
