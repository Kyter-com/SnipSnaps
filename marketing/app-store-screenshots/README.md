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
├── seed-photos/            # 42 jpgs (Picsum/Unsplash + JPEG-quality variants)
├── raw/<device>/           # per-device 01-home..06-settings.png
├── output/<device>/        # composited App Store PNGs
└── .capture-runs/          # xcresult bundles from the last test runs (gitignored)
```

## Visual style

The marketing layout pulls its palette from `Frame 11.png` in `AppIcon.appiconset`:

- Deep midnight gradient background with two diagonal radial glows in the icon's electric blue.
- Floating ice-blue sparkles echoing the icon's central 4-point glyph.
- Liquid-glass chrome: translucent rounded pills/chips with a top sheen and hairline highlight border.
- Brand icon + tagline rendered directly on the navy at top-left.
- Per-slide kicker uses a glass pill with an accent dot.
- Device frame is rendered with a colored brand glow plus a separate dark drop shadow for depth.

If the app icon changes, resample its primary colors and update the `DEEP / MID / GLOW / ACCENT / ICE` constants at the top of `generate.py`.

## Adding more screens

1. Add a `case` to the demo seed flow inside `ScreenshotCaptureTests.swift` — navigate to the new screen via accessibility queries, then call `capture("07-newscreen")`.
2. Append an entry to `SLIDES` in `generate.py` with `kicker`, `title`, `subtitle`, `screen` (where `screen` matches the capture filename suffix).
3. Re-run `capture.sh` for each device.

## Gotchas worth remembering

If captures look wrong after a re-run, the cause is almost always one of these:

- **Today / On This Day show 0** — the EXIF dates on `seed-photos/*.jpg` weren't refreshed before `simctl addmedia`. Run `refresh-seed-dates.py` again or just rerun `capture.sh`, which does it for you.
- **"Photo access denied" on the home screen** — the TCC.db has a stale row with `auth_value = 2`. iOS 26 needs `auth_value = 4` for full Photos access. `capture.sh` resets and rewrites this on each run.
- **`No Similar Photos Found`** — `Photos.swift` is using `PHImageRequestOptionsDeliveryMode.fastFormat` for dHash thumbnails. That mode returns inconsistent placeholders at the 18 × 16 target size, breaking hash equality. Switch to `.highQualityFormat` (already done in this repo as of the May 11 capture run).
- **Cream / yellow band at the top of the device frame** — `fit_image()` in `generate.py` was hardcoding `(246, 244, 239)` as the letterbox fill. It now samples the top-left pixel of the raw screenshot so the band blends into the real iOS status-bar background.
- **Diagonal smear / refraction across the details sheet** — iOS 26 Liquid Glass is refracting the photo behind. Either advance past high-contrast photos before opening details (the test does this with two `Keep photo` taps) or expand the sheet to `.large` so the photo is fully covered.
