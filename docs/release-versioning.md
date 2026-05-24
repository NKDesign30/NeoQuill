# NeoQuill Versioning

`VERSION` is the source of truth for the app version shown in GitHub.

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
- Public artifacts come from `scripts/package-release.sh`; the JSON manifest is the handoff source for version, build, commit, branch, dirty-state, signing and SHA256.
- For public distribution, `--strict-distribution --notarize` must pass with a Developer ID Application certificate and a notary profile.
