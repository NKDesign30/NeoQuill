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
