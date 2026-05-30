# NeoQuill Market Readiness

Stand: 2026-05-30

## Gate

Vor einem öffentlichen Direct-Sale-Release muss laufen:

```bash
./scripts/market-readiness.sh
```

Das Script prüft:

- Git-Stand clean
- `dev` und `main` synchron
- Tag passend zu `VERSION`
- Changelog-Abschnitt für die aktuelle Version
- lokales Release-Manifest, ZIP und SHA256
- lokales DMG mit SHA256, Signatur und stapled Ticket
- `appcast.xml` mit aktueller Version, Manifest-Build, DMG-Enclosure, Length und EdDSA-Signatur
- GitHub Release mit DMG, ZIP, SHA256-Dateien und Manifest
- Developer-ID-Signatur
- Notarization und Stapling

## Aktueller Status

`v0.9.16` ist öffentlich auf GitHub released und Direct-Sale-tauglich verpackt.
Das Release-Manifest meldet einen cleanen Build `98` aus Commit `ef40604`,
Developer-ID-Signatur, Apple-Notarization und stapled Ticket. Der GitHub
Release enthält DMG, ZIP, SHA256-Dateien und Manifest. `appcast.xml` zeigt auf
das DMG `NeoQuill-v0.9.16-build98-ef40604.dmg` und enthält die passende
EdDSA-Signatur.

Für den nächsten Release-Lauf gilt trotzdem:

1. Von einem cleanen Release-Branch aus arbeiten, idealerweise `main`.
2. `dev` und `main` vor dem Release synchronisieren.
3. `VERSION`, Git-Tag, Changelog, Manifest und GitHub Release müssen dieselbe
   Version tragen.
4. `NEOQUILL_NOTARY_PROFILE=<profile>` in der Release-Shell setzen.
5. `./scripts/package-release.sh --strict-distribution --notarize` ausführen.
6. Danach `./scripts/market-readiness.sh` ohne FAIL laufen lassen.

Lokaler Arbeitsstand vom 2026-05-30: Branch `fix/audio-quality-48khz-stereo`
ist absichtlich dirty durch laufende Audio-/Diagnostics-Arbeit. Die Keychain
enthält ein `Developer ID Application` Zertifikat, aber
`NEOQUILL_NOTARY_PROFILE` ist in der aktuellen Shell nicht exportiert.

## Aktueller Release-Stand

- Neuester Release: `v0.9.16`
- GitHub Release: https://github.com/NKDesign30/NeoQuill/releases/tag/v0.9.16
- Release-Artefakte: `NeoQuill-v0.9.16-build98-ef40604.dmg`, ZIP, SHA256-Dateien und JSON-Manifest.
- Bekannter Distribution-Status: Developer-ID-signiert, notarized und stapled.
