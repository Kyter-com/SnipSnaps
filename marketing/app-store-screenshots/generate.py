from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
RAW = HERE / "raw"
FRAME_PNG = HERE / "frames" / "iphone-16.png"
BACKGROUND = HERE / "backgrounds" / "aurora-teal.jpg"

# Text/chrome colors. The aurora backdrop carries the palette now; we only need
# legible foreground ink plus a cool accent for subtle device grounding.
WHITE = (255, 255, 255)
DIM = (206, 220, 226)

DEVICES = {
    "iphone-6.9": (1290, 2796),
    "ipad-13": (2064, 2752),
}

# Aurora backdrop transform. The source (backgrounds/aurora-teal.jpg) is a
# 1920x1080 landscape gradient; these knobs reorient/crop it to fill the tall
# portrait canvas. rot: one of "0"/"90cw"/"90ccw"/"180". zoom: >1 crops tighter.
# anchor: (x, y) in 0..1 picks which part of the covered image stays in frame.
BG = {
    "rot": "180",
    "zoom": 1.0,
    "anchor": (0.5, 0.5),
    "flip": False,
    # Legibility scrim: darken the top (behind the white headline) and add a
    # gentle floor so the device reads against the backdrop.
    "scrim_top": 165,
    "scrim_bottom": 70,
    "scrim_color": (4, 12, 18),
}

_ROT = {
    "0": None,
    "90cw": Image.ROTATE_270,
    "90ccw": Image.ROTATE_90,
    "180": Image.ROTATE_180,
}

# iPhone 16 frame geometry, in the SVG's 391-wide viewBox units. Scaled to the
# rasterized PNG at load time. glass = live screen rect; di = Dynamic Island.
FRAME_VB_W = 391.0
GLASS_VB = (13, 10, 378, 775)
GLASS_RX_VB = 52
DI_VB = (140, 24, 250, 55)
DI_RX_VB = 15.5

SLIDES = [
    {"title": "Clear photo clutter in minutes.", "screen": "home"},
    {"title": "Review one item at a time.", "screen": "review"},
    {"title": "Find duplicate-looking shots.", "screen": "similar"},
    {"title": "Know what you are looking at.", "screen": "details"},
    {"title": "Review everything before it goes.", "screen": "summary"},
    {"title": "Tune each cleanup session.", "screen": "settings"},
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Avenir Next.ttc",
    ):
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            pass
    return ImageFont.load_default()


def wrapped_lines(draw, text, max_width, fnt) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        test = f"{current} {word}".strip()
        if draw.textbbox((0, 0), test, font=fnt)[2] <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def cover(image: Image.Image, size, zoom: float = 1.0, anchor=(0.5, 0.5)) -> Image.Image:
    """Scale to fully cover `size` (crop overflow), then crop at `anchor`."""
    w, h = size
    ratio = max(w / image.width, h / image.height) * zoom
    resized = image.resize(
        (max(w, round(image.width * ratio)), max(h, round(image.height * ratio))),
        Image.Resampling.LANCZOS,
    )
    ax, ay = anchor
    x = round((resized.width - w) * ax)
    y = round((resized.height - h) * ay)
    return resized.crop((x, y, x + w, y + h))


def rounded_mask(size, radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def scrim(size) -> Image.Image:
    """Vertical dark gradient: strong at top (protects the headline), soft floor."""
    w, h = size
    top, bottom = BG["scrim_top"], BG["scrim_bottom"]
    color = BG["scrim_color"]
    strip = Image.new("RGBA", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        a = int(top * (1 - t) ** 1.5 + bottom * (t ** 2.4))
        px[0, y] = (*color, min(255, a))
    return strip.resize((w, h))


def backdrop(w: int, h: int) -> Image.Image:
    """Aurora background: reorient/crop the source image and lay down the scrim."""
    img = Image.open(BACKGROUND).convert("RGB")
    transpose = _ROT[BG["rot"]]
    if transpose is not None:
        img = img.transpose(transpose)
    if BG["flip"]:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    base = cover(img, (w, h), zoom=BG["zoom"], anchor=BG["anchor"]).convert("RGBA")
    return Image.alpha_composite(base, scrim((w, h)))


def raw_capture(device: str, index: int, screen: str):
    path = RAW / device / f"{index:02d}-{screen}.png"
    return Image.open(path).convert("RGB") if path.exists() else None


# Marketing clock. We retime the captured status bar to Apple's canonical 9:41
# rather than re-capturing with `simctl status_bar override` — the iOS 26.4
# Photos-permission flow makes a clean re-capture unreliable (see capture.sh),
# and the content is already correct, so only the clock needs changing.
CLOCK_IPHONE = "9:41"
CLOCK_IPAD = "9:41 AM"


def _dark_runs(px, band: int, x_lo: int, x_hi: int, thresh=120, gap=18):
    """Contiguous x-runs containing dark (glyph) pixels within the top band."""
    cols = []
    for x in range(x_lo, x_hi):
        for y in range(band):
            r, g, b = px[x, y][:3]
            if r < thresh and g < thresh and b < thresh:
                cols.append(x)
                break
    runs = []
    if cols:
        start = prev = cols[0]
        for x in cols[1:]:
            if x - prev <= gap:
                prev = x
            else:
                runs.append((start, prev))
                start = prev = x
        runs.append((start, prev))
    return runs


def _clock_font(draw, target_h: int) -> ImageFont.FreeTypeFont:
    size = target_h
    for _ in range(30):
        fnt = font(size)
        bb = draw.textbbox((0, 0), "9:41", font=fnt)
        if bb[3] - bb[1] >= target_h:
            return fnt
        size += 1
    return font(size)


def retime_status_bar(shot: Image.Image, device: str) -> Image.Image:
    """Replace the captured status-bar time with the marketing 9:41, drawn in the
    system SF font so it matches iOS exactly. iPhone shows just the time; iPad
    shows time + AM/PM followed by a date, so we retime the time and keep the
    date."""
    shot = shot.convert("RGB").copy()
    d = ImageDraw.Draw(shot)
    px = shot.load()
    band = int(shot.height * 0.045)
    bg = shot.getpixel((int(shot.width * 0.02), band // 2))

    if device.startswith("iphone"):
        runs = _dark_runs(px, band, int(shot.width * 0.10), int(shot.width * 0.35))
        label = CLOCK_IPHONE
    else:
        # iPad: runs are "3:40", "PM", "Tue", "May", "12". The largest gap splits
        # the time+AM/PM from the date; retime up to that split.
        runs = _dark_runs(px, band, int(shot.width * 0.015), int(shot.width * 0.30), gap=14)
        label = CLOCK_IPAD
    if not runs:
        return shot

    x0 = runs[0][0]
    if device.startswith("iphone"):
        x1 = runs[0][1]
    else:
        split = max(range(len(runs) - 1), key=lambda i: runs[i + 1][0] - runs[i][1]) if len(runs) > 1 else 0
        x1 = runs[split][1]

    ys = [y for x in range(x0, x1 + 1) for y in range(band)
          if px[x, y][0] < 120 and px[x, y][1] < 120 and px[x, y][2] < 120]
    y0, y1 = min(ys), max(ys)
    d.rectangle((x0 - 16, y0 - 24, x1 + 34, y1 + 24), fill=bg)
    fnt = _clock_font(d, y1 - y0)
    top_offset = d.textbbox((0, 0), label, font=fnt)[1]
    d.text((x0, y0 - top_offset), label, fill=(0, 0, 0), font=fnt)
    return shot


_FRAME_CACHE: Image.Image | None = None


def _frame() -> Image.Image:
    global _FRAME_CACHE
    if _FRAME_CACHE is None:
        _FRAME_CACHE = Image.open(FRAME_PNG).convert("RGBA")
    return _FRAME_CACHE


def iphone_frame(screenshot, target_w: int) -> Image.Image:
    """Composite a screenshot into the real iPhone 16 frame at native resolution,
    redraw the Dynamic Island on top, then scale to `target_w`."""
    frame = _frame().copy()
    s = frame.width / FRAME_VB_W
    gx0, gy0, gx1, gy1 = (round(v * s) for v in GLASS_VB)
    glass = (gx1 - gx0, gy1 - gy0)

    if screenshot is not None:
        screen = cover(screenshot, glass, anchor=(0.5, 0.5)).convert("RGBA")
        frame.paste(screen, (gx0, gy0), rounded_mask(glass, round(GLASS_RX_VB * s)))

    di = tuple(round(v * s) for v in DI_VB)
    ImageDraw.Draw(frame, "RGBA").rounded_rectangle(di, radius=round(DI_RX_VB * s), fill=(6, 6, 8, 255))

    target_h = round(frame.height * target_w / frame.width)
    return frame.resize((target_w, target_h), Image.Resampling.LANCZOS)


def tablet_frame(screenshot, size) -> Image.Image:
    """Simple dark iPad frame (no photoreal mockup supplied for iPad)."""
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    outer_r, inner_r, inset = 74, 58, 26
    d.rounded_rectangle((0, 0, w, h), radius=outer_r, fill=(12, 13, 17))
    d.rounded_rectangle((2, 2, w - 2, h - 2), radius=outer_r - 2, outline=(255, 255, 255, 40), width=3)
    screen_box = (inset, inset, w - inset, h - inset)
    if screenshot is not None:
        screen = (screen_box[2] - screen_box[0], screen_box[3] - screen_box[1])
        img.paste(cover(screenshot, screen).convert("RGBA"), (screen_box[0], screen_box[1]),
                  rounded_mask(screen, inner_r))
    else:
        d.rounded_rectangle(screen_box, radius=inner_r, fill=(246, 244, 239))
    return img


def device_shadow(frame: Image.Image, blur: int, dy: int):
    """Device-shaped soft shadow built from the frame's own alpha silhouette."""
    pad = blur * 3
    shape = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    shape.putalpha(frame.split()[-1].point(lambda a: a * 175 // 255))
    canvas = Image.new("RGBA", (frame.width + pad * 2, frame.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(shape, (pad, pad + dy))
    return canvas.filter(ImageFilter.GaussianBlur(blur)), pad


def draw_headline(base: Image.Image, title: str, x: int, y: int, max_width: int, scale: float):
    title_font = font(int(96 * scale))
    line_height = int(112 * scale)
    d = ImageDraw.Draw(base, "RGBA")
    for i, line in enumerate(wrapped_lines(d, title, max_width, title_font)[:2]):
        ly = y + i * line_height
        d.text((x + 2, ly + 3), line, fill=(0, 0, 0, 120), font=title_font)
        d.text((x, ly), line, fill=WHITE, font=title_font)


def compose(device: str, slide, index: int):
    w, h = DEVICES[device]
    img = backdrop(w, h)
    screenshot = raw_capture(device, index, slide["screen"])
    if screenshot is not None:
        screenshot = retime_status_bar(screenshot, device)

    if device.startswith("iphone"):
        scale = w / 1290
        draw_headline(img, slide["title"], int(96 * scale), int(196 * scale), int(1110 * scale), scale)

        frame_w = int(1060 * scale)
        frame = iphone_frame(screenshot, frame_w)
        fx = (w - frame.width) // 2
        fy = int(560 * scale)
        shadow, spad = device_shadow(frame, blur=int(70 * scale), dy=int(34 * scale))
        img.alpha_composite(shadow, (fx - spad, fy - spad))
        img.alpha_composite(frame, (fx, fy))
    else:
        draw_headline(img, slide["title"], 170, 250, w - 340, 1.5)
        frame_w, frame_h = 1420, 1893
        frame = tablet_frame(screenshot, (frame_w, frame_h))
        fx = (w - frame_w) // 2
        fy = 720
        shadow, spad = device_shadow(frame, blur=90, dy=46)
        img.alpha_composite(shadow, (fx - spad, fy - spad))
        img.alpha_composite(frame, (fx, fy))

    out_dir = OUT / device
    out_dir.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out_dir / f"{index:02d}-{slide['screen']}.png", optimize=True)


def main():
    for device in DEVICES:
        for i, slide in enumerate(SLIDES, 1):
            compose(device, slide, i)
    print(f"Generated {len(SLIDES) * len(DEVICES)} screenshots in {OUT}")


if __name__ == "__main__":
    main()
