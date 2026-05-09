# SnipSnaps App Store Screenshots

This folder contains a lightweight generator for App Store-ready iPhone and iPad marketing screenshots.

Generated outputs:

- `output/iphone-6.9` - 1290 x 2796 PNGs
- `output/ipad-13` - 2064 x 2752 PNGs

Raw simulator captures:

- `raw/iphone-6.9` - iPhone simulator app screenshots
- `raw/ipad-13` - iPad simulator app screenshots

Run:

```bash
python3 marketing/app-store-screenshots/generate.py
```

The generator embeds raw simulator captures when present and falls back to drawn UI previews if a raw capture is missing. The DEBUG app supports deterministic capture screens with `SNIPSNAPS_SCREENSHOT_SCREEN` values: `home`, `review`, `similar`, `details`, `summary`, and `settings`.

The demo library artwork is generated in-app and has no external licensing dependency.
