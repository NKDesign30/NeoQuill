# NeoQuill Versioning

`VERSION` is the source of truth for the app version shown in GitHub.
`CHANGELOG.md` is the human-facing release history.

`scripts/build-app.sh` embeds this metadata into `NeoQuill.app/Contents/Info.plist`:

- `CFBundleShortVersionString`: semantic version from `VERSION`
- `CFBundleVersion`: monotonically increasing git commit count, or `NEOQUILL_BUILD_NUMBER`
- `NeoQuillGitCommit`: short git SHA
- `NeoQuillGitBranch`: current branch
- `NeoQuillGitDirty`: `clean` or `dirty`
- `NeoQuillBuildDate`: UTC build timestamp

Release tags should match the version file, for example `v0.9.0`.

## Branch and Release Policy

- Work happens on `dev`.
- `main` is only updated after the release gate passes on `dev`.
- Tags are created on `main` and must match `VERSION`.
- Public artifacts come from `scripts/package-release.sh`, `scripts/build-dmg.sh`
  and `scripts/publish-update.sh`.
- The JSON manifest is the handoff source for version, build, commit, branch,
  dirty-state, changelog, ZIP archive and SHA256. `publish-update.sh` requires
  the matching DMG and SHA256 sidecar for the same build / commit before it
  publishes `appcast.xml` or GitHub Release assets.
- `scripts/verify-changelog.sh` must pass before packaging; every release needs a `## [VERSION] - YYYY-MM-DD` section with at least one bullet.
- `scripts/market-readiness.sh` must pass before paid/public distribution.
- For public distribution, `--strict-distribution --notarize`,
  `build-dmg.sh --notarize`, `publish-update.sh` and `market-readiness.sh` must
  pass on `main` with a Developer ID Application certificate, a notary profile,
  complete DMG / ZIP / manifest assets and an EdDSA-signed Sparkle appcast.
