# NeoQuill

Local-first macOS meeting intelligence for people who do not want a bot sitting
in every call.

NeoQuill records microphone and system audio, transcribes meetings locally,
keeps speaker labels stable across sessions, summarizes the result and turns
follow-ups into reviewable actions. The product direction is simple: private by
default, useful without a cloud account, and explicit whenever external AI or
connectors are used.

## Current Release

- Latest tag: `v0.9.12`
- Source of truth for version: `VERSION`
- Human release history: `CHANGELOG.md`
- Release artifacts: GitHub Releases with ZIP, SHA256 and JSON manifest
- Public Direct-Sale blocker: Developer ID Application signing and notarization

## Product Position

NeoQuill is built for:

- freelancers and small agencies documenting customer calls
- consultants, PMs and sales people who need usable notes without meeting bots
- privacy-sensitive teams that want local storage and bring-your-own AI keys

The expected v1 path is direct download first, then paid direct sale, then App
Store once direct-sale feedback proves the product shape.

## What Works Now

- macOS app bundle with embedded version, build, commit, branch, dirty-state and build date
- microphone and system-audio capture paths
- local-first meeting storage with SQLite WAL
- local transcription path through WhisperKit
- speaker diarization and cross-meeting speaker identity memory
- manual speaker relabeling that updates transcript, summary, highlights, tasks and chapters
- ambiguous speaker-match rejection to avoid confident wrong labels
- playback correction for too-short/high-pitched recordings through rendered WAV copies
- Teams, Google Meet and Zoom transcript import/parsing paths
- OpenAI-compatible summary provider settings with secrets stored in Keychain
- privacy-safe diagnostics export
- Markdown/export flows and action queue handoff paths
- reproducible release packaging with changelog, SHA256 and manifest

## What Is Not Market-Clear Yet

- Direct-sale public builds are not Developer-ID-signed or notarized yet.
- No payment/licensing layer is wired.
- No auto-updater is installed.
- Public beta still needs real outside-user meeting tests.

Run the market gate before treating a build as public-ready:

```bash
./scripts/market-readiness.sh
```

## Architecture

```text
SwiftUI App
  ├─ Recording UI / Detail UI / Settings
  ├─ RecordingController
  │   ├─ AudioCapture
  │   ├─ ProcessAudioTap
  │   ├─ SCKAudioCapture fallback
  │   └─ AudioWriter
  ├─ FinalSTTTranscriber / WhisperKit
  ├─ SpeakerDiarizer / SpeakerStore
  ├─ TranscriptMerger / Platform parsers
  ├─ PostProcessor / Summary providers
  ├─ MeetingStore / SQLite
  └─ Export, Diagnostics and Action services
```

Core rule: local meeting data stays local unless the user explicitly configures
an external provider or connector.

## Stack

- SwiftUI + Swift Package Manager
- macOS 15+
- WhisperKit
- FluidAudio
- AVFoundation, CoreAudio and ScreenCaptureKit
- SQLite with WAL mode
- GitHub Releases for distributable ZIP artifacts

## Development

```bash
swift build
swift test
```

Run from SPM:

```bash
swift run NeoQuill
```

Build, install and launch the app:

```bash
./scripts/build-app.sh
```

Build without installing:

```bash
./scripts/build-app.sh --no-install --no-run
```

## Release Flow

Work happens on `dev`. `main` is only updated after the release gate passes.

```bash
./scripts/verify-changelog.sh
swift test
./scripts/build-app.sh --no-install --no-run
./scripts/package-release.sh --launch-smoke
```

For public direct distribution:

```bash
NEOQUILL_NOTARY_PROFILE=<profile> ./scripts/package-release.sh --strict-distribution --notarize
./scripts/market-readiness.sh
```

Release artifacts are written to `dist/`:

- `NeoQuill-v<version>-build<build>-<commit>.zip`
- matching `.zip.sha256`
- matching `.json` manifest

## Repository Map

- `Sources/NeoQuill` - app source
- `Tests/NeoQuillTests` - regression tests
- `scripts/build-app.sh` - local app bundle build/install/launch
- `scripts/package-release.sh` - release artifact packaging
- `scripts/verify-changelog.sh` - changelog release gate
- `scripts/market-readiness.sh` - paid/public distribution gate
- `docs/release-versioning.md` - version and release policy
- `docs/market-readiness.md` - distribution status and blockers
- `PRODUCT_RELEASE_PLAN.md` - product, pricing and launch plan

## Design Notes

NeoQuill belongs to the Neon family and uses the Emerald identity
(`#2EAB73`). The product should feel like a focused Mac utility, not a SaaS
dashboard: fast capture, clear transcript, useful summary, explicit actions.

## Open-Source Inspiration

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device speech AI
- [AudioCap](https://github.com/insidegui/AudioCap) for Core Audio Tap reference work
- [muesli](https://github.com/pHequals7/muesli) for pure-Swift local meeting transcription ideas
- [HushScribe](https://github.com/drcursor/HushScribe) for local meeting transcription positioning
