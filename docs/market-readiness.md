# NeoQuill Market Readiness

Stand: 2026-05-24

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
- GitHub Release mit ZIP, SHA256 und Manifest
- Developer-ID-Signatur
- Notarization und Stapling

## Aktueller Blocker

Der aktuelle Stand ist funktional verpackt und auf GitHub released, aber noch
nicht öffentlich distributionsbereit. In der lokalen Keychain liegt aktuell
kein `Developer ID Application` Zertifikat. `Apple Development` reicht nur für
lokale Tests, `Apple Distribution` ist nicht der Direct-Sale-Ersatz.

Für Direct-Sale braucht NeoQuill:

1. `Developer ID Application` Zertifikat im Keychain Access.
2. Notary-Profil per `xcrun notarytool store-credentials`.
3. `NEOQUILL_NOTARY_PROFILE=<profile>` beim Release.
4. `./scripts/package-release.sh --strict-distribution --notarize`.
5. Danach `./scripts/market-readiness.sh` ohne FAIL.

## Aktueller Release-Stand

- Neuester Release: `v0.9.10`
- GitHub Release: https://github.com/NKDesign30/NeoQuill/releases/tag/v0.9.10
- Bekannter Distribution-Status: nicht notarized, nicht stapled, Apple-Development-signiert.
