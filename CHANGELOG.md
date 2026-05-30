# Changelog

Alle relevanten Änderungen an NeoQuill werden hier dokumentiert.

Format: newest first, nutzerverständlich, releasefähig. `VERSION`, Git-Tag,
GitHub Release und dieser Changelog müssen für jedes Release zusammenpassen.

## [Unreleased]

- Nächste Änderungen werden hier gesammelt, bis `VERSION` erhöht wird.

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
