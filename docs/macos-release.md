# macOS Release Runbook (Mac App Store)

How to ship the macOS build of SnipSnaps on the **same universal-purchase app
record** as iOS/iPadOS (`com.kyter.SnipSnaps`, ASC app id `6746975535`). See
`docs/release.md` for the shared version/notes tooling; this doc covers only the
Mac-specific setup.

## Current state (updated 2026-07-14 — 1.1.0 iOS + macOS submitted for review)

- **macOS now ships via Xcode Cloud (Path B).** A second workflow **"Default - macOS"** (id `a171fa58-2a04-4c34-9a16-3d6dfe4a5361`) mirrors "Default" (iOS): a macOS archive of the `SnipSnaps` scheme, App Store distribution, triggering on push to `main`, on `latest:stable` (Xcode 26.5 / macOS Tahoe 26.5.1). Xcode Cloud handles Mac App Store distribution signing in the cloud — **no local Apple Distribution cert or MAS profile is needed.** Net effect: every push to `main` now produces an iOS **and** a macOS build.
- **1.1.0 is in review (submitted 2026-07-14).** iOS App Store version `5ccacaf2-879f-477f-9f2e-1f4c9cdc3278` (build **58**) and macOS version `f95f9217-9a40-4500-a281-e12e7e9c1e23` (build **59**, from commit `41efbb1`) are both `WAITING_FOR_REVIEW`, release type `AFTER_APPROVAL`. Live on the store today: **1.0.4** (iOS).
- **Build numbers are auto-incremented by Xcode Cloud** (ASC max + 1), so the committed `CURRENT_PROJECT_VERSION` (56) lags the shipped builds (58/59). This is cosmetic — the cloud ignores the local value.
- App is **free, no IAP** (no StoreKit in the codebase). App Privacy = **Data Not Collected** (published). Age rating **4+**. Export compliance auto-cleared (`ITSAppUsesNonExemptEncryption=false`).
- **Distribution decision: Mac App Store only.** Do **not** notarize — Apple notarizes MAS builds server-side. `notarytool`/`stapler` are only for Developer-ID direct downloads, which we are not doing.
- macOS metadata/screenshots/review-notes for the store live in `marketing/app-store-metadata/app-store-connect-macos.json` and `marketing/app-store-screenshots/output/mac/` (4 shots, 2880×1800, uploaded to the `APP_DESKTOP` set). ASC is the source of truth.

## Signing — pick one path

The dev Mac currently has only an "Apple Development" identity (no Apple
Distribution / Mac Installer Distribution cert, no `com.kyter.SnipSnaps`
profiles). You do **not** need to create certs by hand — pick a path:

### Path A — Xcode.app Automatic signing (simplest for a manual one-off)
The target uses `CODE_SIGN_STYLE=Automatic`. With the **W2W286Y75F** Apple ID
(Admin or App Manager) signed into **Xcode ▸ Settings ▸ Accounts**, Xcode mints
the **Apple Distribution** cert and the **Mac App Store** provisioning profile on
demand at archive time. Then:

1. Xcode ▸ scheme destination **My Mac** (or "Any Mac").
2. **Product ▸ Archive**.
3. In the **Organizer**, select the archive ▸ **Distribute App ▸ App Store Connect ▸ Upload**, keep "Automatically manage signing".
4. Repeat with an **iOS** destination for the iPhone/iPad archive.

### Path B — Xcode Cloud (✅ used for 1.1.0 — this is the standing setup)
Xcode Cloud manages distribution signing in the cloud, so no local certs are
needed. macOS 1.1.0 (build 59) shipped this way via a dedicated **"Default -
macOS"** workflow that mirrors the iOS "Default" workflow.

**How it was set up via the `asc` CLI (repeatable, no GUI):**
Requires an Apple web session (`asc web auth login --apple-id dev@kyter.com
--provider-id 127815394`; needs a 2FA code, so run interactively). Then:

```sh
# 1. Read the raw v15 payload of the working iOS workflow to use as a template.
#    (asc web ... workflows describe gives a SIMPLIFIED view that does NOT round-trip;
#     the create payload needs the full content shape incl. description,
#     environment_variables, product_environment_variables, locked, and an action id.)
# 2. Create the macOS workflow from a full payload (see marketing/.../workflow-macos template):
asc web xcode-cloud workflows create --product-id 43CEA0A8-23AD-4736-B633-C8A954293A22 \
  --file workflow-macos.json --apple-id dev@kyter.com
#    key fields vs iOS: actions[0].platform = {"name":"macOS"}, post_actions = [],
#    archive_config.distribution_type = "testFlightExternalAndAppStore".
# 3. Trigger a build for the current commit (public API, keychain creds — no web session):
asc xcode-cloud run --workflow-id <new-macos-workflow-id> --branch main
# 4. Monitor: asc xcode-cloud status --run-id <run> --wait ; asc builds wait --app 6746975535 \
#      --build-number <n> --version 1.1.0 --platform MAC_OS --fail-on-invalid
```

**GUI equivalent** (if you prefer): Xcode ▸ **Product ▸ Xcode Cloud ▸ Manage
Workflows** (or ASC ▸ your app ▸ **Xcode Cloud**) ▸ **＋** a workflow ▸ scheme
`SnipSnaps` ▸ Archive action with **Platform = macOS** ▸ deliver to App Store
Connect ▸ trigger on `main`.

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
