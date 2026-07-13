# SnipSnaps for macOS — Implementation Plan

**Status:** ✅ **merged to `main` and shipped in the 1.1.0 / build 56 universal target** (Phases 0–2, 4, 4b + the full native UI/UX & desktop pass). macOS build green + launches (verified 2026-07-13 on macOS 26.5.2 / Xcode 26.6). Remaining work is **release/App Store Connect stand-up for the macOS platform**, not code — see `docs/macos-release.md` for the runbook.
**Target:** native macOS destination on the existing SwiftUI target (`MACOSX_DEPLOYMENT_TARGET` now **15.0** with macOS 26 Liquid Glass availability-gated; iOS stays 18.5)
**Distribution:** Mac App Store + App Sandbox (decided). App is free, no in-app purchase; universal purchase across iOS/iPadOS/macOS on one app record (`6746975535`, `com.kyter.SnipSnaps`).
**Author:** planning doc, 2026-06-22 · last updated 2026-07-13 (reconciled to shipped state)

## Native macOS UI/UX & desktop pass (2026-06-24)

A 70-finding audit (native shell / keyboard-menu / Liquid Glass / Finder / bugs / a11y), adversarially verified, then implemented in 6 phases and re-reviewed (3 issues caught + fixed). **Decisions:** keep the macOS floor at 15.0, use Liquid Glass only behind `#available(macOS 26, *)` with bordered/material fallbacks, replace the iOS bottom `TabView` with a native `NavigationSplitView` sidebar on macOS, and move Settings to a `Settings{}` scene (⌘,). Delivered:

- **Shell:** sidebar (Photos/Files), ⌘, Settings window, default/min window size, Mac title-bar Refresh, `.accentColor`→`.tint`, `@SceneStorage` sidebar selection.
- **Keyboard + menu bar:** `Commands/AppCommands.swift` (Edit▸Undo ⌘Z, File▸Add Folder ⇧⌘O, Review menu, Help URLs) bridged via `focusedSceneValue`; ←/→/Delete/Space/Esc on review surfaces, with Return reserved for summary/default actions (rule: `.keyboardShortcut` on Buttons, not `.onKeyPress` on non-focusable containers).
- **Finder integration (Files):** Reveal in Finder, Quick Look (Space), Open (double-click/⌘O), right-click context menus, drag-a-folder-to-add, sort menu, Show-in-Trash.
- **Liquid Glass:** `Design/GlassStyle.swift` (availability-gated glass buttons/info-chips with pre-macOS 26 fallbacks, hover highlight + pointer cursor), adaptive `AppColor.cardEdge`, recessed Mac card-hierarchy colors (fixed near-invisible Light-mode cards), monospaced hero digits.
- **Bug fixes:** iCloud `.icloud`-placeholder skip + on-disk allocated size (E1); 200k-cap truncation now reported via `ScanResult`/count warnings instead of silent-empty (E2); cancellable scans (E3); security-scoped-bookmark transient-preserve / removable-dead / re-grant-upgrade / inaccessible-folder warning (E4–E6); HomeView count-cache generation race (E7); trash/hash failure surfacing + memory-option snapshot (E8/E10); duplicate bucketing keyed on logical (not allocated) size.
- **Accessibility:** Reduce Motion, VoiceOver (decorative count hidden + merged cards + Files swipe actions), Dynamic Type growth, hit targets, `.help` tooltips, localized screenshot-name detection.
- **macOS app icon:** `mac_*.png` squircle set generated from the iOS artwork, wired into `AppIcon.appiconset/Contents.json`.

---

## Progress log (pause point)

All work is on branch `macos-port-phase-0-1`. Commits, newest first:

| Commit    | What                                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------- |
| `c63e466` | Review cleanup — align macOS 15 deployment docs, fix shortcut hints, harden Files retry/truncation paths      |
| `f596961` | Copilot review fixes — lower deploy target to 15, availability-gate Liquid Glass, a11y + UX polish            |
| `a933981` | Native UI/UX & desktop pass — sidebar, menus, keyboard shortcuts, Liquid Glass, Finder integration            |
| `fd76267` | Docs — update macOS port plan with progress log at pause point                                                |
| `9f7c826` | Phase 4b — Files "Remember Reviewed" (`FileReviewHistory`) + duplicate detection (size-bucket + SHA-256)      |
| `b902724` | Files↔Photos cohesion — shared `reviewLimit`, lifetime `totalDeletedCount`/`Bytes`, post-review count refresh |
| `2a684b7` | Phase 4 — on-disk Files cleanup surface (`SnipSnaps/Files/*`, `Views/Files/*`, macOS-only)                    |
| `5259bf4` | Phase 2 — Similar/duplicate scan on macOS (shared `CGImage` core)                                             |
| `fd8ee7b` | docs — record the Form layout-cycle crash + fix                                                               |
| `7647f1a` | Crash fix — `.formStyle(.grouped)` in Settings                                                                |
| `45264df` | Phase 0–1 — native Mac target, sandbox entitlements, UIKit-only fixes                                         |
| `1129e0e` | This plan doc                                                                                                 |

**Done:** Phase 0–1, Phase 2, Phase 3's native settings/menu/keyboard work, Phase 4 (incl. Duplicates), and full Files↔Photos settings/stats cohesion.

**Deviations from the original plan:**

- Built order was 0–1 → 2 → **4 → 4b**, deferring Phase 3 (polish) until after the Files surface existed so the desktop pass could cover Photos and Files together.
- Hit and fixed a macOS-only launch crash not anticipated in the plan: the default columnar `Form` style → AppKit "Update Constraints in Window pass" abort (see risk #10). Fix: `.formStyle(.grouped)`.
- A separate per-SDK entitlements file (`SnipSnaps-macOS.entitlements` via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`) is used so iOS keeps its own; the project already had `ENABLE_APP_SANDBOX=YES` / `ENABLE_USER_SELECTED_FILES` build settings (flipped to `readwrite` for Phase 4).

**Verification reality (this machine):**

- macOS builds verified green at every phase; app launches and the Files surface works live on a real Downloads folder (real scan counts).
- **iOS not buildable here** — the iOS 26.5 platform isn't installed in this Xcode, so iOS was verified only by construction (changes guarded/behavior-preserving). Build iOS on a normal setup before shipping.
- **Photos features not runtime-tested** — this Mac's Photos library is empty (0 assets), so Similar-matching accuracy on macOS is unverified.
- **Destructive Files paths not driven by Claude** — Trash, duplicate review, and remember-reviewed skip were left for the user to exercise (avoiding deletion of real files); they compile and the app launches.

**Remaining:**

- Near-duplicate _image_ matching for Files (reuse the Phase 2 dHash+Vision core fed `CGImageSource` from disk).
- Runtime-confirm the destructive Files flows + Similar matching on a Mac with a populated Photos library; iOS regression build.
- Mac App Store / ASC setup: first `MAC_OS` build upload and version metadata. Current ASC `MAC_OS` status has no builds yet.
- AppKit video/Live Photo playback on macOS; Photos-side Quick Look + VoiceOver swipe actions; String Catalog pluralization.

---

## Goal

Bring SnipSnaps to macOS with **two cleanup surfaces**:

1. **Photos** — the existing iCloud/Photos review-and-delete experience, ported to Mac.
2. **Files (new)** — review and clean up loose files on disk: Downloads, Desktop, Documents, on-disk screenshots, big/old/duplicate junk.

Distribution is **Mac App Store, sandboxed** — which has one important consequence baked into the whole plan: the Files surface **cannot silently scan** `~/Downloads`, `~/Desktop`, `~/Documents`. The user grants each folder once via a system picker; we persist that grant with a security-scoped bookmark. This is the standard, App-Review-approved model (Gemini 2, CleanMyMac ship this way).

---

## Target & distribution decision (settled)

- **Native macOS destination** on the existing single SwiftUI target — add **"Mac"** to _Supported Destinations_. The repo is already set up for this (`SDKROOT = auto`, existing `#if canImport(UIKit) / #elseif canImport(AppKit)` seams, `typealias PlatformImage = NSImage`).
- **Not** Mac Catalyst (scaled-iPad feel, awkward for a Finder-style file UI) and **not** "Designed for iPad" (strict iOS sandbox → no real file access → Files feature impossible).
- **Mac App Store + App Sandbox.** App Review permits destructive cleanup utilities; the only constraint is the user-granted-folder access model above.

---

## What ports vs. what's new (grounded in the current code)

| Area                                                                                                                         | Verdict                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PhotoLibrary` fetch/count/sort/delete (`Utils/Photos.swift`)                                                                | **Runs on macOS as-is.** PhotoKit + `PHAssetChangeRequest.deleteAssets` via `performChanges` (`Photos.swift:688`) is first-class on Mac; the existing `PHPhotosError.userCancelled` handling already matches the Mac system confirmation. |
| `PhotoReviewHistory`, `ReviewMode`, value types, image cache (NSImage branch)                                                | **Reusable as-is.**                                                                                                                                                                                                                       |
| Similar/duplicate scan (`fetchSimilarPhotoGroups`, `thumbnailImage`, `differenceHash`, `featurePrint`)                       | **Currently a no-op on macOS** — wrapped in `#if canImport(UIKit)`, AppKit branch returns `[]`. Needs a CGImage refactor (Phase 2).                                                                                                       |
| Unguarded UIKit (haptics, `UIApplication.open`, UIKit colors)                                                                | **Won't compile on Mac.** Must guard/replace (Phase 1).                                                                                                                                                                                   |
| iOS-only SwiftUI modifiers (`navigationBarTitleDisplayMode`, `topBar*`, `.tabBar`, `fullScreenCover`, `presentationDetents`) | **Won't compile on Mac.** Must guard/swap (Phase 1).                                                                                                                                                                                      |
| Files cleanup surface                                                                                                        | **Net-new.** ~60–70% of the _shape_ clones from the Photos flow; ~0% ports by direct call (everything is bound to `PHAsset`).                                                                                                             |

---

## Phase 0 — Project config + entitlements _(prerequisite, ~1 day)_

Nothing compiles or runs on Mac until this is done.

- [ ] Add **"Mac"** to the target's _Supported Destinations_; set `MACOSX_DEPLOYMENT_TARGET` (current `SUPPORTED_PLATFORMS` is `iphoneos iphonesimulator` only; `SDKROOT = auto` already correct).
- [ ] Populate `SnipSnaps/SnipSnaps.entitlements` (currently empty `<dict></dict>`):
  - `com.apple.security.app-sandbox` = `true` _(mandatory for Mac App Store)_
  - `com.apple.security.personal-information.photos-library` = `true` _(with the sandbox on, the Photos library is unreachable without this)_
  - `com.apple.security.files.user-selected.read-write` = `true` _(read-write to user-picked Downloads/Desktop/Documents folders)_
  - `com.apple.security.files.bookmarks.app-scope` = `true` _(persist folder grants across launches)_
  - `com.apple.security.files.downloads.read-write` = `true` _(optional convenience: pre-grants Downloads with no picker; no Desktop/Documents equivalent exists)_
- [ ] Add `Info.plist` usage strings: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription` (keep existing `NSPhotoLibraryUsageDescription`).

> ⚠️ With the sandbox on, any file access outside the container that isn't a granted/bookmarked URL **silently fails** — it is not a build error. Route all file access through granted URLs.

**Payoff:** the project builds for a Mac destination; gates everything else.

---

## Phase 1 — Make the Photos build compile + run on macOS _(cheap win, ~1–2 days)_

Fix the unguarded platform code so the existing Photos features build and run on Mac. **Every mode except Similar works immediately** after this, because the engine and PhotoKit deletion are already cross-platform.

**Unguarded UIKit (breaks the build):**

- [ ] `ContentView.swift:40` — wrap `UIImpactFeedbackGenerator(...)` in `#if canImport(UIKit)`.
- [ ] `SettingsView.swift:78`, `:170`, `:222` — replace `UIApplication.shared.open(url)` with SwiftUI `@Environment(\.openURL)` (cross-platform, cleanest).
- [ ] `SettingsView.swift:92`, `:201`, `ScreenshotDemoView.swift:371` — replace `Color(UIColor.tertiaryLabel)` with `.foregroundStyle(.tertiary)`.
- [ ] `Design/AppColors.swift` — give `background`/`card` platform-conditional definitions. `Color(.systemGroupedBackground)` / `.secondarySystemGroupedBackground` don't exist on AppKit. Map AppKit → `Color(nsColor: .windowBackgroundColor)` / `.controlBackgroundColor` (or define an asset-catalog color set so `AppColor` is one cross-platform source of truth). Same for inline `Color(.tertiarySystemGroupedBackground)` in `HomeView` (3×), `ScreenshotDemoView` (4×), and `Color(.secondarySystemBackground)` / `Color(.tertiarySystemFill)` in `ReviewSessionView`'s card views.

**iOS-only SwiftUI modifiers (`#if os(iOS)` or swap):**

- [ ] `.navigationBarTitleDisplayMode(...)` — `ReviewSessionView` (`:303`, `:1063`, `:2093`) + `HomeView:175`.
- [ ] `ToolbarItem(placement: .topBarLeading/.topBarTrailing)` → cross-platform placements (`.navigation`/`.primaryAction`/`.cancellationAction`) — `ReviewSessionView` (`:313`, `:1067`, `:2095`) + `HomeView:177`.
- [ ] `.toolbar(.hidden, for: .tabBar)` — `ReviewSessionView:323`, `:1078` (omit on macOS).
- [ ] `.fullScreenCover(item:)` → `.sheet(item:)` on macOS — `ReviewSessionView:1079`.
- [ ] `statusBarHidden` (`ReviewSessionView:1981`) and `.presentationDetents([...])` (`:2100`) — wrap in `#if os(iOS)`.
- [ ] Optionally `#if os(iOS)` out the DEBUG-only `ScreenshotDemoView` for the first Mac build.

**Payoff:** a running Mac app that fetches, counts, reviews, and deletes Photos across all modes except Similar.

---

## Phase 2 — Restore Similar/duplicate detection on macOS _(~2–3 days)_

The headline 1.0.4 "Similar" mode is a silent empty screen on Mac until this is done.

- [ ] Refactor `thumbnailImage` (`Photos.swift:1296`), `featurePrint` (`:1342`), `differenceHash` (`:1373`) to operate on **`CGImage`** instead of `UIImage`. `differenceHash` is already pure CoreGraphics; Vision (`VNGenerateImageFeaturePrintRequest`) is fully cross-platform.
- [ ] Lift the `fetchSimilarPhotoGroups` body (`Photos.swift:515+`) out of `#if canImport(UIKit)`. The **only** platform-conditional step becomes `PHAsset → CGImage` (request a `CGImage` directly, or `NSImage.cgImage(forProposedRect:context:hints:)` on the AppKit side).
- [ ] Re-tune thresholds against Mac-rendered thumbnails (dHash hamming ≤ 14, Vision distance ≤ 0.35) — NSImage→CGImage color-space differences can shift values.

**Payoff:** Photos surface reaches feature parity on Mac.

> Video and Live Photo playback are already `#if`-gated and degrade to a still image — acceptable for v1. AppKit playback parity (`AVPlayerView`, `PHLivePhotoView` on macOS) is optional later work.

---

## Phase 3 — Mac-native review UX polish _(~1–2 days)_

The touch-tuned swipe loop feels broken with a mouse and gives no haptics on Mac.

- [ ] Add keyboard shortcuts via `.keyboardShortcut` / `.onKeyPress`: ← or Delete = delete, → = keep, Cmd-Z = undo, Space = preview/details, Return = summary/default action.
- [ ] Make the decision-bar buttons the primary interaction; keep the `DragGesture` swipe for trackpad users.
- [ ] Optional: `NSHapticFeedbackManager` for trackpad feedback (haptics already no-op on macOS).

**Payoff:** feels like a Mac app, not a stretched phone app.

> **Milestone candidate:** Phases 0–3 are a shippable "SnipSnaps for Mac — Photos" release on their own.

---

## Phase 4 — Net-new Files cleanup surface _(the harder half, ~8–15 days)_

Build a parallel engine + UI, keyed on a `FileItem` value type, cloning the proven Photos patterns. Gate behind `#if os(macOS)` so iOS is untouched.

### 4a. Folder access + persistence (the platform plumbing)

- [ ] New "Files" tab (SF Symbol `folder`) alongside Home + Settings, `#if os(macOS)`.
- [ ] Empty-state onboarding: "Choose a folder" with quick presets for Downloads / Desktop / Documents, each opening `.fileImporter(allowedContentTypes: [.folder])` / `NSOpenPanel(canChooseDirectories: true)`.
- [ ] On grant: create an **app-scoped security-scoped bookmark** (`url.bookmarkData(options: .withSecurityScope, …)`), persist it; list granted folders with a revoke control.
- [ ] On launch: resolve bookmarks (`URL(resolvingBookmarkData:options:.withSecurityScope, bookmarkDataIsStale:&stale)`), recreate if stale.
- [ ] Wrap **every** access in `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` — use `defer` rigorously (leaks otherwise).

### 4b. Scan engine (`FileLibrary`, the on-disk analog of `PhotoLibrary`)

- [ ] Enumerate granted folders via `FileManager.enumerator(at:includingPropertiesForKeys:options:)` prefetching `.fileSizeKey`, `.contentModificationDateKey`, `.creationDateKey`, `.isDirectoryKey`, `.contentTypeKey`.
- [ ] Build `[FileItem]` (url, size, created, modified, contentType). Run off the main actor with the existing `SimilarPhotoScanProgress`-style progress + partial-results streaming and cancellation (mirror the `scanTask` pattern).
- [ ] **Categories** (the file analog of `ReviewMode`):
  - **Large Files** — size desc, configurable threshold (e.g. ≥ 50 MB).
  - **Old Files** — `modificationDate` older than N months.
  - **On-Disk Screenshots** — UTType `.png`/`.image` + filename match (`Screenshot`/`Screen Shot`, locale-aware) **OR** `kMDItemIsScreenCapture` Spotlight metadata. Combine signals; let the user confirm.
  - **Downloads Clutter** — everything in Downloads by age/size.
  - **Duplicate Files** — size-bucket pre-pass, then SHA-256 only within same-size buckets. For near-duplicate images, reuse the dHash + Vision pipeline from Phase 2, fed `CGImageSourceCreateWithURL` instead of `PHCachingImageManager`.

### 4c. Review UI (`FileReviewSessionView`)

- [ ] Clone the swipe card stack + decision bar + deferred-delete summary + per-item Undo, keyed on `FileItem`.
- [ ] Thumbnails via `QLThumbnailGenerator` (any file type) or `CGImageSource` (images). Card shows name, size, path, dates.
- [ ] Keyboard shortcuts (same scheme as Phase 3).

### 4d. Deletion (safety-critical)

- [ ] Mark in-memory during review (fully reversible — nothing touched on disk); only the final **"Move N to Trash"** button acts.
- [ ] Delete via `FileManager.trashItem(at:resultingItemURL:)` — **never** `removeItem` (permanent). Capture `resultingItemURL` (files are renamed on collision).
- [ ] Persist `[originalURL → resultingItemURL]` pairs for a post-trash Undo (`moveItem`); macOS Cmd-Z / Restore-from-Trash also work, so this is nice-to-have.
- [ ] **Do not** call `trashItem` inside an `NSFileCoordinator.coordinate` block (deadlock).
- [ ] Exclude `.app` bundles, packages, symlinks, dotfiles, and iCloud-evicted `.icloud` placeholders.

### 4e. File-scoped review memory

- [ ] Extend the `PhotoReviewHistory` design, re-keyed from `PHAsset.localIdentifier` to a **stable file identity** (`.fileResourceIdentifierKey` / volume-id+inode, or bookmark data) since paths change. Same expiration windows.

**Payoff:** delivers your distinctive second goal — cleaning loose Downloads/Desktop/Documents junk.

---

## Recommended architectural refactor (optional but worth it)

Before/while building Phase 4, factor the decision/swipe/summary/undo state machine into a generic **`ReviewEngine<Item>`** with a small protocol (`id`, thumbnail provider, `sizeBytes`, dates, delete action). Have both `PHAsset` and `FileItem` conform. Then Photos and Files share one engine + one card view, with platform-specific input (touch+haptics on iOS, keyboard+trackpad on macOS). Turns "copy-paste" into real reuse.

---

## Effort summary (solo)

| Scope                       | Effort         |
| --------------------------- | -------------- |
| Phases 0–3: Photos on macOS | ~1.5–2.5 weeks |
| Phase 4: Files surface      | ~2–3 weeks     |
| **Both, shipped well**      | **~4–6 weeks** |

Suggested sequencing: ship **Phases 0–3 as "SnipSnaps for Mac (Photos)"** first, then follow with the Files surface as a feature update.

---

## Top risks / gotchas

1. **Similar mode silently empty on Mac** until the Phase 2 CGImage refactor — don't ship the Mac build with it visible-but-broken; port it or hide it.
2. **Empty entitlements file today** — with the sandbox on, missing `photos-library` / file entitlements = silent runtime denial, not a build error.
3. **Grant folders, not individual files** — a single-file sandbox extension doesn't grant write to the parent dir, and trash is a _move_ out of it, so trashing a lone picked file fails with `NSFileWriteNoPermissionError`.
4. **No full-disk auto-scan on the App Store** — no Desktop/Documents entitlement exists (only Downloads), so the user grants each folder. Set product expectations: this is a per-folder model by design.
5. **Destructive safety on files > Photos** — Photos has Recently Deleted (30-day); files must use `trashItem` (recoverable), exclude bundles/symlinks/dotfiles/`.icloud` placeholders.
6. **Security-scoped bookmark hygiene** — persist them or the user re-picks every launch; handle `bookmarkDataIsStale`; balance every `start`/`stop` with `defer`.
7. **iCloud "Desktop & Documents Folders"** — enumerating/hashing dataless placeholders can pull gigabytes; detect `NSURLUbiquitousItemIsDownloadedKey` and skip/warn.
8. **Touch-tuned swipe UX** feels wrong with a mouse — Phase 3 keyboard shortcuts + button-first interaction are not optional polish, they're required for a usable desktop loop.
9. **App Store privacy labels (2026 rules)** — disclose local data handling accurately.
10. **macOS `Form` default style crashes at launch** _(found + fixed in Phase 1)_ — SwiftUI's default columnar `Form` style on macOS can trip an AppKit "Update Constraints in Window pass" cycle (`NSGenericException`/SIGABRT) once a form has enough rows. `TabView` eagerly lays out all tabs on macOS, so a crash in any tab aborts the whole app at launch. Fix: `.formStyle(.grouped)` (no-op on iOS, where grouped is already the default). Watch for the same cycle in any future macOS `Form`/`List`-heavy screens (e.g. the Files-folder settings).

---

## Verification notes

The macOS platform facts above were web-verified against current Apple docs (entitlement key reference, "Requesting Changes to the Photo Library," App Review Guideline 2.4.5(i)) and four adversarial checks (sandbox file delete, PhotoKit delete UX, App Review approval, target choice) — all returned _confirmed-with-conditions_; the conditions are folded into the phases and risks above.
