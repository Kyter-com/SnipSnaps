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

1. Refreshes EXIF timestamps on seed photos so they import as "today" (otherwise `Today` / `On This Day` modes show 0).
2. Shuts the sim down, wipes `Media/DCIM` + `Media/PhotoData` for a clean slate.
3. Pre-grants Photos full access (TCC.db insert + `simctl privacy grant photos`).
4. Re-adds the 42 seed photos via `simctl addmedia`.
5. Runs `SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens` against the device — which launches the real app, taps through every marketing screen, and attaches a named PNG of each one via `XCUIScreen.main.screenshot()`.
6. Extracts the named attachments from the `.xcresult` bundle into `raw/<device>/01-home.png` … `06-settings.png`.

The UI test also walks the system Photos-permission dialog if the pre-grant ever fails on a fresh device.

## File layout

```
marketing/app-store-screenshots/
├── capture.sh              # orchestrates one device end-to-end
├── extract-shots.py        # pulls named PNGs out of an xcresult bundle
├── refresh-seed-dates.py   # rewrites EXIF dates on seed photos to "now"
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
  `generate.py` stays PIL-only. Screenshots fill the screen glass, the Dynamic
  Island is redrawn on top, and a device-shaped drop shadow grounds it.
- **iPad** uses a simple drawn frame — no iPad mockup has been supplied.
- **No app logo/tagline** — the headline leads.
- **Status-bar clock** is retimed to a marketing `9:41` at composite time
  (`retime_status_bar`), drawn in the system SF font.

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
- **"Photo access denied" on every screen — and shots that bounce into iOS Settings** — on iOS 26.4 the old TCC pre-grant no longer works. `simctl privacy grant photos` lands as `auth_value = 2` (the modern Photos stack reads it as denied) and a direct `auth_value = 4` write to `TCC.db` is ignored because `tccd` keeps serving its cached value. Either way the permission ends up *determined*, which suppresses the system prompt and strands the app on its "Photo access denied" screen — the UI test then taps "Open Settings" and captures the Settings app. `capture.sh` now just resets Photos to *not-determined* and relies on the test's "Allow Full Access" dialog walker, which grants full access through `tccd` correctly.
- **`No Similar Photos Found`** — `Photos.swift` is using `PHImageRequestOptionsDeliveryMode.fastFormat` for dHash thumbnails. That mode returns inconsistent placeholders at the 18 × 16 target size, breaking hash equality. Switch to `.highQualityFormat` (already done in this repo as of the May 11 capture run).
- **Screenshot doesn't reach the bezel, or the tab bar is clipped** — the iPhone 16 SVG's screen glass (~0.477 aspect) is slightly wider than the real screen (~0.461). Filling by width clips the tab bar off the bottom; filling by height leaves black side-bands. `iphone_frame()` uses a *centered cover*, so it fills to the bezel while cropping only ~46px symmetrically — the status bar and tab bar both survive.
- **Status-bar time / weak signal** — shots are retimed to `9:41` in `generate.py` (`retime_status_bar`), drawn in the system SF font, rather than depending on a clean capture. `capture.sh` also sets `simctl status_bar override` (9:41, full battery/signal), so once a capture succeeds it bakes the clean status bar in natively.
- **Diagonal smear / refraction across the details sheet** — iOS 26 Liquid Glass is refracting the photo behind. Either advance past high-contrast photos before opening details (the test does this with two `Keep photo` taps) or expand the sheet to `.large` so the photo is fully covered.
