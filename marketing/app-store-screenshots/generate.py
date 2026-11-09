from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
RAW = HERE / "raw"
FRAME_PNG = HERE / "frames" / "iphone-16.png"
FRAME_PNG_IPAD = HERE / "frames" / "ipad-13.png"
BACKGROUND = HERE / "backgrounds" / "aurora-teal.jpg"

# Text/chrome colors. The aurora backdrop carries the palette now; we only need
# legible foreground ink plus a cool accent for subtle device grounding.
WHITE = (255, 255, 255)
DIM = (206, 220, 226)

DEVICES = {
    "iphone-6.9": (1290, 2796),
    "ipad-13": (2064, 2752),
    # iPhone Duo needs a set for each display: the outer display, folded, and
    # the inner display, unfolded in landscape the way it opens like a book.
    "iphone-duo-outer": (1398, 2034),
    "iphone-duo-inner": (2853, 2007),
    # Mac App Store: 16:10 retina. 2880×1800 is the largest accepted size.
    "mac": (2880, 1800),
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

# Mac backdrop. Same aurora source, but the canvas is landscape (2880×1800) and
# the source is already landscape (1920×1080), so no rotation — just cover-fit.
# A stronger top scrim protects the centered white headline; a gentle floor
# grounds the window.
BG_MAC = {
    "rot": "0",
    "zoom": 1.0,
    "anchor": (0.5, 0.5),
    "flip": False,
    "scrim_top": 150,
    "scrim_bottom": 55,
    "scrim_color": (4, 12, 18),
}

# iPhone 16 frame geometry, in the SVG's 391-wide viewBox units. Scaled to the
# rasterized PNG at load time. glass = live screen rect; di = Dynamic Island.
FRAME_VB_W = 391.0
GLASS_VB = (13, 10, 378, 775)
GLASS_RX_VB = 52
DI_VB = (140, 24, 250, 55)
DI_RX_VB = 15.5

# A real 6.9" screenshot is 1320x2868 (aspect 0.4603). The SVG's glass opening is
# ~3.7% too wide for that, so a straight cover-fit had to crop the status bar and
# tab bar to fill it. We instead stretch the frame vertically at load so the glass
# matches this aspect exactly: the capture then maps 1:1 (no crop, no squish) and
# the clock lands aligned with the Dynamic Island.
SCREEN_ASPECT = 1320 / 2868

# iPad Pro 13" frame geometry, in the SVG's 707-wide viewBox units
# (frames/ipad-13.svg). glass = live screen rect, taken from the SVG's screen
# mask. There's no Dynamic Island, and the glass aspect (639.835/852.898 = 0.7502)
# already matches a real 2064x2752 capture (0.7500), so — unlike the iPhone — no
# vertical stretch is needed; the capture maps ~1:1 into the glass.
IPAD_FRAME_VB_W = 707.0
IPAD_GLASS_VB = (33.5825, 33.5509, 673.417, 886.449)
IPAD_GLASS_RX_VB = 12.37

# iPhone Duo frame. There's no mockup to trace, so duo_frame() draws one in the
# style of the iPhone and iPad frames: a graphite rim and a black bezel around
# the screen's real shape, plus the buttons and the hinge. Sizes are in screen
# pixels (3 px = 1 pt).
#
# DUO_CORNER is Apple's continuous corner as three cubic Béziers, for a
# top-right corner, in units of how far the corner runs along each edge. It and
# each display's corner reach come from the simulator's framebuffer masks
# (iPhone Duo.simdevicetype). The outer display's corners are tight along the
# hinge, which runs down its left edge.
DUO_CORNER = (
    (-1.0, 0.0), (-0.65228, 0.0), (-0.52618, 0.03621), (-0.39906, 0.10419),
    (-0.27194, 0.17218), (-0.17218, 0.27194), (-0.10419, 0.39906),
    (-0.03621, 0.52618), (0.0, 0.65228), (0.0, 1.0),
)
# Screen size and corner reach (top-left, top-right, bottom-right, bottom-left).
DUO_SCREENS = {
    "iphone-duo-outer": ((1398, 2034), (30.8, 226.9, 226.9, 30.8)),
    "iphone-duo-inner": ((2853, 2007), (205.5, 205.5, 205.5, 205.5)),
}
DUO_RIM = 12
DUO_BEZEL = 24
# Room around the body for the buttons and the hinge.
DUO_MARGIN = 30
# Buttons as (edge, start, end) along that edge of the body, as fractions. On
# the inner display they're on the half behind the outer display.
DUO_BUTTONS = {
    "iphone-duo-outer": (("top", 0.47, 0.59), ("top", 0.63, 0.75), ("right", 0.29, 0.44)),
    "iphone-duo-inner": (("top", 0.735, 0.795), ("top", 0.815, 0.875), ("right", 0.29, 0.44)),
}
# The outer display's camera, (center x, center y, radius) on the screen. Like
# the iPhone's Dynamic Island, it isn't in an XCTest capture, so it's redrawn.
DUO_CAMERA = {"iphone-duo-outer": (1254, 143, 55.5)}
# Supersampling for anti-aliased edges.
DUO_SS = 3

SLIDES = [
    {"title": "Clear photo clutter by category.", "screen": "home"},
    {"title": "Keep or delete, one at a time.", "screen": "review"},
    {"title": "Compare similar shots.", "screen": "similar"},
    {"title": "See a photo's date, size, and location.", "screen": "details"},
    {"title": "Check what's marked before you delete.", "screen": "summary"},
    {"title": "Set your review size and what's remembered.", "screen": "settings"},
]

# Headlines that change on iPhone Duo, by screen. Unfolded, Similar review puts
# the photo beside another from its group. Neither display is tall enough to
# show the details sheet down to its location map.
TITLES_DUO = {
    "iphone-duo-outer": {
        "details": "See a photo's date, size, and more.",
    },
    "iphone-duo-inner": {
        "similar": "Compare similar shots side by side.",
        "details": "See a photo's date, size, and more.",
    },
}

# Mac App Store slides. Fewer, landscape, and the window is framed instead of a
# device — see compose_mac. `screen` matches the raw/mac/NN-<screen>.png suffix
# and the SNIPSNAPS_SCREENSHOT_SCREEN value the capture script launches with.
SLIDES_MAC = [
    {"title": "Clear photo clutter by category.", "screen": "home"},
    {"title": "Keep or delete, one at a time.", "screen": "review"},
    {"title": "Compare similar shots.", "screen": "similar"},
    {"title": "Clean up Downloads, Desktop, and Documents.", "screen": "files"},
]

# Headline weight. San Francisco (SFNS.ttf) is a variable font; we select a
# named weight off its wght axis so the marketing headline carries the same
# confident weight as the app's own bold titles ("SnipSnaps", "Settings")
# instead of the thin Regular that got lost against the aurora backdrop.
# Options: "Regular" / "Medium" / "Semibold" / "Bold" / "Heavy". "Semibold" is
# the quieter alternative; "Heavy" reads as an ad and is too much for a utility.
HEADLINE_WEIGHT = "Bold"

# wght-axis coordinate per named weight (SF's Weight axis runs 1-1000, Regular=400).
_WEIGHTS = {"Regular": 400, "Medium": 500, "Semibold": 600, "Bold": 700, "Heavy": 860}


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    for candidate in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Avenir Next.ttc",
    ):
        try:
            fnt = ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
        # SFNS is variable: pin axes (Width=100, Optical Size=96 for display-tuned
        # letterforms, GRAD=400) and set the requested weight. Non-variable
        # fallbacks silently skip this and render at their default weight.
        if candidate.endswith("SFNS.ttf") and weight in _WEIGHTS:
            try:
                fnt.set_variation_by_axes([100, 96, 400, _WEIGHTS[weight]])
            except (OSError, ValueError):
                pass
        return fnt
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


def balanced_lines(draw, text, max_width, fnt) -> list[str]:
    """Like wrapped_lines, but two lines break where they're closest in length,
    so the second line isn't a lone word."""
    lines = wrapped_lines(draw, text, max_width, fnt)
    if len(lines) != 2:
        return lines
    words = text.split()

    def width(i):
        return max(draw.textbbox((0, 0), " ".join(part), font=fnt)[2] for part in (words[:i], words[i:]))

    split = min(range(1, len(words)), key=width)
    return [" ".join(words[:split]), " ".join(words[split:])]


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


def scrim(size, cfg=BG) -> Image.Image:
    """Vertical dark gradient: strong at top (protects the headline), soft floor."""
    w, h = size
    top, bottom = cfg["scrim_top"], cfg["scrim_bottom"]
    color = cfg["scrim_color"]
    strip = Image.new("RGBA", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        a = int(top * (1 - t) ** 1.5 + bottom * (t ** 2.4))
        px[0, y] = (*color, min(255, a))
    return strip.resize((w, h))


def backdrop(w: int, h: int, cfg=BG) -> Image.Image:
    """Aurora background: reorient/crop the source image and lay down the scrim."""
    img = Image.open(BACKGROUND).convert("RGB")
    transpose = _ROT[cfg["rot"]]
    if transpose is not None:
        img = img.transpose(transpose)
    if cfg["flip"]:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    base = cover(img, (w, h), zoom=cfg["zoom"], anchor=cfg["anchor"]).convert("RGBA")
    return Image.alpha_composite(base, scrim((w, h), cfg))


def raw_capture(device: str, index: int, screen: str):
    path = RAW / device / f"{index:02d}-{screen}.png"
    return Image.open(path).convert("RGB") if path.exists() else None


# The status bar is baked in natively at capture time: capture.sh sets
# `simctl status_bar override` (9:41, full battery, Wi-Fi, 4 signal bars) before
# the UI test runs, so the raw captures already carry a clean marketing status
# bar and no compositing-time retiming/redrawing is needed.


_FRAME_CACHE: tuple[Image.Image, float, float] | None = None


def _frame() -> tuple[Image.Image, float, float]:
    """Frame image with its glass opening stretched to SCREEN_ASPECT, plus the
    per-axis viewBox->pixel scales (sx, sy). sy > sx by the stretch factor."""
    global _FRAME_CACHE
    if _FRAME_CACHE is None:
        frame = Image.open(FRAME_PNG).convert("RGBA")
        sx = frame.width / FRAME_VB_W
        glass_w = (GLASS_VB[2] - GLASS_VB[0]) * sx
        glass_h = (GLASS_VB[3] - GLASS_VB[1]) * sx
        vstretch = (glass_w / SCREEN_ASPECT) / glass_h
        frame = frame.resize((frame.width, round(frame.height * vstretch)), Image.Resampling.LANCZOS)
        _FRAME_CACHE = (frame, sx, sx * vstretch)
    return _FRAME_CACHE


def iphone_frame(screenshot, target_w: int) -> Image.Image:
    """Composite a screenshot into the real iPhone 16 frame at native resolution,
    redraw the Dynamic Island on top, then scale to `target_w`."""
    frame, sx, sy = _frame()
    frame = frame.copy()
    gx0, gy0 = round(GLASS_VB[0] * sx), round(GLASS_VB[1] * sy)
    gx1, gy1 = round(GLASS_VB[2] * sx), round(GLASS_VB[3] * sy)
    glass = (gx1 - gx0, gy1 - gy0)

    if screenshot is not None:
        screen = cover(screenshot, glass, anchor=(0.5, 0.5)).convert("RGBA")
        frame.paste(screen, (gx0, gy0), rounded_mask(glass, round(GLASS_RX_VB * sx)))

    di = (round(DI_VB[0] * sx), round(DI_VB[1] * sy), round(DI_VB[2] * sx), round(DI_VB[3] * sy))
    ImageDraw.Draw(frame, "RGBA").rounded_rectangle(di, radius=round(DI_RX_VB * sy), fill=(6, 6, 8, 255))

    target_h = round(frame.height * target_w / frame.width)
    return frame.resize((target_w, target_h), Image.Resampling.LANCZOS)


_IPAD_FRAME_CACHE: Image.Image | None = None


def ipad_frame(screenshot, target_w: int) -> Image.Image:
    """Composite a screenshot into the real iPad Pro 13" frame at native
    resolution, then scale to `target_w`. No vertical stretch and no Dynamic
    Island (see the IPAD_* geometry note) — the capture maps ~1:1 into the glass."""
    global _IPAD_FRAME_CACHE
    if _IPAD_FRAME_CACHE is None:
        _IPAD_FRAME_CACHE = Image.open(FRAME_PNG_IPAD).convert("RGBA")
    frame = _IPAD_FRAME_CACHE.copy()
    s = frame.width / IPAD_FRAME_VB_W
    gx0, gy0 = round(IPAD_GLASS_VB[0] * s), round(IPAD_GLASS_VB[1] * s)
    gx1, gy1 = round(IPAD_GLASS_VB[2] * s), round(IPAD_GLASS_VB[3] * s)
    glass = (gx1 - gx0, gy1 - gy0)

    if screenshot is not None:
        screen = cover(screenshot, glass, anchor=(0.5, 0.5)).convert("RGBA")
        frame.paste(screen, (gx0, gy0), rounded_mask(glass, round(IPAD_GLASS_RX_VB * s)))

    target_h = round(frame.height * target_w / frame.width)
    return frame.resize((target_w, target_h), Image.Resampling.LANCZOS)


def _cubic(p0, p1, p2, p3, steps: int) -> list[tuple[float, float]]:
    points = []
    for i in range(1, steps + 1):
        t = i / steps
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t**2, t**3
        points.append((
            a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
            a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
        ))
    return points


def continuous_rect(box, reach, steps: int = 16) -> list[tuple[float, float]]:
    """Polygon for `box` (x0, y0, x1, y1) with Apple's continuous corners.
    `reach` is how far each corner (top-left, top-right, bottom-right,
    bottom-left) runs along its edges."""
    x0, y0, x1, y1 = box
    tl, tr, br, bl = reach
    curve = [DUO_CORNER[0]]
    for i in (0, 3, 6):
        curve += _cubic(*DUO_CORNER[i:i + 4], steps)
    # Clockwise from the top-right corner; each corner mirrors the last.
    return (
        [(x1 + u * tr, y0 + v * tr) for u, v in curve]
        + [(x1 + u * br, y1 - v * br) for u, v in reversed(curve)]
        + [(x0 - u * bl, y1 - v * bl) for u, v in curve]
        + [(x0 - u * tl, y0 + v * tl) for u, v in reversed(curve)]
    )


def _aa_mask(size, draw) -> Image.Image:
    """An anti-aliased mask: `draw(d, s)` draws at `s` times the size."""
    big = Image.new("L", (size[0] * DUO_SS, size[1] * DUO_SS), 0)
    draw(ImageDraw.Draw(big), DUO_SS)
    return big.resize(size, Image.Resampling.BOX)


def _fill(frame: Image.Image, mask: Image.Image, fill):
    """Composite a color, or an RGBA image the frame's size, through `mask`."""
    layer = fill.copy() if isinstance(fill, Image.Image) else Image.new("RGBA", frame.size, fill)
    layer.putalpha(ImageChops.multiply(layer.split()[-1], mask))
    frame.alpha_composite(layer)


_DUO_FRAME_CACHE: dict[str, tuple[Image.Image, Image.Image, tuple[int, int]]] = {}


def _duo_body(device: str):
    """The empty iPhone Duo frame at screen resolution, its screen mask, and
    where the screen goes."""
    if device in _DUO_FRAME_CACHE:
        return _DUO_FRAME_CACHE[device]
    (sw, sh), reach = DUO_SCREENS[device]
    border = DUO_RIM + DUO_BEZEL
    inset = DUO_MARGIN + border
    size = (sw + 2 * inset, sh + 2 * inset)
    frame = Image.new("RGBA", size, (0, 0, 0, 0))

    def shape(grow: float):
        # The screen's shape grown by `grow` on every side; the corners grow
        # with it so the rim and bezel stay concentric with the screen.
        box = (inset - grow, inset - grow, inset + sw + grow, inset + sh + grow)
        return continuous_rect(box, [r + grow * 1.52866 for r in reach])

    def polygon(grow: float):
        return _aa_mask(size, lambda d, s: d.polygon([(x * s, y * s) for x, y in shape(grow)], fill=255))

    bx0, by0, bx1, by1 = inset - border, inset - border, inset + sw + border, inset + sh + border
    body_w, body_h = bx1 - bx0, by1 - by0

    # Buttons sit behind the body, so only their outer edge shows.
    out, overlap = 9, 12
    for edge, start, end in DUO_BUTTONS[device]:
        if edge == "top":
            rect = (bx0 + body_w * start, by0 - out, bx0 + body_w * end, by0 + overlap)
        else:
            rect = (bx1 - overlap, by0 + body_h * start, bx1 + out, by0 + body_h * end)
        for grow, color in ((0, (36, 36, 39)), (-2.5, (62, 62, 66))):
            r = [rect[0] - grow, rect[1] - grow, rect[2] + grow, rect[3] + grow]
            _fill(frame, _aa_mask(size, lambda d, s, r=r: d.rounded_rectangle(
                [v * s for v in r], radius=(out + grow) * s, fill=255)), color)

    if device == "iphone-duo-outer":
        # The hinge: a rounded spine down the left edge, shaded like a cylinder.
        spine_out, spine_in = 16, 24
        rect = (bx0 - spine_out, by0 + 14, bx0 + spine_in, by1 - 14)
        spine = _aa_mask(size, lambda d, s: d.rounded_rectangle(
            [v * s for v in rect], radius=spine_out * s, fill=255))
        row = Image.new("RGBA", (spine_out, 1))
        for x, color in enumerate(
            [(30, 30, 33)] * 2 + [(48, 48, 52)] * 3 + [(72, 72, 77)] * 4 + [(56, 56, 60)] * 4 + [(40, 40, 43)] * 3
        ):
            row.putpixel((x, 0), (*color, 255))
        shading = Image.new("RGBA", size, (40, 40, 43, 255))
        shading.paste(row.resize((spine_out, size[1]), Image.Resampling.NEAREST), (bx0 - spine_out, 0))
        _fill(frame, spine, shading)

    # Rim (dark, a highlight, then mid graphite), then the bezel.
    outline = polygon(border)
    _fill(frame, outline, (38, 38, 41))
    for grow, color in ((border - 3, (66, 66, 70)), (border - 7, (46, 46, 49)), (DUO_BEZEL, (9, 10, 11))):
        _fill(frame, polygon(grow), color)

    if device == "iphone-duo-inner":
        # The hinge shows as a seam across the rim, top and bottom.
        cx = size[0] / 2
        seams = _aa_mask(size, lambda d, s: [
            d.rectangle([(cx - 2.5) * s, y0 * s, (cx + 2.5) * s, y1 * s], fill=255)
            for y0, y1 in ((by0 - 1, by0 + DUO_RIM + 1), (by1 - DUO_RIM - 1, by1 + 1))
        ])
        _fill(frame, ImageChops.multiply(seams, outline), (14, 14, 16))

    _DUO_FRAME_CACHE[device] = (frame, polygon(0), (inset, inset))
    return _DUO_FRAME_CACHE[device]


def duo_frame(device: str, screenshot, target_w: int) -> Image.Image:
    """Composite a screenshot into the drawn iPhone Duo frame at screen
    resolution, then scale to `target_w`."""
    body, screen_mask, origin = _duo_body(device)
    frame = body.copy()
    if screenshot is not None:
        size = DUO_SCREENS[device][0]
        screen = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        screen.paste(cover(screenshot, size).convert("RGBA"), origin)
        _fill(frame, screen_mask, screen)
    if device in DUO_CAMERA:
        cx, cy, r = DUO_CAMERA[device]
        cx, cy = cx + origin[0], cy + origin[1]
        _fill(frame, _aa_mask(frame.size, lambda d, s: d.ellipse(
            [(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=255)), (6, 6, 8))
    target_h = round(frame.height * target_w / frame.width)
    return frame.resize((target_w, target_h), Image.Resampling.LANCZOS)


def device_shadow(frame: Image.Image, blur: int, dy: int):
    """Device-shaped soft shadow built from the frame's own alpha silhouette."""
    pad = blur * 3
    shape = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    shape.putalpha(frame.split()[-1].point(lambda a: a * 175 // 255))
    canvas = Image.new("RGBA", (frame.width + pad * 2, frame.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(shape, (pad, pad + dy))
    return canvas.filter(ImageFilter.GaussianBlur(blur)), pad


def draw_headline(base: Image.Image, title: str, x: int, y: int, max_width: int, scale: float):
    title_font = font(int(100 * scale), HEADLINE_WEIGHT)
    line_height = int(116 * scale)
    d = ImageDraw.Draw(base, "RGBA")
    for i, line in enumerate(wrapped_lines(d, title, max_width, title_font)[:2]):
        ly = y + i * line_height
        d.text((x + 2, ly + 3), line, fill=(0, 0, 0, 120), font=title_font)
        d.text((x, ly), line, fill=WHITE, font=title_font)


def _has_transparent_corners(img: Image.Image) -> bool:
    """True if the capture already carries its own rounded-corner alpha (a real
    `screencapture` window grab) so we don't re-round it."""
    if img.mode != "RGBA":
        return False
    w, h = img.size
    alpha = img.split()[-1]
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    return any(alpha.getpixel(c) < 200 for c in corners)


def mac_window(screenshot: Image.Image, target_w: int) -> Image.Image:
    """Frame a captured Mac window for the marketing shot: scale to `target_w`,
    round the corners (unless the capture already has them), and add a hairline
    rim so the window reads against the backdrop. No device mockup — just the
    real window, per the Jesse Squires 'window on a desktop' treatment."""
    ratio = target_w / screenshot.width
    target_h = round(screenshot.height * ratio)
    win = screenshot.resize((target_w, target_h), Image.Resampling.LANCZOS).convert("RGBA")

    if not _has_transparent_corners(win):
        # Opaque/square capture (a fallback full-window grab) — round it ourselves.
        win.putalpha(rounded_mask((target_w, target_h), round(target_w * 0.018)))

    # Hairline rim: a ~2px bright ring derived from the window's OWN alpha edge
    # (alpha minus a 2px erosion of it), so it hugs the real rounded corners
    # exactly and can never paint outside them — regardless of the window's
    # actual corner radius. A fixed-radius rounded_rectangle stroke would sit
    # inside the corner curve and leave faint specks in the transparent corners.
    alpha = win.split()[-1]
    ring = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(5)))
    rim = Image.new("RGBA", win.size, (255, 255, 255, 0))
    rim.putalpha(ring.point(lambda a: 46 if a > 127 else 0))
    win.alpha_composite(rim)
    return win


def draw_headline_centered(
    base: Image.Image, title: str, zone_top: int, zone_h: int, max_width: int, font_size: int, balance: bool = False
):
    """Centered white headline (up to 2 lines), block vertically centered within a
    fixed [zone_top, zone_top+zone_h] band so a one-line and a two-line headline
    both sit centered — and the window below lands at the same y on every slide.
    `balance` evens out the two lines' lengths.

    Legibility comes from a *soft blurred* shadow (a diffuse halo), not a hard
    offset black copy — the offset copy reads as a crude second set of letters
    behind the white."""
    title_font = font(font_size, HEADLINE_WEIGHT)
    line_height = int(font_size * 1.16)
    d = ImageDraw.Draw(base, "RGBA")
    lines = (balanced_lines if balance else wrapped_lines)(d, title, max_width, title_font)[:2]
    cx = base.width // 2
    start_y = zone_top + max(0, (zone_h - len(lines) * line_height) // 2)

    placed = []
    for i, line in enumerate(lines):
        bbox = d.textbbox((0, 0), line, font=title_font)
        x = cx - (bbox[2] - bbox[0]) // 2
        placed.append((line, x, start_y + i * line_height))

    # Soft shadow: render the lines onto a transparent layer, blur, composite at
    # low opacity — a diffuse glow that lifts the text off the backdrop.
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for line, x, ly in placed:
        sd.text((x, ly + max(2, font_size // 44)), line, fill=(0, 0, 0, 140), font=title_font)
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(4, font_size // 14))))

    for line, x, ly in placed:
        d.text((x, ly), line, fill=WHITE, font=title_font)


def compose_mac(device: str, slide, index: int):
    """Compose one Mac App Store slide: aurora backdrop, centered headline, and
    the real app window floating below with a soft device-shaped shadow. The
    window is scaled to fit the space under a fixed headline band so it's the
    same size and position on every slide and never runs off the canvas."""
    w, h = DEVICES[device]
    scale = w / 2880
    img = backdrop(w, h, BG_MAC)

    zone_top, zone_h = int(90 * scale), int(300 * scale)
    draw_headline_centered(
        img, slide["title"], zone_top, zone_h, max_width=int(2400 * scale), font_size=int(126 * scale)
    )

    path = RAW / device / f"{index:02d}-{slide['screen']}.png"
    if path.exists():
        raw = Image.open(path).convert("RGBA")
        avail_top = zone_top + zone_h + int(70 * scale)
        avail_bottom = h - int(90 * scale)
        avail_h = avail_bottom - avail_top

        raw_aspect = raw.height / raw.width
        window_w = min(int(2200 * scale), int(avail_h / raw_aspect))
        frame = mac_window(raw, window_w)

        fx = (w - frame.width) // 2
        fy = avail_top + max(0, (avail_h - frame.height) // 2)

        shadow, spad = device_shadow(frame, blur=int(85 * scale), dy=int(42 * scale))
        img.alpha_composite(shadow, (fx - spad, fy - spad))
        img.alpha_composite(frame, (fx, fy))

    out_dir = OUT / device
    out_dir.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out_dir / f"{index:02d}-{slide['screen']}.png", optimize=True)


def compose_duo(device: str, slide, index: int):
    """Compose one iPhone Duo slide in the iPhone and iPad style. The outer
    display is portrait, with the headline top left. The inner display is
    landscape, so it follows the Mac layout: a centered headline over the
    device."""
    w, h = DEVICES[device]
    title = TITLES_DUO[device].get(slide["screen"], slide["title"])
    screenshot = raw_capture(device, index, slide["screen"])

    if device == "iphone-duo-inner":
        scale = w / 2880
        img = backdrop(w, h, BG_MAC)
        zone_top, zone_h = int(90 * scale), int(300 * scale)
        draw_headline_centered(
            img, title, zone_top, zone_h, max_width=int(2400 * scale), font_size=int(126 * scale), balance=True
        )
        top = zone_top + zone_h + int(40 * scale)
        avail_h = h - int(70 * scale) - top
        body = _duo_body(device)[0]
        frame = duo_frame(device, screenshot, int(avail_h * body.width / body.height))
        fx = (w - frame.width) // 2
        fy = top + (avail_h - frame.height) // 2
        shadow, spad = device_shadow(frame, blur=int(85 * scale), dy=int(42 * scale))
    else:
        scale = w / 1398
        img = backdrop(w, h)
        draw_headline(img, title, int(110 * scale), int(160 * scale), w - int(220 * scale), 1.05 * scale)
        frame = duo_frame(device, screenshot, int(1060 * scale))
        fx = (w - frame.width) // 2
        fy = h - frame.height - int(56 * scale)
        shadow, spad = device_shadow(frame, blur=int(70 * scale), dy=int(34 * scale))

    img.alpha_composite(shadow, (fx - spad, fy - spad))
    img.alpha_composite(frame, (fx, fy))
    out_dir = OUT / device
    out_dir.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out_dir / f"{index:02d}-{slide['screen']}.png", optimize=True)


def compose(device: str, slide, index: int):
    w, h = DEVICES[device]
    img = backdrop(w, h)
    screenshot = raw_capture(device, index, slide["screen"])

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
        frame = ipad_frame(screenshot, 1500)
        fx = (w - frame.width) // 2
        fy = 700
        shadow, spad = device_shadow(frame, blur=90, dy=46)
        img.alpha_composite(shadow, (fx - spad, fy - spad))
        img.alpha_composite(frame, (fx, fy))

    out_dir = OUT / device
    out_dir.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out_dir / f"{index:02d}-{slide['screen']}.png", optimize=True)


def main():
    parser = argparse.ArgumentParser(description="Composite the existing App Store screenshot style.")
    parser.add_argument("--device", action="append", choices=DEVICES, help="Repeat to select devices; defaults to all.")
    parser.add_argument("--screen", action="append", choices=sorted({s["screen"] for s in SLIDES + SLIDES_MAC}),
                        help="Repeat to select screens; keeps the original slide numbering.")
    args = parser.parse_args()
    selected = [
        (device, i, slide)
        for device in DEVICES if not args.device or device in args.device
        for i, slide in enumerate(SLIDES_MAC if device == "mac" else SLIDES, 1)
        if not args.screen or slide["screen"] in args.screen
    ]
    if not selected:
        parser.error("No slides match the selected device and screen.")
    # Check the entire selection before writing any output. A missing capture
    # must not silently turn into placeholder UI in a release asset.
    for device, i, slide in selected:
        path = RAW / device / f"{i:02d}-{slide['screen']}.png"
        if not path.is_file():
            parser.error(f"Missing raw capture: {path}")
    for device, i, slide in selected:
        if device == "mac":
            compose_mac(device, slide, i)
        elif device in DUO_SCREENS:
            compose_duo(device, slide, i)
        else:
            compose(device, slide, i)
    print(f"Generated {len(selected)} screenshots in {OUT}")


if __name__ == "__main__":
    main()
