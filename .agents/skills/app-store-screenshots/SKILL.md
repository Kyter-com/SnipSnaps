---
name: app-store-screenshots
description: Use when generating Apple App Store screenshots for iPhone and iPad apps, especially when the workflow should use real iOS simulator captures embedded in polished marketing layouts. Triggers on app store screenshots, iOS screenshots, iPad screenshots, simulator screenshots, marketing screenshots, screenshot generator.
---

# Apple App Store Screenshots

## Purpose

Create App Store-ready iPhone and iPad screenshots that combine real app-rendered simulator captures with polished marketing layouts.

This skill is Apple-only. Do not include Google Play, Android, feature graphic, or Play Store guidance unless the user explicitly asks for a separate Android workflow.

## Core Rules

- Prefer real simulator captures over hand-drawn UI mockups.
- Treat screenshots as marketing assets: one clear idea per slide, short copy, readable at App Store thumbnail size.
- Keep export dimensions exactly App Store-compatible.
- Keep copy/layout stable across screenshots. Reserve fixed text regions and fixed button-label widths so repeated slides do not visually shift.
- Use deterministic demo states when live app data, Photos permission, or manual tapping would make captures unreliable.
- Avoid third-party downloaded photos unless licensing is explicit. Prefer public-domain/stock assets with clear license, user-provided assets, or generated in-app demo imagery.
- Pull the marketing palette from the actual app icon, not from a generic template. A warm-cream/pink layout around a deep-blue icon reads as off-brand even when individually polished. Sample 3–4 colors from the icon (dark frame, mid body, accent highlight) and use them for background, chrome, and accents.

## Brand Cohesion

Marketing screenshots should feel like an extension of the icon, not a separate template. Before composing a layout:

- Inspect the icon: dominant background, accent color, glyph style (geometric, gradient, dimensional, soft).
- Mirror that mood in the composite background, not just a small icon thumbnail in the corner. If the icon is dark and atmospheric, the screenshot background should be dark and atmospheric. If the icon has a sparkle, gradient, or motif, repeat that as a subtle background flourish so the slides feel cohesive.
- Replace generic "blob" or "pastel circle" backgrounds with brand-derived elements (radial glow in the icon's hero color, motif particles, gradient).

## Liquid Glass Treatment

For modern iOS marketing (iOS 17+ and the iOS 26 Liquid Glass language), prefer translucent layered chrome over flat colored shapes:

- Headline kicker: a translucent "glass" pill with a hairline highlight border and faint top sheen, instead of plain accent-color text.
- Brand chip / app name: a glass pill containing the icon plus app name + tagline.
- Feature callouts: small glass chips with a colored status dot.
- Device frame: pair a soft colored glow (in the brand accent) with a separate dark drop shadow for depth on dark backgrounds.
- Implementation in Pillow: a glass panel is a rounded rect with `(255,255,255,~28)` fill, a top-half sheen at `(255,255,255,~22)`, and a 2px outer border at `(255,255,255,~110)` plus a 1px inner border at lower alpha.

## Target Outputs

Default Apple portrait exports:

- iPhone 6.9": `1290 x 2796`
- iPad 13": `2064 x 2752`

Recommended repo layout:

```text
marketing/app-store-screenshots/
├── README.md
├── generate.py
├── raw/
│   ├── iphone-6.9/
│   │   ├── 01-home.png
│   │   └── ...
│   └── ipad-13/
│       ├── 01-home.png
│       └── ...
└── output/
    ├── iphone-6.9/
    │   ├── 01-home.png
    │   └── ...
    └── ipad-13/
        ├── 01-home.png
        └── ...
```

## First Pass Questions

Ask only for missing information that cannot be inferred from the repo:

- Which App Store devices are needed: iPhone, iPad, or both?
- Which screens/features should each slide sell?
- Should captures use real app data, deterministic demo data, or supplied screenshot PNGs?
- Is the app universal for iPad? If iPad screenshots are needed, verify native iPad support instead of relying on iPhone compatibility mode.
- Are there brand constraints beyond the app’s current icon, accent color, and visual style?

If the repo already contains a generator or strong design direction, continue from it instead of scaffolding a new project.

## Recommended Workflow

1. Inspect existing app UI, icons, colors, and any screenshot generator.
2. Define a slide list with one idea per slide.
3. Add DEBUG-only deterministic screenshot routes/screens if needed.
4. Build and install the app on iPhone and iPad simulators.
5. Capture raw simulator screenshots into `raw/<device>/`.
6. Generate final marketing composites into `output/<device>/`.
7. Validate exact dimensions and visually inspect at least one iPhone and one iPad output.
8. Commit raw captures, outputs, generator changes, and any DEBUG-only screenshot harness.

## Capture Harness

There are two viable patterns. Prefer the second one — it captures the *real* production views, which is what reviewers and store visitors see.

### Pattern A — DEBUG-only mocked demo views (fallback / quick start)

For SwiftUI apps where Photos permission, real PhotoKit assets, or live data make captures unreliable, fall back to a DEBUG environment switch in the root view:

```swift
#if DEBUG
if let screenshotScreen = ProcessInfo.processInfo.environment["APP_SCREENSHOT_SCREEN"] {
  ScreenshotDemoView(screen: screenshotScreen)
} else {
  appRootView
}
#else
appRootView
#endif
```

Keep the `ScreenshotDemoView` strictly hand-rolled marketing copy of the real screens. This is fast to build but can drift from production UI — bugs like duplicate labels, missing accessibility, or stale layouts will only show up in marketing, not in the real app.

### Pattern B — XCUITest driving the real app (preferred)

Capture the actual production views with real data so the marketing layout shows what users will see. This requires three pieces:

1. **Seeded data**: bundle a curated set of source photos (e.g. 25–40 free stock images), refresh their EXIF dates to *now* before import, and load them with `simctl addmedia` so date-filtered modes show populated counts.
2. **Permissions via the in-test dialog walker** (NOT a pre-grant on modern iOS): on iOS 26.4 `simctl privacy grant` and direct TCC.db writes do not stick, so reset to *not-determined* (`simctl privacy reset all <bundle>`) and let the app prompt. The app often auto-requests on launch, so the SpringBoard alert races the test — poll for ~15s, tapping the app's enable affordance if present and `XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]` the moment the alert appears. A single-shot `waitForExistence` loses the race and the app lands denied.
3. **An XCUITest** in the UI-tests target that drives the app screen by screen and calls `XCUIScreen.main.screenshot()` wrapped in `XCTAttachment(name: "01-home")` with `.keepAlways` lifetime. Run via `xcodebuild test -resultBundlePath out.xcresult`, then extract attachments via `xcrun xcresulttool export attachments`.

This pattern in SnipSnaps lives in:

- `marketing/app-store-screenshots/capture.sh` — orchestrates one device end-to-end.
- `marketing/app-store-screenshots/refresh-seed-dates.py` — rewrites EXIF dates on seed photos.
- `marketing/app-store-screenshots/extract-shots.py` — pulls named PNGs from an xcresult.
- `SnipSnapsUITests/ScreenshotCaptureTests.swift` — the actual UI test.

### Critical gotchas this pattern solves

- **`simctl addmedia` does NOT set the photo's creation date to "now"** when the source file has no EXIF date. Photos imported that way fall outside the app's `creationDate >= startOfDay(today)` predicate, so `Today` and `On This Day` modes silently report 0. Stamp the seed files via piexif/exiftool before each capture run.
- **On iOS 26.4 the TCC pre-grant is dead — rely on the in-test dialog walker instead.** Older guides (and earlier iOS 26 builds) let you pre-grant Photos by writing `auth_value = 4` into `.../data/Library/TCC/TCC.db` and/or calling `simctl privacy grant photos`. On 26.4 both fail: `simctl privacy grant photos` lands as `auth_value = 2`, which the modern Photos stack treats as *denied*, and a direct `auth_value = 4` write does land on disk but `tccd` keeps serving its cached value (verified by querying the DB — it reads 4 while the app still sees denied). Either way the permission ends up *determined*, which suppresses the system prompt and leaves the app on its "Photo access denied" screen (the UI test then taps "Open Settings" and captures the Settings app). **Fix: `simctl privacy reset all <bundle>` to leave Photos *not-determined*, and do NOT pre-grant.** On launch the app shows its own "Enable Photo Access" affordance; the UI test taps it and walks the system dialog, which grants access through `tccd` correctly.
- **The in-test permission-dialog walker is the primary path, and it must be race-robust.** The app can auto-request Photos access on launch, so the SpringBoard alert may appear *before or instead of* your own tap on the app's enable button — a single `if enableButton.waitForExistence(timeout: 2) { … }` gate loses that race and the app ends up denied. Instead poll for ~15s: each tick, tap `springboard.buttons["Allow Full Access"]` if it exists (fall back to a label containing "Full Access" / starting with "Allow"), otherwise tap the app's enable button if present. On iOS 26.4 the alert order is `Limit Access… / Allow Full Access / Don't Allow`. Run once per (not-determined) simulator; subsequent runs see the grant.
- **The test runner can intermittently fail to launch** with `Application failed preflight checks` / `Busy` — usually stale simulator state (e.g. a sim left booted, or many rapid boots). `xcrun simctl shutdown all` before the run, and `xcrun simctl erase <device>` if a specific sim keeps failing, clears it.
- **PhotoKit's `.fastFormat` delivery mode returns placeholders, not real renders,** for very small `targetSize` requests (e.g., 18×16 for dHash). Two PHAssets with byte-identical content can come back with different placeholder pixels and therefore different hashes. If your similar-photo algorithm relies on stable hashes, request `.highQualityFormat` instead — slower per asset but deterministic across runs.
- **A "similar/duplicate photos" screen coming up empty in the simulator is usually a `PHFetchOptions` NULL-predicate bug, not broken on-device ML — check the predicate before blaming Vision.** `simctl addmedia` imports photos with a **NULL `mediaSubtype`** column (no camera metadata). A fetch predicate like `(mediaSubtype & <screenshot>) == 0` (the natural way to *exclude* screenshots) then drops **every** asset, because in the Photos store `NULL & N == 0` evaluates to NULL, not true — so the scan fetches 0 assets and returns instantly. This looks identical to "the near-duplicate detector no-ops in the sim," which is what fooled us: Vision `VNGenerateImageFeaturePrintRequest` actually works fine in the iOS 26.4 sim on direct CGImages (verified by unit test), and even where it returns nil on PhotoKit thumbnails, a dHash fallback still groups near-dups. The fix is to make the exclusion predicate NULL-safe: `NOT ((mediaSubtype & N) == N)` keeps NULL-subtype assets while still excluding real screenshots (and fixes imported/synced photos being silently skipped for real users too). To diagnose an empty on-device-ML screen in the sim: log the fetch's `result.count`, an unfiltered `PHAsset.fetchAssets` count, and the authorization status — if unfiltered > 0 but the predicated fetch is 0, it's the predicate, not the algorithm.
- **The marketing letterbox-fill color must come from the screenshot itself.** Don't hardcode a "neutral" off-white (`(246, 244, 239)` cream is a common default and is wrong for iOS 26 light mode). Sample the top-left pixel of the captured raw screenshot and use that as the canvas background in `fit_image()` — the iOS status-bar area then blends seamlessly into the device frame.
- **Use semantic XCUI queries**, not pixel coordinates. `app.staticTexts["Today"]`, `app.buttons["Close review"]`, `app.tabBars.buttons["Settings"]`, etc. Coordinates break the moment Liquid Glass or Dynamic Type shifts a layout. **Idiom caveat:** a SwiftUI `TabView` renders as a bottom tab bar on iPhone (exposed under `app.tabBars`) but as a floating *top* tab bar on iPad that is **not** under `tabBars` — so `app.tabBars.buttons["Settings"]` times out on iPad and the tap is silently skipped, capturing the previous tab. Fall back to a plain `app.buttons["<tab>"]` query and confirm you landed by waiting on the destination's nav bar (`app.navigationBars["Settings"]`).
- **Attach screenshots with stable names** (`01-home`, `02-review`, …) so the host extractor can rename the GUID-named exports back to predictable filenames.
- **No host-level mouse automation is required.** XCUITest runs inside Xcode's test infrastructure and does not need Accessibility/Screen-Recording permissions — unlike `cliclick`, AppleScript clicks, or `idb`, all of which silently fail when those grants aren't in place.
- **For sheet-over-photo captures, pre-position the underlying state.** iOS 26 sheets render with translucent material that refracts whatever's behind them. If the photo behind has high-contrast vertical lines (bridge cables, text, etc.), they show through as distracting smears. Either advance the app to a flat-color photo first or expand the sheet to its largest detent before capturing.
- **Bake the marketing status bar in natively — don't redraw it in post.** `xcrun simctl status_bar <device> override --time "9:41" --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState discharging --batteryLevel 100` works on iOS 26.4 and gives a real Apple status bar (correct SF font, real signal bars) in every capture. It's far cleaner than compositing-time retiming/redrawing. Set it after boot (`simctl bootstatus … -b`); it persists through the `xcodebuild test` run. If a capture still shows the live clock or the simulator's gray cellular dots, the override didn't apply — usually a stale/reused sim; `erase` and re-run.
- **Match the device-frame's screen aspect to the real capture, or the chrome misaligns.** Figma/SVG device mockups often have a screen opening a few percent wider than the real screenshot (iPhone 16: ~0.477 vs the true 0.460 of a 1320×2868 capture). A cover-crop then shaves the top/bottom, shoving the status bar off the Dynamic Island and clipping the tab bar. Fix by stretching the *frame* vertically (~3.7%) so its glass matches the capture aspect and the shot maps 1:1 — stretching the frame is imperceptible on rounded corners, whereas squishing the app content is visible.
- **Don't let a noisy `xcodebuild test` exit abort the capture script before extraction.** `xcodebuild` runs UI tests on simulator *clones* and retries transient `Busy` / `Application failed preflight checks` launch failures on a fresh clone — so it can print `** TEST FAILED **` for a dead clone, pass on the retry, and still exit non-zero. Under `set -euo pipefail` that kills the orchestration script before it extracts the attachments. Wrap the `xcodebuild` line in `set +o pipefail … set -o pipefail` (or `|| true`) and treat the extracted-attachment count as the real success signal.
- **Re-verify navigation labels after any app-UI change; they drift.** Semantic queries only help if the label still exists. Real drift that broke this run: a review summary dismissed by a top-left X labelled `Close without deleting` (the bottom `Done` only appears when nothing is marked), and a card ("Similar") that moved into a lower home section and needed a `swipeUp` to reach. Also mind capture *ordering*: features that "remember reviewed" items must be captured before the flow that reviews them, or they show an empty state.

### Reusing this on a new screen / state / app

- New screen: add a `capture("0N-name")` waypoint in the UI test, then add a matching slide entry to the generator's `SLIDES` list.
- New state (e.g. error banner): drive the app into that state from the test (mark photos, simulate failures via env vars, etc.) before calling `capture`.
- New device: pass its simulator UUID to `capture.sh` and a matching entry in `DEVICES` in `generate.py`.
- New app: copy the four scripts and the `ScreenshotCaptureTests.swift` template; replace the bundle id, view labels, and palette constants.

## Simulator Capture Commands

For modern iOS marketing, prefer an iOS 26+ simulator runtime so the captured system chrome (nav bars, tab bars, controls) renders with Liquid Glass material. iOS 18 and earlier render as flat material and look dated alongside the marketing layout's glass chrome.

```bash
xcrun simctl list runtimes        # confirm an iOS 26 runtime is installed
xcrun simctl create "iPhone 16 Pro Max - iOS 26" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-26-4
```

List available simulators:

```bash
xcrun simctl list devices available
```

Build for a specific simulator:

```bash
xcodebuild -project App.xcodeproj -scheme App -destination 'id=<DEVICE_ID>' -derivedDataPath /private/tmp/AppScreenshots build
```

Install:

```bash
xcrun simctl install <DEVICE_ID> /private/tmp/AppScreenshots/Build/Products/Debug-iphonesimulator/App.app
```

Capture each deterministic screen:

```bash
ROOT=/absolute/path/to/repo
screens=(home review similar details summary settings)
names=(01-home 02-review 03-similar 04-details 05-summary 06-settings)
for i in {1..6}; do
  screen=$screens[$i]
  name=$names[$i]
  xcrun simctl terminate <DEVICE_ID> com.example.App >/dev/null 2>&1 || true
  SIMCTL_CHILD_APP_SCREENSHOT_SCREEN=$screen xcrun simctl launch <DEVICE_ID> com.example.App >/dev/null
  sleep 1.2
  xcrun simctl io <DEVICE_ID> screenshot "$ROOT/marketing/app-store-screenshots/raw/<device>/$name.png" >/dev/null
done
```

Use absolute screenshot output paths with `simctl io screenshot`; relative paths can fail or write somewhere unexpected.

## iPad Support Check

If iPad screenshots are requested, verify the app is not running in iPhone compatibility mode.

For Xcode projects, inspect `TARGETED_DEVICE_FAMILY`:

```text
TARGETED_DEVICE_FAMILY = "1,2";
```

`1` means iPhone only. `"1,2"` means iPhone + iPad. If the app is iPhone-only, iPad simulator captures will be letterboxed and are not suitable as native iPad App Store screenshots.

Only change the device family when it is appropriate for the product; enabling iPad support is a real app-distribution change.

## Generator Guidance

A simple repo-native generator is acceptable. Next.js is not required if Python/Pillow or another existing tool already fits the project.

Generator expectations:

- Read raw captures from `raw/<device>/<slide>.png`.
- Embed raw captures in a device frame or direct layout.
- Fall back to drawn placeholder UI only when a raw capture is missing.
- Reserve fixed-height headline and subtitle blocks so text does not shift between slides.
- Use consistent icon placement, typography, background shapes, and frame positions.
- Validate output dimensions programmatically.

## Per-Device Layout Budgeting

iPhone and iPad canvases have different aspect ratios; do not just multiply iPhone coordinates by a single `scale = canvas_w / phone_w` factor for the iPad branch and call it done. The iPad canvas (e.g. 2064x2752, ratio ~0.75) is much *less* tall than that calculation implies, so device frames overflow off-canvas.

Budget the iPad canvas explicitly in absolute pixels:

- Top brand pill ends at ~y=370.
- Headline + subtitle block: y ≈ 420 → 950.
- Optional feature chip row: y ≈ 1000 → 1080.
- Device frame: y ≈ 1100 → 2700, height ≈ 1600, width ≈ height × 0.75 (iPad portrait aspect).
- Bottom margin: ≥ 50px.

Verify the frame's bottom edge `fy + frame_h` is inside the canvas before rendering.

For iPhone (1290x2796), the frame can take the bottom 50–55% of the canvas and the headline block sits above it.

Python/Pillow dimension check:

```bash
python3 - <<'PY'
from PIL import Image
from pathlib import Path
expected = {'iphone-6.9': (1290, 2796), 'ipad-13': (2064, 2752)}
for path in sorted(Path('marketing/app-store-screenshots/output').glob('*/*.png')):
    size = Image.open(path).size
    assert size == expected[path.parent.name], f'{path}: {size}'
    print(path, size)
PY
```

## Copy Guidelines

- Keep headlines short, concrete, and benefit-led.
- Avoid feature-list headlines.
- Prefer plain words over jargon.
- Use consistent line-count reservations in the layout, even when a headline is shorter.
- If a slide uses the same image layout as another slide, keep the text block origin, max width, line height, and reserved height identical.

Good examples:

- `Swipe fast. Keep the best.`
- `Find duplicate-looking shots.`
- `Know what each photo costs.`
- `Clean up with confidence.`

## UI Capture Quality Notes

- Hide unrelated chrome when it distracts from the screenshot, but keep enough UI to prove it is the real app.
- Use DEBUG demo data for stable dates, counts, progress, and similar-photo groups.
- For dynamic labels that change count, use fixed-width count badges or reserved text widths to prevent layout shift.
- Add haptics, animations, or interaction polish in production UI only when it improves the real app; screenshot-only code should stay DEBUG-only.
- Re-capture raw simulator screenshots after any UI change that appears in the marketing output.

## Verification Checklist

- Raw iPhone captures exist and match expected simulator resolution.
- Raw iPad captures are native iPad, not iPhone compatibility-mode letterboxed.
- Final output dimensions match App Store sizes.
- Text blocks do not shift between slides with the same layout.
- Dynamic button labels do not shift when counts change.
- Generator runs from a clean checkout with documented commands.
- Release app behavior is not affected by DEBUG-only screenshot routes.
