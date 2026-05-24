# Changelog

Alle relevanten Änderungen an NeoQuill werden hier dokumentiert.

Format: newest first, nutzerverständlich, releasefähig. `VERSION`, Git-Tag,
GitHub Release und dieser Changelog müssen für jedes Release zusammenpassen.

## [Unreleased]

- Nächste Änderungen werden hier gesammelt, bis `VERSION` erhöht wird.

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
