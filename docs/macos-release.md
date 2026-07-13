# macOS Release Runbook (Mac App Store)

How to ship the macOS build of SnipSnaps on the **same universal-purchase app
record** as iOS/iPadOS (`com.kyter.SnipSnaps`, ASC app id `6746975535`). See
`docs/release.md` for the shared version/notes tooling; this doc covers only the
Mac-specific setup.

## Current state (verified 2026-07-13)

- macOS code is **shipped on `main`** in the 1.1.0 / build 56 universal target; the app builds green and launches on macOS 26.5.2 / Xcode 26.6.
- App Store Connect **iOS**: 1.0.4 live; **1.1.0 build 57 VALID**, TestFlight beta-approved, App Store version in `PREPARE_FOR_SUBMISSION` (0 blockers).
- App Store Connect **macOS**: platform reachable but **empty — 0 versions, 0 builds** (`npm run release:status:mac` → "No builds found").
- App is **free, no IAP** (no StoreKit in the codebase).
- **Distribution decision: Mac App Store only.** Do **not** notarize — Apple notarizes MAS builds server-side. `notarytool`/`stapler` are only for Developer-ID direct downloads, which we are not doing.

## Signing — pick one path

The dev Mac currently has only an "Apple Development" identity (no Apple
Distribution / Mac Installer Distribution cert, no `com.kyter.SnipSnaps`
profiles). You do **not** need to create certs by hand — pick a path:

### Path A — Xcode.app Automatic signing (simplest, recommended for now)
The target uses `CODE_SIGN_STYLE=Automatic`. With the **W2W286Y75F** Apple ID
(Admin or App Manager) signed into **Xcode ▸ Settings ▸ Accounts**, Xcode mints
the **Apple Distribution** cert and the **Mac App Store** provisioning profile on
demand at archive time. Then:

1. Xcode ▸ scheme destination **My Mac** (or "Any Mac").
2. **Product ▸ Archive**.
3. In the **Organizer**, select the archive ▸ **Distribute App ▸ App Store Connect ▸ Upload**, keep "Automatically manage signing".
4. Repeat with an **iOS** destination for the iPhone/iPad archive.

### Path B — Xcode Cloud (matches how iOS build 57 shipped)
An Xcode Cloud product already exists for this app (`asc apps ci-product view
--id 6746975535` → product "SnipSnaps"). Xcode Cloud manages distribution
signing in the cloud. To also build macOS:

1. Xcode ▸ **Product ▸ Xcode Cloud ▸ Manage Workflows** (or App Store Connect ▸ your app ▸ **Xcode Cloud** tab).
2. Open the existing release workflow (or **＋** a new one).
3. Under **Environment**, keep the scheme `SnipSnaps`.
4. **Archive action** → set/add **Platform = macOS** (Xcode Cloud archive actions are per-platform; add a macOS archive alongside the iOS one, or clone the workflow with Platform = macOS).
5. **Post-Actions ▸ TestFlight and App Store Connect** so the macOS archive is delivered to ASC automatically.
6. Trigger on your release branch. Xcode Cloud handles the Apple Distribution + Mac App Store signing.

### Path C — command line (for a scripted/CI archive; optional)
Once a distribution cert exists (Path A creates it), you can script it. No
notarization for MAS.

```sh
# macOS App Store archive
xcodebuild -project SnipSnaps.xcodeproj -scheme SnipSnaps -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/SnipSnaps-mac.xcarchive archive

xcodebuild -exportArchive -archivePath build/SnipSnaps-mac.xcarchive \
  -exportPath build/export-mac -exportOptionsPlist ExportOptions-MAS.plist

# upload the signed .pkg (Apple notarizes MAS itself; do NOT run notarytool)
xcrun altool --upload-app -f build/export-mac/SnipSnaps.pkg -t macos \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

`ExportOptions-MAS.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>W2W286Y75F</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
```

The iOS/iPad archive is the same with `-destination 'generic/platform=iOS'`, a
`.ipa` output, and `-t ios` on upload.

## Release sequence (launch iOS + macOS 1.1.0 together)

1. **App Store Connect app setup (once):**
   - Confirm the **macOS platform** is enabled on record 6746975535 (universal purchase — never create a second Mac record). First Mac build upload finalizes it.
   - **Pricing & Availability**: price = **Free**, and confirm the **macOS** platform is available in the intended territories (Mac availability is not auto-toggled by the iOS availability).
2. **Build numbers:** for the first Mac upload, build 56 is fine (Mac has an independent sequence). For later builds keep them in lockstep:
   ```sh
   ASC_OP_ITEM=<item> npm run release:next-build:all -- --apply   # writes max(next iOS, next Mac)
   ```
3. **Archive + upload both platforms** (Path A/B/C above). Confirm both process to VALID:
   ```sh
   ASC_OP_ITEM=<item> npm run release:status:all
   ```
4. **Create the macOS 1.1.0 version** and fill its metadata from
   `marketing/app-store-metadata/app-store-connect-macos.json`:
   - Description (covers Photos + the Mac Files surface), subtitle, keywords, promo text.
   - **Screenshots:** upload the 4 committed shots from `marketing/app-store-screenshots/output/mac/` (2880×1800) to the macOS slot.
   - **App Review notes:** paste the Mac-specific `reviewNotes` (folder-grant flow + Trash recoverability + how to get test content). This is important — a destructive utility with no testable content risks a Guideline 2.1 rejection.
5. **Submission gates (both platforms):** App Privacy = **Data Not Collected**; **age rating** questionnaire (2026 rules) per platform; export compliance (auto from `ITSAppUsesNonExemptEncryption=false`); content rights = no third-party content; verify privacy/support/terms URLs return 200.
6. **Apply What's New** to both platforms from `docs/next-release-notes.md`:
   ```sh
   ASC_OP_ITEM=<item> npm run release:apply-notes:all -- --confirm
   ```
7. **Submit** both the iOS and macOS versions for review (attach build 57+ to iOS, the new Mac build to macOS).
8. **Tag** the shipped commit (shared): `npm run release:tag -- --confirm`.

## Platform-aware release tooling

The npm release scripts now take `--platform IOS|MAC_OS|all` (default `IOS`;
also `SNIPSNAPS_PLATFORM`). Convenience scripts:

| Script | Effect |
|---|---|
| `release:status` / `:mac` / `:all` | ASC status for iOS / macOS / both |
| `release:next-build` / `:all` | next build number; `:all --apply` writes the max so the shared `CURRENT_PROJECT_VERSION` is valid for both trains |
| `release:apply-notes` / `:mac` / `:all` | push What's New / TestFlight notes to iOS / macOS / both |
| `release:backfill` / `:all` | regenerate `docs/apple-release-history.md` (now has a Platform column) |

All ASC-backed scripts need the 1Password-injected key, e.g.
`ASC_OP_ITEM=<item> npm run release:status:all` or
`op run --env-file <private-asc-env> -- npm run release:status:all`.

## Pre-ship verification still owed (on a populated Mac)

- Files ▸ move-to-Trash + **⌘Z undo** round-trip.
- Security-scoped-bookmark resolve/stale/re-grant across an app relaunch.
- Similar/duplicate matching accuracy on a real library.
- iOS/iPad regression build + core Photos flow (can be done on the dev Mac — iOS 18.5–26.5 simulators are installed).
