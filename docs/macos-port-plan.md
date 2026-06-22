# SnipSnaps for macOS — Implementation Plan

**Status:** proposed (planning only — no code changes yet)
**Target:** native macOS destination on the existing SwiftUI target
**Distribution:** Mac App Store + App Sandbox (decided)
**Author:** planning doc, 2026-06-22

---

## Goal

Bring SnipSnaps to macOS with **two cleanup surfaces**:

1. **Photos** — the existing iCloud/Photos review-and-delete experience, ported to Mac.
2. **Files (new)** — review and clean up loose files on disk: Downloads, Desktop, Documents, on-disk screenshots, big/old/duplicate junk.

Distribution is **Mac App Store, sandboxed** — which has one important consequence baked into the whole plan: the Files surface **cannot silently scan** `~/Downloads`, `~/Desktop`, `~/Documents`. The user grants each folder once via a system picker; we persist that grant with a security-scoped bookmark. This is the standard, App-Review-approved model (Gemini 2, CleanMyMac ship this way).

---

## Target & distribution decision (settled)

- **Native macOS destination** on the existing single SwiftUI target — add **"Mac"** to *Supported Destinations*. The repo is already set up for this (`SDKROOT = auto`, existing `#if canImport(UIKit) / #elseif canImport(AppKit)` seams, `typealias PlatformImage = NSImage`).
- **Not** Mac Catalyst (scaled-iPad feel, awkward for a Finder-style file UI) and **not** "Designed for iPad" (strict iOS sandbox → no real file access → Files feature impossible).
- **Mac App Store + App Sandbox.** App Review permits destructive cleanup utilities; the only constraint is the user-granted-folder access model above.

---

## What ports vs. what's new (grounded in the current code)

| Area | Verdict |
|---|---|
| `PhotoLibrary` fetch/count/sort/delete (`Utils/Photos.swift`) | **Runs on macOS as-is.** PhotoKit + `PHAssetChangeRequest.deleteAssets` via `performChanges` (`Photos.swift:688`) is first-class on Mac; the existing `PHPhotosError.userCancelled` handling already matches the Mac system confirmation. |
| `PhotoReviewHistory`, `ReviewMode`, value types, image cache (NSImage branch) | **Reusable as-is.** |
| Similar/duplicate scan (`fetchSimilarPhotoGroups`, `thumbnailImage`, `differenceHash`, `featurePrint`) | **Currently a no-op on macOS** — wrapped in `#if canImport(UIKit)`, AppKit branch returns `[]`. Needs a CGImage refactor (Phase 2). |
| Unguarded UIKit (haptics, `UIApplication.open`, UIKit colors) | **Won't compile on Mac.** Must guard/replace (Phase 1). |
| iOS-only SwiftUI modifiers (`navigationBarTitleDisplayMode`, `topBar*`, `.tabBar`, `fullScreenCover`, `presentationDetents`) | **Won't compile on Mac.** Must guard/swap (Phase 1). |
| Files cleanup surface | **Net-new.** ~60–70% of the *shape* clones from the Photos flow; ~0% ports by direct call (everything is bound to `PHAsset`). |

---

## Phase 0 — Project config + entitlements *(prerequisite, ~1 day)*

Nothing compiles or runs on Mac until this is done.

- [ ] Add **"Mac"** to the target's *Supported Destinations*; set `MACOSX_DEPLOYMENT_TARGET` (current `SUPPORTED_PLATFORMS` is `iphoneos iphonesimulator` only; `SDKROOT = auto` already correct).
- [ ] Populate `SnipSnaps/SnipSnaps.entitlements` (currently empty `<dict></dict>`):
  - `com.apple.security.app-sandbox` = `true` *(mandatory for Mac App Store)*
  - `com.apple.security.personal-information.photos-library` = `true` *(with the sandbox on, the Photos library is unreachable without this)*
  - `com.apple.security.files.user-selected.read-write` = `true` *(read-write to user-picked Downloads/Desktop/Documents folders)*
  - `com.apple.security.files.bookmarks.app-scope` = `true` *(persist folder grants across launches)*
  - `com.apple.security.files.downloads.read-write` = `true` *(optional convenience: pre-grants Downloads with no picker; no Desktop/Documents equivalent exists)*
- [ ] Add `Info.plist` usage strings: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription` (keep existing `NSPhotoLibraryUsageDescription`).

> ⚠️ With the sandbox on, any file access outside the container that isn't a granted/bookmarked URL **silently fails** — it is not a build error. Route all file access through granted URLs.

**Payoff:** the project builds for a Mac destination; gates everything else.

---

## Phase 1 — Make the Photos build compile + run on macOS *(cheap win, ~1–2 days)*

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

## Phase 2 — Restore Similar/duplicate detection on macOS *(~2–3 days)*

The headline 1.0.4 "Similar" mode is a silent empty screen on Mac until this is done.

- [ ] Refactor `thumbnailImage` (`Photos.swift:1296`), `featurePrint` (`:1342`), `differenceHash` (`:1373`) to operate on **`CGImage`** instead of `UIImage`. `differenceHash` is already pure CoreGraphics; Vision (`VNGenerateImageFeaturePrintRequest`) is fully cross-platform.
- [ ] Lift the `fetchSimilarPhotoGroups` body (`Photos.swift:515+`) out of `#if canImport(UIKit)`. The **only** platform-conditional step becomes `PHAsset → CGImage` (request a `CGImage` directly, or `NSImage.cgImage(forProposedRect:context:hints:)` on the AppKit side).
- [ ] Re-tune thresholds against Mac-rendered thumbnails (dHash hamming ≤ 14, Vision distance ≤ 0.35) — NSImage→CGImage color-space differences can shift values.

**Payoff:** Photos surface reaches feature parity on Mac.

> Video and Live Photo playback are already `#if`-gated and degrade to a still image — acceptable for v1. AppKit playback parity (`AVPlayerView`, `PHLivePhotoView` on macOS) is optional later work.

---

## Phase 3 — Mac-native review UX polish *(~1–2 days)*

The touch-tuned swipe loop feels broken with a mouse and gives no haptics on Mac.

- [ ] Add keyboard shortcuts via `.keyboardShortcut` / `.onKeyPress`: ← or Delete = delete, → or Return = keep, Cmd-Z = undo, Space = preview.
- [ ] Make the decision-bar buttons the primary interaction; keep the `DragGesture` swipe for trackpad users.
- [ ] Optional: `NSHapticFeedbackManager` for trackpad feedback (haptics already no-op on macOS).

**Payoff:** feels like a Mac app, not a stretched phone app.

> **Milestone candidate:** Phases 0–3 are a shippable "SnipSnaps for Mac — Photos" release on their own.

---

## Phase 4 — Net-new Files cleanup surface *(the harder half, ~8–15 days)*

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

| Scope | Effort |
|---|---|
| Phases 0–3: Photos on macOS | ~1.5–2.5 weeks |
| Phase 4: Files surface | ~2–3 weeks |
| **Both, shipped well** | **~4–6 weeks** |

Suggested sequencing: ship **Phases 0–3 as "SnipSnaps for Mac (Photos)"** first, then follow with the Files surface as a feature update.

---

## Top risks / gotchas

1. **Similar mode silently empty on Mac** until the Phase 2 CGImage refactor — don't ship the Mac build with it visible-but-broken; port it or hide it.
2. **Empty entitlements file today** — with the sandbox on, missing `photos-library` / file entitlements = silent runtime denial, not a build error.
3. **Grant folders, not individual files** — a single-file sandbox extension doesn't grant write to the parent dir, and trash is a *move* out of it, so trashing a lone picked file fails with `NSFileWriteNoPermissionError`.
4. **No full-disk auto-scan on the App Store** — no Desktop/Documents entitlement exists (only Downloads), so the user grants each folder. Set product expectations: this is a per-folder model by design.
5. **Destructive safety on files > Photos** — Photos has Recently Deleted (30-day); files must use `trashItem` (recoverable), exclude bundles/symlinks/dotfiles/`.icloud` placeholders.
6. **Security-scoped bookmark hygiene** — persist them or the user re-picks every launch; handle `bookmarkDataIsStale`; balance every `start`/`stop` with `defer`.
7. **iCloud "Desktop & Documents Folders"** — enumerating/hashing dataless placeholders can pull gigabytes; detect `NSURLUbiquitousItemIsDownloadedKey` and skip/warn.
8. **Touch-tuned swipe UX** feels wrong with a mouse — Phase 3 keyboard shortcuts + button-first interaction are not optional polish, they're required for a usable desktop loop.
9. **App Store privacy labels (2026 rules)** — disclose local data handling accurately.
10. **macOS `Form` default style crashes at launch** *(found + fixed in Phase 1)* — SwiftUI's default columnar `Form` style on macOS can trip an AppKit "Update Constraints in Window pass" cycle (`NSGenericException`/SIGABRT) once a form has enough rows. `TabView` eagerly lays out all tabs on macOS, so a crash in any tab aborts the whole app at launch. Fix: `.formStyle(.grouped)` (no-op on iOS, where grouped is already the default). Watch for the same cycle in any future macOS `Form`/`List`-heavy screens (e.g. the Files-folder settings).

---

## Verification notes

The macOS platform facts above were web-verified against current Apple docs (entitlement key reference, "Requesting Changes to the Photo Library," App Review Guideline 2.4.5(i)) and four adversarial checks (sandbox file delete, PhotoKit delete UX, App Review approval, target choice) — all returned *confirmed-with-conditions*; the conditions are folded into the phases and risks above.
