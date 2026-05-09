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

## Deterministic iOS Capture Harness

For SwiftUI apps, use a DEBUG-only environment switch in the root view:

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

Then create `ScreenshotDemoView` with deterministic states such as:

- `home`
- `review`
- `similar`
- `details`
- `summary`
- `settings`

Keep this code behind `#if DEBUG` so release builds are not affected.

## Simulator Capture Commands

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
