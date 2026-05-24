# Decision: Sparkle 2 Auto-Updater

Date: 2026-05-24

## Decision

Integrate **Sparkle 2.x** as auto-update framework for NeoQuill Direct-Sale builds.
Host `appcast.xml` and update ZIPs in a separate **public mirror repository**
`NKDesign30/neoquill-updates`. The main `NKDesign30/NeoQuill` repository stays
private.

## Why

- Without an auto-updater, every NeoQuill release would force the user to manually
  download and replace the `.app` bundle. That breaks the Direct-Sale loop.
- Sparkle is the de-facto Mac auto-update framework (Audio Hijack, Tower, BBEdit,
  Sketch, Things, Bear). EdDSA signatures, delta updates and SwiftUI integration
  are first-class.
- Public mirror repo solves the private-repo / public-download gap without
  requiring GitHub Pro Plan or external hosting.

## Architecture

```text
NKDesign30/NeoQuill (private)              NKDesign30/neoquill-updates (public)
  ├─ Sources/, Tests/, Resources/            ├─ appcast.xml
  ├─ scripts/build-app.sh                    ├─ releases/
  ├─ scripts/package-release.sh ──┐          │   ├─ NeoQuill-v0.9.14-*.zip
  └─ scripts/generate-appcast.sh ─┘──────►   │   └─ NeoQuill-v0.9.15-*.zip
                                             └─ README.md (Download-Page)

App (running on user Mac)
  └─ Sparkle  ──HTTPS GET──► raw.githubusercontent.com/.../appcast.xml
              ──HTTPS GET──► github.com/NKDesign30/neoquill-updates/releases/...
              └─ EdDSA-verify against SUPublicEDKey in Info.plist
```

## Hosting Decision

Three options were considered:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| GitHub Pages on private repo | Native, one repo | Requires GitHub Pro/Team plan | ❌ Niko doesn't have Pro |
| Vercel/Cloudflare Pages | Free, fast CDN | Extra service, separate auth | ⚠️ Adds dependency |
| **Public mirror repo** | Free, GitHub-native, ZIPs are first-class GitHub Releases | Two repos to push to per release | ✅ Chosen |

The mirror repo also doubles as the **public download page** for the Direct-Sale
website — `https://github.com/NKDesign30/neoquill-updates/releases` is the
canonical "where do I download NeoQuill" URL until `neoquill.com` exists.

## EdDSA Key Management

- One private/public key pair generated with Sparkle's `generate_keys` tool
- Private key stored in 1Password Automation Vault (same vault as the Developer
  ID Application Cert) — **never in repo, never in CI logs**
- Public key embedded in `Info.plist` as `SUPublicEDKey`
- `generate_appcast` signs every release ZIP with the private key
- Sparkle on the user's Mac verifies signatures before installing

If the private key is ever compromised, every future update would require a new
key pair AND a manual user migration (old app rejects updates signed with new
key). Treat with same care as the P12 password.

## Update Channel Strategy

- **One channel: `stable`** for now.
- Pre-release / beta channels can be added later by hosting a second
  `appcast-beta.xml` and toggling via Settings.
- `SUFeedURL` is fixed in Info.plist for v1; channel-switching is post-v1.

## Integration Scope (in NeoQuill code)

- `Package.swift`: add Sparkle SPM dependency, link to `NeoQuill` target.
- `App.swift`: own a `SPUStandardUpdaterController` as `@State` and expose
  `Check for Updates…` via `CommandGroup(after: .appInfo)`.
- `SettingsView.swift`: toggle for "Automatically check for updates"
  (bound to Sparkle's `automaticallyChecksForUpdates`).
- `Info.plist`: `SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`,
  `SUEnableDownloaderService` (Sparkle 2 XPC keys — even for non-sandboxed apps
  it's the recommended default).

## Build/Release Pipeline Integration

- `scripts/package-release.sh` keeps producing the signed + notarized ZIP in
  `dist/`.
- New `scripts/publish-update.sh`:
  1. Reads `dist/NeoQuill-vX.Y.Z-*.zip` and matching manifest.
  2. Clones / pulls `NKDesign30/neoquill-updates`.
  3. Copies ZIP into the mirror repo.
  4. Runs `generate_appcast` against the mirror repo's archive folder, signing
     with the EdDSA private key read from `~/.neoquill-signing/sparkle_ed25519`.
  5. Commits + pushes `appcast.xml` and the new ZIP to the mirror repo.
  6. Creates a GitHub Release in the mirror repo with the ZIP as asset.
- `scripts/market-readiness.sh` gets an extra check: `appcast.xml` lists the
  current `VERSION`.

## Verify Path

Live smoke after each Sparkle change:

1. Build + install v0.9.13 (already done).
2. Build v0.9.14 with a visible change (e.g., changelog entry).
3. Publish v0.9.14 to mirror repo via `publish-update.sh`.
4. Launch v0.9.13 → `Check for Updates…` → must show v0.9.14, install, relaunch.
5. After relaunch: `defaults read com.neon.quill SUFeedURL` matches; app version
   shows v0.9.14.

## Non-Goals

- Delta / binary-diff updates (Sparkle supports them but they require extra
  storage; ship full ZIPs for v1).
- Sandboxed update path (NeoQuill is not sandboxed by design — Direct-Sale only).
- Crash reporting integration (separate decision; out of scope here).
- In-app license check gating update access (license layer is its own slice).

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| EdDSA private key loss | 1Password backup, rotation plan documented in this file |
| Mirror repo desync (push fails mid-release) | `publish-update.sh` is idempotent; rerun overwrites |
| User downgrades by editing `SUFeedURL` | `SUFeedURL` in Info.plist is signed via codesign; tampering invalidates Developer ID signature |
| Apple notary delay blocks update publish | `publish-update.sh` runs AFTER package-release.sh, which already waits for notarization |
| `raw.githubusercontent.com` CDN cache | TTL ~5min; acceptable for non-critical updates |
