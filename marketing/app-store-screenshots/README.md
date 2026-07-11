# SnipSnaps App Store Screenshots

Lightweight generator + automation for App Store-ready iPhone and iPad marketing screenshots, built on real captures from the iOS 26 simulator driven by an XCUITest.

## Outputs

- `output/iphone-6.9/*.png` — 1290 × 2796 (App Store iPhone 6.9")
- `output/ipad-13/*.png` — 2064 × 2752 (App Store iPad 13")

## One-shot regenerate

If `raw/` already has captures (e.g. you only touched the marketing layout), just recomposite:

```bash
python3 marketing/app-store-screenshots/generate.py
```

## Full reproduce (real captures end-to-end)

Captures the actual production `HomeView` / `ReviewSessionView` / `SettingsView` from a clean simulator state.

```bash
# iPhone 17 Pro Max @ iOS 26.4
marketing/app-store-screenshots/capture.sh \
  3102152A-571A-49D2-B7A4-5F7C05CFB7BF \
  marketing/app-store-screenshots/raw/iphone-6.9

# iPad Pro 13" (M5) @ iOS 26.4
marketing/app-store-screenshots/capture.sh \
  3C4DDFAD-C938-472A-AAF8-8133E2C1823A \
  marketing/app-store-screenshots/raw/ipad-13

# Composite the marketing layouts
python3 marketing/app-store-screenshots/generate.py
```

`capture.sh` for each device:

1. Refreshes EXIF timestamps on seed photos so they import as "today" (otherwise `Today` / `On This Day` modes show 0), and stamps EXIF GPS on a few seeds (`seed-locations.py`) so the photo-details **Location** map renders.
2. Shuts the sim down, wipes `Media/DCIM` + `Media/PhotoData` for a clean slate.
3. Sets `simctl status_bar override` (9:41, full battery/Wi-Fi/signal) so the captures carry a clean marketing status bar natively, then resets Photos to *not-determined* (`simctl privacy reset all`). The pre-grant is dead on iOS 26.4, so the app is left to prompt and the UI test grants access by walking the system dialog.
4. Re-adds the 42 seed photos via `simctl addmedia`.
5. Runs `SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens` against the device — which launches the real app, grants Photos access via the system dialog, taps through every marketing screen, and attaches a named PNG of each one via `XCUIScreen.main.screenshot()`.
6. Extracts the named attachments from the `.xcresult` bundle into `raw/<device>/01-home.png` … `06-settings.png`.

Granting Photos access by walking the system dialog (`Allow Full Access`) is the primary path on iOS 26.4, not a fallback — see the gotchas below.

## File layout

```
marketing/app-store-screenshots/
├── capture.sh              # orchestrates one device end-to-end
├── extract-shots.py        # pulls named PNGs out of an xcresult bundle
├── refresh-seed-dates.py   # rewrites EXIF dates on seed photos to "now"
├── seed-locations.py       # stamps EXIF GPS on select seeds (details Location map)
├── generate.py             # composites raw captures into marketing PNGs
├── backgrounds/            # aurora-teal.jpg — the composite backdrop
├── frames/                 # iphone-16.svg source + pre-rasterized iphone-16.png
├── seed-photos/            # 42 jpgs (Picsum/Unsplash + JPEG-quality variants)
├── raw/<device>/           # per-device 01-home..06-settings.png
├── output/<device>/        # composited App Store PNGs
└── .capture-runs/          # xcresult bundles from the last test runs (gitignored)
```

## Visual style

- **Background** — the `backgrounds/aurora-teal.jpg` gradient, reoriented to fill
  the portrait canvas. The `BG` dict at the top of `generate.py` controls the crop
  (`rot` / `zoom` / `anchor`) plus a legibility scrim that darkens the top behind
  the white headline. Current crop is `rot 180°`.
- **Device frame** — the real iPhone 16 mockup. `frames/iphone-16.svg` is the
  source (a slimmed Figma export with the placeholder wallpaper stripped out);
  it's pre-rasterized to `frames/iphone-16.png` (2000px wide, transparent) so
  `generate.py` stays PIL-only. The SVG's glass opening is ~0.477 aspect but a
  real 6.9" capture is 0.460, so `iphone_frame()` stretches the frame vertically
  (~3.7%, to `SCREEN_ASPECT`) before compositing. The capture then maps 1:1 into
  the glass — no crop — so content reaches the bezel, the status bar sits
  centered on the Dynamic Island, and the tab bar survives. The Dynamic Island
  is redrawn on top and a device-shaped drop shadow grounds it.
- **iPad** uses a simple drawn frame — no iPad mockup has been supplied.
- **No app logo/tagline** — the headline leads.
- **Status bar** is baked in natively at capture time. `capture.sh` runs
  `simctl status_bar override` (9:41, full battery, Wi-Fi, 4 signal bars) before
  the UI test, so the raw captures already carry a clean marketing status bar —
  no compositing-time retiming or redrawing (the old `retime_status_bar` path
  has been removed).

To re-rasterize the frame after editing the SVG (needs `librsvg`; only for
regenerating the asset, not for normal runs):

```bash
rsvg-convert -w 2000 -f png frames/iphone-16.svg -o frames/iphone-16.png
```

## Adding more screens

1. Add a `case` to the demo seed flow inside `ScreenshotCaptureTests.swift` — navigate to the new screen via accessibility queries, then call `capture("07-newscreen")`.
2. Append an entry to `SLIDES` in `generate.py` with `title` and `screen` (where `screen` matches the capture filename suffix).
3. Re-run `capture.sh` for each device.

## Gotchas worth remembering

If captures look wrong after a re-run, the cause is almost always one of these:

- **Today / On This Day show 0** — the EXIF dates on `seed-photos/*.jpg` weren't refreshed before `simctl addmedia`. Run `refresh-seed-dates.py` again or just rerun `capture.sh`, which does it for you.
- **"Photo access denied" on every screen — and shots that bounce into iOS Settings** — on iOS 26.4 the TCC pre-grant is dead. `simctl privacy grant photos` does NOT stick (verified: the app still shows the system prompt even on a freshly-`erase`d device), and a direct `auth_value = 4` write to `TCC.db` is ignored because `tccd` serves its cached value. So `capture.sh` resets Photos to *not-determined* (`simctl privacy reset all`) and the UI test grants access by walking the system dialog. **The walker must be robust:** the app auto-requests on launch, so the SpringBoard alert (`Limit Access… / Allow Full Access / Don't Allow`) can appear on its own and races the test's own "Enable Photo Access" tap. The test therefore polls for ~15s, tapping the app's enable button if present and `springboard.buttons["Allow Full Access"]` the moment the alert shows. A too-short, single-shot check loses the race and the app lands denied → the test taps "Open Settings" → you capture the Settings app.
- **`No Similar Photos Found` in the simulator — capture Similar on a real device.** The similar scan fingerprints each photo (18×16 *synchronous* PhotoKit thumbnail → dHash, plus a Vision feature print) and clusters near-duplicates. In the iOS 26.4 *simulator* it returns zero groups near-instantly (no scanning spinner) — verified with 4 byte-identical copies of one photo, which still didn't group. The fingerprinting path just doesn't work for `simctl addmedia`'d assets in the sim; the same build detects similars fine on a physical phone. So for a populated `03-similar` slide, run `capture.sh <connected-device-udid> …` against a real device, or fall back to the DEBUG `ScreenshotDemoView` Similar state. (Historical note: the scan once used `.fastFormat` thumbnails, which returned inconsistent placeholders at 18×16 and broke hash equality; it's `.highQualityFormat` now, but that doesn't rescue the simulator.) The UI test runs Similar *before* the Today review so real-device runs don't skip already-reviewed groups.
- **`04-details` shows no map, or a blank beige grid where the map should be** — two separate causes. (1) *No Location section at all*: the seed photo carries no GPS, so `PHAsset.location` is nil and `PhotoMetadataSheet` omits the whole Location section. `seed-locations.py` (run by `capture.sh`) stamps EXIF GPS on `alley`/`beach`/`boat`; `boat.jpg` is the one the details step lands on (3rd photo, newest-first, after two `Keep photo` taps). `refresh-seed-dates.py` preserves that GPS on every run. (2) *Blank grid*: MapKit tiles fetch over the network and paint an empty grid until they arrive, so the capture must wait several seconds after the sheet opens — `ScreenshotCaptureTests` sleeps 8s before `capture("04-details")`. The test also positions the sheet so the map is in frame, and this is idiom-specific: on **iPhone** the sheet opens at `.medium`, so the test drags its nav-bar chrome up to the `.large` detent (press-drag the chrome, not `swipeUp()` which just scrolls the Form) — this also fully covers the photo and avoids the Liquid Glass refraction smear; on **iPad** the sheet would otherwise be a small fixed-size form-sheet card that clips its content (the map falls below the fold), so `PhotoMetadataSheet` gives it `.presentationSizing(.page)` — a page-size sheet tall enough to show the whole list with no scroll (a no-op on iPhone's compact width, which uses the detents). That one line is the only app-source change for the screenshots; `.presentationSizing(.fitted)` was tried first and rejected (it collapses a scrollable `Form` to a stub), and a `.large` detent selection is simply ignored on regular-width iPad.
- **Status bar rides above the Dynamic Island / tab bar clipped** — the iPhone 16 SVG's screen glass (~0.477 aspect) is wider than a real 6.9" capture (~0.460). The old *centered cover* shaved ~52px off the top and bottom to fill it, which pushed the status bar above the Dynamic Island and trimmed the tab bar. `iphone_frame()` now stretches the *frame* vertically (~3.7%, to `SCREEN_ASPECT`) so the capture maps 1:1 — no crop, status bar centered on the Island, tab bar intact. Stretching the frame is imperceptible on the rounded corners; squishing the app content would be visible, so we stretch the frame, not the shot.
- **Status-bar time / weak signal** — baked in natively by `capture.sh`'s `simctl status_bar override` (9:41, full battery, Wi-Fi, 4 signal bars), which works on iOS 26.4. There is no compositing-time retiming any more. (The captures once *predated* the override being added to `capture.sh` and showed the sim's live clock + placeholder cellular dots; re-capturing fixed it. If you see a live clock or gray dots, the override didn't apply — usually a stale/reused sim; `erase` and re-run.)
- **Diagonal smear / refraction across the details sheet** — iOS 26 Liquid Glass is refracting the photo behind. Either advance past high-contrast photos before opening details (the test does this with two `Keep photo` taps) or expand the sheet to `.large` so the photo is fully covered.
- **`capture.sh` prints `** TEST FAILED **` but exits 0 with no new raws** — `xcodebuild` runs the UI test on simulator *clones* and retries a transient `Busy` / `Application failed preflight checks` launch on a fresh clone. It can print `** TEST FAILED **` for the dead clone yet pass on the retry (`Test Case … passed on 'Clone 1 …'`) and still exit non-zero. Under `set -euo pipefail` that non-zero aborted the script *before* the extract step, so `raw/` never updated. `capture.sh` now wraps the `xcodebuild` line in `set +o pipefail … set -o pipefail` so `extract-shots.py` always runs — the extract count is the real success check. If a clone keeps failing, `xcrun simctl erase <device>` clears it.
- **Navigation labels drift with the app UI — re-verify after UI changes.** Two that bit us: the review **summary** is dismissed by the top-left X labelled `Close without deleting` (the bottom `Done` button only appears when *nothing* is marked; with photos marked it's `Delete N`). And **"Similar"** moved into the "Space Savers" section near the *bottom* of the home list, so the test scrolls (`swipeUp`) to reach its button before tapping, then scrolls back to the top for the "Today" review.
