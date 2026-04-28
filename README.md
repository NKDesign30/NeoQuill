# NeoQuill

Native macOS Meeting-Capture-App. Local-first, on-device transcription, editorial UI.
Teil der Neon-Family — Forest Emerald · Warm Dark · Editorial Display.

## Stack

- SwiftUI 6 + Swift Package Manager
- macOS 15+ (Sonoma+)
- WhisperKit (Apple Silicon, on-device)
- Core Audio Process Tap (System-Audio) + AVAudioEngine (Mic) + ScreenCaptureKit (Fallback)
- SQLite (WAL-Mode) für Meetings/Transkripte
- Lizensierte Fonts: DM Serif Display, Inter, Geist Mono, Space Grotesk

## Open-Source-Inspiration

- [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) — On-device Speech AI
- [insidegui/AudioCap](https://github.com/insidegui/AudioCap) — Apple-Sample für Core Audio Tap
- [pHequals7/muesli](https://github.com/pHequals7/muesli) — Pure-Swift Granola-Klon, Multi-ASR
- [drcursor/HushScribe](https://github.com/drcursor/HushScribe) — Local meeting transcription
- Ghost Pepper — MIT-licensed local meeting tool

## Build

```bash
swift build
swift run NeoQuill
```

Bundle als `.app`:
```bash
./scripts/build-app.sh
```

## Status

In Bau. Phase A (Theme + Foundation) — laufend.
