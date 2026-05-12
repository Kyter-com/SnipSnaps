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
2. **Pre-granted permissions**: write directly to the sim's TCC.db AND call `simctl privacy grant <service> <bundle>`. Keep an in-test fallback that walks any system permission dialog via `XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]`.
3. **An XCUITest** in the UI-tests target that drives the app screen by screen and calls `XCUIScreen.main.screenshot()` wrapped in `XCTAttachment(name: "01-home")` with `.keepAlways` lifetime. Run via `xcodebuild test -resultBundlePath out.xcresult`, then extract attachments via `xcrun xcresulttool export attachments`.

This pattern in SnipSnaps lives in:

- `marketing/app-store-screenshots/capture.sh` — orchestrates one device end-to-end.
- `marketing/app-store-screenshots/refresh-seed-dates.py` — rewrites EXIF dates on seed photos.
- `marketing/app-store-screenshots/extract-shots.py` — pulls named PNGs from an xcresult.
- `SnipSnapsUITests/ScreenshotCaptureTests.swift` — the actual UI test.

### Critical gotchas this pattern solves

- **`simctl addmedia` does NOT set the photo's creation date to "now"** when the source file has no EXIF date. Photos imported that way fall outside the app's `creationDate >= startOfDay(today)` predicate, so `Today` and `On This Day` modes silently report 0. Stamp the seed files via piexif/exiftool before each capture run.
- **iOS 26 TCC.db needs `auth_value = 4` for full Photos access.** The legacy `auth_value = 2` ("allowed") that older guides reference is interpreted as *denied* by the modern Photos permission system, leaving the app stuck on a "Photo access denied" banner. Insert: `INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServicePhotos', '<bundle>', 0, 4, 4, 1);` into `~/Library/Developer/CoreSimulator/Devices/<UUID>/data/Library/TCC/TCC.db`. Also call `simctl privacy grant photos <bundle>` for belt-and-suspenders.
- **`simctl privacy reset all <bundle>` before each capture run.** Stale TCC rows from prior runs (especially ones written with the wrong auth_value) survive `simctl addmedia` and the test, leaving the app in `.denied`.
- **Always keep an in-test permission-dialog walker** so the run still succeeds on a freshly-erased device where the TCC hack hasn't been seeded yet. Query `XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]` then fall back to any button whose label starts with "Allow".
- **PhotoKit's `.fastFormat` delivery mode returns placeholders, not real renders,** for very small `targetSize` requests (e.g., 18×16 for dHash). Two PHAssets with byte-identical content can come back with different placeholder pixels and therefore different hashes. If your similar-photo algorithm relies on stable hashes, request `.highQualityFormat` instead — slower per asset but deterministic across runs.
- **The marketing letterbox-fill color must come from the screenshot itself.** Don't hardcode a "neutral" off-white (`(246, 244, 239)` cream is a common default and is wrong for iOS 26 light mode). Sample the top-left pixel of the captured raw screenshot and use that as the canvas background in `fit_image()` — the iOS status-bar area then blends seamlessly into the device frame.
- **Use semantic XCUI queries**, not pixel coordinates. `app.staticTexts["Today"]`, `app.buttons["Close review"]`, `app.tabBars.buttons["Settings"]`, etc. Coordinates break the moment Liquid Glass or Dynamic Type shifts a layout.
- **Attach screenshots with stable names** (`01-home`, `02-review`, …) so the host extractor can rename the GUID-named exports back to predictable filenames.
- **No host-level mouse automation is required.** XCUITest runs inside Xcode's test infrastructure and does not need Accessibility/Screen-Recording permissions — unlike `cliclick`, AppleScript clicks, or `idb`, all of which silently fail when those grants aren't in place.
- **For sheet-over-photo captures, pre-position the underlying state.** iOS 26 sheets render with translucent material that refracts whatever's behind them. If the photo behind has high-contrast vertical lines (bridge cables, text, etc.), they show through as distracting smears. Either advance the app to a flat-color photo first or expand the sheet to its largest detent before capturing.

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
