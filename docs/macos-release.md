# macOS Release Runbook (Mac App Store)

SnipSnaps ships on the same universal-purchase app record as iOS/iPadOS:
`com.kyter.SnipSnaps`, ASC app `6746975535`. Follow [release.md](release.md) for
versioning, notes, and the final release commit. ASC and git are the source of
truth for current release status; this runbook describes the standing setup.

## Xcode Cloud

Both enabled workflows archive the `SnipSnaps` scheme from
`SnipSnaps.xcodeproj`, distribute an App Store eligible build, and trigger only
on pushes to `main`:

| Platform | Workflow | ID |
|---|---|---|
| iOS/iPadOS | Default | `2C58B198-EB14-489F-A62D-487D9F58EF1B` |
| macOS | Default - macOS | `a171fa58-2a04-4c34-9a16-3d6dfe4a5361` |

Product: `43CEA0A8-23AD-4736-B633-C8A954293A22`.
Xcode Cloud manages distribution signing. No local distribution certificate or
Mac App Store provisioning profile is needed for this path. Distribution is
through the Mac App Store; a Developer ID notarization/export is not part of it.

Prepare code, release notes, version/build settings, metadata drafts, screenshot
assets, and documentation before merging the release PR. The final `main`
commit must be the source commit for both archives. Cloud assigns separate run
numbers, so the two uploaded build numbers can differ from each other and from
`CURRENT_PROJECT_VERSION`. Match both by marketing version and source SHA.

Use the Homebrew CLI to inspect the workflow and recent runs:

```sh
/opt/homebrew/bin/asc xcode-cloud workflows --app 6746975535
/opt/homebrew/bin/asc xcode-cloud build-runs --workflow-id <workflow-id> --sort=-number --limit 5
/opt/homebrew/bin/asc xcode-cloud status --run-id <run-id>
/opt/homebrew/bin/asc xcode-cloud build-runs builds --run-id <run-id>
```

Verify the actual Xcode version on the new runs. Detailed workflow toolchain
settings can be read through `asc web xcode-cloud workflows describe` with a
valid Apple web session. Public API authentication alone does not provide that
web session. If a trigger is missed, first confirm that no matching run exists,
then start the same committed `main` revision explicitly:

```sh
/opt/homebrew/bin/asc xcode-cloud run --workflow-id <workflow-id> --branch main
```

## Store metadata

The Mac draft is `marketing/app-store-metadata/app-store-connect-macos.json`.
Create the next `MAC_OS` version on the existing app, copy the last live version's
metadata, and update its release notes and review instructions. Use the four
committed 2880×1800 screenshots in
`marketing/app-store-screenshots/output/mac/` for the `APP_DESKTOP` set. Verify
uploaded checksums and order against the files before submission.

Review instructions describe Photos access, granting a folder, file categories,
keyboard controls, and recoverable Trash actions. SnipSnaps is free with no IAP,
uses no accounts or analytics, and declares `ITSAppUsesNonExemptEncryption=false`.
Verify the current privacy, age rating, content rights, pricing, and availability
in ASC when validating the release.

Once the selected build is VALID, use the shared release helper with the actual
Mac build number; this does not mutate repository files:

```sh
ASC_OP_ITEM=<item> npm run release:apply-notes -- --platform MAC_OS --build-number <mac-build> --target testflight --confirm
ASC_OP_ITEM=<item> npm run release:apply-notes:all -- --target appstore --confirm
ASC_OP_ITEM=<item> npm run release:notes:verify:all
/opt/homebrew/bin/asc versions attach-build --version-id <mac-version-id> --build-id <mac-build-id>
/opt/homebrew/bin/asc validate --app 6746975535 --version-id <mac-version-id> --platform MAC_OS
/opt/homebrew/bin/asc review submit --app 6746975535 --version-id <mac-version-id> --platform MAC_OS --build-id <mac-build-id> --confirm
```

The iOS version is staged and submitted separately on the same app record. Keep
build IDs and source SHAs in ASC/PR release evidence, rather than making another
commit to record them after the release build starts.

## Verification scope

Run macOS unit tests and a Release build before the release commit. File scanning
tests cover sorting, limits, reviewed items, overlapping roots, hidden files,
packages, symlinks, and duplicate grouping. Marketing demo captures verify
presentation; they do not exercise a real Photos library or the production file
permission flow.

A populated Mac smoke test should cover moving files to Trash and undoing,
resolving saved folder access across relaunch, and matching real similar photos.
Record which checks actually ran in the PR. iOS/iPad simulator checks cover the
Photos review flow and accessibility separately; physical-device haptic feel
requires a device.
