# Decision: Sparkle 2 Auto-Updater

Date: 2026-05-24

## Decision

Integrate **Sparkle 2.x** as auto-update framework for NeoQuill Direct-Sale builds.
Host `appcast.xml` and update artefacts **directly in `NKDesign30/NeoQuill`**
once the repository is flipped to public visibility.

> **2026-05-24 update.** The initial plan was a separate public mirror repo to
> keep the source private. Niko decided to make the main repo public instead, so
> the mirror plan is dropped. See "Hosting Decision" below.
>
> **2026-05-30 update.** The public Direct-Sale artefact is the signed and
> notarized DMG. The ZIP stays available as a legacy / scripted fallback and as
> the source for the build manifest. `publish-update.sh` now uses the newest
> manifest as source of truth and requires a clean tracked worktree plus the
> matching DMG, ZIP, both SHA256 sidecars and JSON manifest before it publishes
> the appcast / GitHub Release.

## Why

- Without an auto-updater, every NeoQuill release would force the user to
  manually download and replace the `.app` bundle. That breaks the Direct-Sale
  loop.
- Sparkle is the de-facto Mac auto-update framework (Audio Hijack, Tower, BBEdit,
  Sketch, Things, Bear). EdDSA signatures, delta updates and SwiftUI integration
  are first-class.

## Architecture

```text
NKDesign30/NeoQuill (public)
  ├─ Sources/, Tests/, Resources/, scripts/
  ├─ appcast.xml                    ← live Sparkle feed
  ├─ CHANGELOG.md
  └─ Releases/                      ← GitHub Releases UI
       ├─ NeoQuill-v0.9.16-*.dmg        (primary Direct-Sale installer)
       ├─ NeoQuill-v0.9.16-*.dmg.sha256
       ├─ NeoQuill-v0.9.16-*.zip        (legacy / scripted fallback)
       ├─ NeoQuill-v0.9.16-*.zip.sha256
       └─ NeoQuill-v0.9.16-*.json       (build manifest)

App (running on user Mac)
  └─ Sparkle  ──HTTPS GET──► raw.githubusercontent.com/NKDesign30/NeoQuill/main/appcast.xml
              ──HTTPS GET──► github.com/NKDesign30/NeoQuill/releases/download/v*.dmg
              └─ EdDSA-verify against SUPublicEDKey in Info.plist
```

## Hosting Decision

Three options were considered initially:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| GitHub Pages on private repo | Native, one repo | Requires GitHub Pro/Team plan | ❌ Not available |
| Vercel/Cloudflare Pages | Free, fast CDN | Extra service, separate auth | ⚠️ Extra moving part |
| Separate public mirror repo | Source stays private | Two repos to push per release | Initial pick, then dropped |
| **Public main repo** | One repo, simplest pipeline, source-available is a feature | Code is open | ✅ Chosen by Niko |

Public-source for a paid app is a deliberate trade-off: it builds trust
("local-first, see for yourself"), invites contributions, and shifts the
defensible moat to the license layer + brand + maintained binaries — not to
obscurity.

## EdDSA Key Management

- One private/public key pair generated with Sparkle's `generate_keys` tool.
- Private key stored in 1Password Automation Vault (same vault as the Developer
  ID Application cert) — **never in repo, never in CI logs**.
- Public key embedded in `Info.plist` as `SUPublicEDKey`.
- `generate_appcast` signs the selected release archive with the private key.
  Current public pipeline signs the DMG enclosure; ZIP remains a release asset
  for legacy / scripted fallback.
- Sparkle on the user's Mac verifies signatures before installing.

If the private key is ever compromised, every future update would require a new
key pair AND a manual user migration (old app rejects updates signed with new
key). Treat with same care as the P12 password.

## Update Channel Strategy

- **One channel: `stable`** for now.
- Pre-release / beta channels can be added later by hosting a second
  `appcast-beta.xml` and toggling via Settings.
- `SUFeedURL` is fixed in Info.plist for v1; channel-switching is post-v1.

## Integration Scope (in NeoQuill code)

- `Package.swift`: Sparkle SPM dependency linked to the `NeoQuill` target.
- `App.swift`: owns a `SPUStandardUpdaterController` via `AppUpdater` and
  exposes `Nach Updates suchen…` via `CommandGroup(after: .appInfo)`.
- `Services/AutoUpdater.swift`: thin wrapper that publishes `canCheckForUpdates`
  for the menu enable/disable state.
- `SettingsView.swift`: toggle for "Automatically check for updates"
  (bound to Sparkle's `automaticallyChecksForUpdates`) — Slice D.
- `Info.plist`: `SUFeedURL` + `SUPublicEDKey` + `SUEnableAutomaticChecks`.

## Build/Release Pipeline Integration

- `scripts/package-release.sh` keeps producing the signed + notarized ZIP and
  JSON manifest in `dist/`.
- `scripts/build-dmg.sh --notarize` packages the signed app into the branded,
  signed, notarized and stapled DMG installer.
- `scripts/publish-update.sh`:
  1. Selects the newest `dist/NeoQuill-vX.Y.Z-*.json` by build number.
  2. Requires a clean tracked worktree, the matching ZIP from the manifest,
     matching DMG by build/commit and both SHA256 sidecars.
  3. Runs `generate_appcast` against a temporary directory containing only the
     matching DMG, signing with the EdDSA private key from the macOS Keychain.
  4. Copies the updated `appcast.xml` into the repo root.
  5. Commits `appcast.xml` on `main` for full public publish; `--dry-run` and
     `--skip-push` stay available for preview / local review.
  6. Creates a GitHub Release for tag `vX.Y.Z` with DMG, DMG SHA256, ZIP, ZIP
     SHA256 and manifest assets.
- `scripts/market-readiness.sh` checks the current `VERSION`, local manifest /
  ZIP / SHA256, signed + stapled local DMG, GitHub Release assets and appcast
  readiness.

## Verify Path

Live smoke after each Sparkle change:

1. Build + install the previous public release.
2. Build/package the next release via `package-release.sh` and
   `build-dmg.sh --notarize`.
3. Publish the next release via `publish-update.sh`.
4. Launch the previous app → menu → `Nach Updates suchen…` → must show the next
   release, download the appcast archive, install and relaunch.
5. After relaunch: `defaults read com.neon.neoquill SUFeedURL` matches; app
   version shows the published release.
6. Run `./scripts/market-readiness.sh`; it must pass the DMG, ZIP, manifest,
   GitHub Release and appcast checks for the current `VERSION`.

## Non-Goals

- Delta / binary-diff updates (Sparkle supports them but they need extra
  storage; ship full DMGs for the public channel and ZIP fallback for v1).
- Sandboxed update path (NeoQuill is not sandboxed by design — Direct-Sale only).
- Crash reporting integration (separate decision; out of scope here).
- In-app license check gating update access (license layer is its own slice).

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| EdDSA private key loss | 1Password backup, rotation plan documented in this file |
| Pushing while a tag is half-published | `publish-update.sh` is idempotent; rerun overwrites |
| User downgrades by editing `SUFeedURL` | `SUFeedURL` in Info.plist is signed via codesign; tampering invalidates Developer ID signature |
| Apple notary delay blocks update publish | `publish-update.sh` runs after `package-release.sh` and `build-dmg.sh --notarize`; `market-readiness.sh` validates DMG signature and stapled ticket before public ship |
| ZIP fallback drifts from DMG release | `market-readiness.sh` requires the GitHub Release to contain DMG, ZIP, both SHA256 sidecars and the JSON manifest |
| `raw.githubusercontent.com` CDN cache | TTL ~5min; acceptable for non-critical updates |
| Public source visible to competitors | Trade-off accepted; differentiation moves to license layer, brand, distribution |
