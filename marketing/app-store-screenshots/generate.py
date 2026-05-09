from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "output"
RAW = Path(__file__).resolve().parent / "raw"
ICON = ROOT / "SnipSnaps/Assets.xcassets/AppIcon.appiconset/Frame 11.png"

WARM = (248, 243, 235)
INK = (32, 30, 28)
MUTED = (105, 97, 89)
CARD = (255, 252, 247)
ACCENT = (229, 88, 106)
GREEN = (47, 168, 109)
RED = (222, 74, 86)
BLUE = (78, 116, 204)

DEVICES = {
    "iphone-6.9": (1290, 2796),
    "ipad-13": (2064, 2752),
}

SLIDES = [
    {
        "kicker": "SNIPSNAPS",
        "title": "Clear photo clutter in minutes.",
        "subtitle": "Pick a review mode, swipe through your library, and keep only what matters.",
        "screen": "home",
    },
    {
        "kicker": "FAST REVIEW",
        "title": "Swipe fast. Keep the best.",
        "subtitle": "A focused card stack helps every decision feel quick and deliberate.",
        "screen": "review",
    },
    {
        "kicker": "SIMILAR PHOTOS",
        "title": "Find duplicate-looking shots.",
        "subtitle": "Compare near matches side by side and keep more than one when you need to.",
        "screen": "similar",
    },
    {
        "kicker": "CONTEXT",
        "title": "Know what you are looking at.",
        "subtitle": "Dates, age, file size, and details make every cleanup decision easier.",
        "screen": "details",
    },
    {
        "kicker": "SAFE DELETE",
        "title": "Review everything before it goes.",
        "subtitle": "Marked photos are grouped for one final check before deleting.",
        "screen": "summary",
    },
    {
        "kicker": "SETTINGS",
        "title": "Tune each cleanup session.",
        "subtitle": "Set review size and track lifetime cleanup progress over time.",
        "screen": "settings",
    },
]


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Avenir Next.ttc",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            pass
    return ImageFont.load_default()


def rounded(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def paste_round(base: Image.Image, image: Image.Image, xy: tuple[int, int], radius: int):
    mask = Image.new("L", image.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    base.paste(image, xy, mask)


def fit_image(image: Image.Image, size: tuple[int, int], fill=(246, 244, 239)) -> Image.Image:
    image = image.convert("RGB")
    canvas = Image.new("RGB", size, fill)
    ratio = min(size[0] / image.width, size[1] / image.height)
    resized = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return canvas


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", size, top)
    pix = img.load()
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(size[0]):
            pix[x, y] = color
    return img


def wrapped_lines(draw: ImageDraw.ImageDraw, text: str, max_width: int, fnt) -> list[str]:
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


def draw_wrapped(draw: ImageDraw.ImageDraw, text: str, xy: tuple[int, int], max_width: int, fill, fnt, line_gap: int = 10) -> int:
    lines = wrapped_lines(draw, text, max_width, fnt)
    y = xy[1]
    for line in lines:
        draw.text((xy[0], y), line, fill=fill, font=fnt)
        y += draw.textbbox((0, 0), line, font=fnt)[3] + line_gap
    return y


def synthetic_photo(seed: int, size: tuple[int, int]) -> Image.Image:
    random.seed(seed)
    palettes = [
        ((255, 183, 137), (88, 132, 179), (244, 232, 198)),
        ((101, 151, 178), (28, 75, 101), (248, 212, 160)),
        ((222, 147, 128), (98, 79, 120), (245, 220, 180)),
        ((122, 172, 129), (58, 112, 92), (238, 225, 183)),
        ((211, 187, 160), (122, 113, 107), (247, 241, 229)),
    ]
    sky, deep, light = palettes[seed % len(palettes)]
    img = gradient(size, light, sky)
    d = ImageDraw.Draw(img, "RGBA")
    w, h = size
    horizon = int(h * random.uniform(0.48, 0.68))
    d.rectangle((0, horizon, w, h), fill=(*deep, 210))
    for i in range(5):
        x = int(w * (i / 4))
        peak = int(horizon - random.uniform(0.16, 0.38) * h)
        d.polygon([(x - w // 3, horizon), (x, peak), (x + w // 3, horizon)], fill=(55, 70, 80, 72))
    for _ in range(5):
        cx = random.randint(0, w)
        cy = random.randint(int(h * 0.1), int(h * 0.45))
        r = random.randint(w // 18, w // 7)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 44))
    img = img.filter(ImageFilter.GaussianBlur(radius=max(w, h) * 0.006))
    return img


def load_icon(size: int) -> Image.Image:
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    return icon


def draw_background(draw: ImageDraw.ImageDraw, w: int, h: int):
    draw.ellipse((-w * 0.15, -h * 0.12, w * 0.65, h * 0.32), fill=(255, 219, 205))
    draw.ellipse((w * 0.55, h * 0.08, w * 1.18, h * 0.56), fill=(229, 240, 221))
    draw.ellipse((w * 0.16, h * 0.75, w * 0.86, h * 1.14), fill=(236, 229, 255))


def draw_slide_text(draw: ImageDraw.ImageDraw, slide: dict, x: int, y: int, max_width: int, scale: float):
    kicker_font = font(int(30 * scale))
    title_font = font(int(78 * scale))
    subtitle_font = font(int(31 * scale))
    title_line_height = int(92 * scale)
    subtitle_line_height = int(43 * scale)
    draw.text((x, y), slide["kicker"], fill=ACCENT, font=kicker_font)
    y += int(68 * scale)
    title_lines = wrapped_lines(draw, slide["title"], max_width, title_font)[:2]
    for index, line in enumerate(title_lines):
        draw.text((x, y + index * title_line_height), line, fill=INK, font=title_font)
    y += title_line_height * 2 + int(18 * scale)
    subtitle_lines = wrapped_lines(draw, slide["subtitle"], max_width, subtitle_font)[:2]
    for index, line in enumerate(subtitle_lines):
        draw.text((x, y + index * subtitle_line_height), line, fill=MUTED, font=subtitle_font)


def raw_capture(device: str, index: int, screen: str) -> Image.Image | None:
    path = RAW / device / f"{index:02d}-{screen}.png"
    if path.exists():
        return Image.open(path).convert("RGB")
    return None


def app_frame(
    size: tuple[int, int],
    screen: str,
    scale: float,
    screenshot: Image.Image | None = None,
    style: str = "phone",
) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    outer_radius = int((62 if style == "phone" else 42) * scale)
    inner_radius = int((48 if style == "phone" else 30) * scale)
    inset = int((20 if style == "phone" else 18) * scale)
    rounded(d, (0, 0, w, h), outer_radius, fill=(21, 21, 24), outline=(0, 0, 0, 35), width=max(2, int(3 * scale)))
    screen_box = (inset, inset, w - inset, h - inset)
    rounded(d, screen_box, inner_radius, fill=(246, 244, 239))
    if screenshot is not None:
        screen_size = (screen_box[2] - screen_box[0], screen_box[3] - screen_box[1])
        paste_round(img, fit_image(screenshot, screen_size).convert("RGBA"), (screen_box[0], screen_box[1]), inner_radius)
    else:
        render_app_screen(img, screen_box, screen, scale)
    if style == "phone":
        d.rounded_rectangle((w * 0.36, inset + int(13 * scale), w * 0.64, inset + int(36 * scale)), radius=int(14 * scale), fill=(19, 19, 21))
    return img


def render_app_screen(base: Image.Image, box: tuple[int, int, int, int], screen: str, scale: float):
    d = ImageDraw.Draw(base, "RGBA")
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    pad = int(34 * scale)
    title_font = font(int(37 * scale))
    body_font = font(int(22 * scale))
    small_font = font(int(17 * scale))
    rounded(d, box, int(48 * scale), fill=(246, 244, 239))

    def app_header(title: str, large: bool = True):
        d.text((x0 + pad, y0 + int(56 * scale)), title, fill=INK, font=font(int((44 if large else 29) * scale)))

    if screen == "home":
        app_header("SnipSnaps")
        d.text((x0 + pad, y0 + int(120 * scale)), "Swipe fast, keep the best, clear the rest.", fill=MUTED, font=body_font)
        cards = [
            ("Today", "Review your newest shots", "24", (255, 240, 214)),
            ("On This Day", "Photos from May 8 across the years", "88", (236, 242, 255)),
            ("Screenshots", "Clear the clutter fast", "143", (255, 232, 235)),
            ("Similar Photos", "Review duplicate-looking groups", "SCAN", (234, 247, 237)),
        ]
        cy = y0 + int(184 * scale)
        for title, sub, count, color in cards:
            rounded(d, (x0 + pad, cy, x1 - pad, cy + int(124 * scale)), int(22 * scale), fill=CARD)
            d.text((x0 + pad + int(22 * scale), cy + int(28 * scale)), title, fill=INK, font=title_font)
            d.text((x0 + pad + int(22 * scale), cy + int(75 * scale)), sub, fill=MUTED, font=small_font)
            d.text((x1 - pad - int(150 * scale), cy + int(25 * scale)), count, fill=(205, 196, 186), font=font(int(42 * scale)))
            cy += int(145 * scale)
    elif screen == "review":
        app_header("Screenshots", large=False)
        d.text((x0 + pad, y0 + int(110 * scale)), "7 of 20", fill=MUTED, font=small_font)
        rounded(d, (x0 + int(110 * scale), y0 + int(116 * scale), x1 - pad, y0 + int(130 * scale)), int(8 * scale), fill=(225, 219, 211))
        rounded(d, (x0 + int(110 * scale), y0 + int(116 * scale), x0 + int(285 * scale), y0 + int(130 * scale)), int(8 * scale), fill=ACCENT)
        paste_round(base, synthetic_photo(12, (w - int(100 * scale), int(535 * scale))).convert("RGBA"), (x0 + int(50 * scale), y0 + int(170 * scale)), int(34 * scale))
        d.text((x0 + pad, y1 - int(86 * scale)), "x", fill=RED, font=font(int(48 * scale)))
        d.text((x1 - pad - int(45 * scale), y1 - int(86 * scale)), "✓", fill=GREEN, font=font(int(48 * scale)))
        d.text((x0 + w // 2 - int(52 * scale), y1 - int(69 * scale)), "Undo", fill=MUTED, font=small_font)
    elif screen == "similar":
        app_header("Similar", large=False)
        d.text((x0 + pad, y0 + int(112 * scale)), "2 kept · 3 marked · 1 year ago", fill=MUTED, font=small_font)
        photo_w = (w - int(90 * scale)) // 2
        for i in range(2):
            px = x0 + pad + i * (photo_w + int(20 * scale))
            paste_round(base, synthetic_photo(20 + i, (photo_w, int(445 * scale))).convert("RGBA"), (px, y0 + int(170 * scale)), int(28 * scale))
            d.rounded_rectangle(
                (px, y0 + int(170 * scale), px + photo_w, y0 + int(615 * scale)),
                radius=int(28 * scale),
                outline=ACCENT if i == 0 else GREEN,
                width=int(5 * scale),
            )
            d.text((px + int(18 * scale), y0 + int(586 * scale)), "Keep", fill=(255, 255, 255), font=small_font)
        rounded(d, (x0 + pad, y1 - int(92 * scale), x1 - pad, y1 - int(35 * scale)), int(19 * scale), fill=ACCENT)
        d.text((x0 + int(175 * scale), y1 - int(79 * scale)), "Mark 3 Extras", fill=(255, 255, 255), font=body_font)
    elif screen == "details":
        app_header("Photo Details", large=False)
        paste_round(base, synthetic_photo(31, (w - int(88 * scale), int(290 * scale))).convert("RGBA"), (x0 + pad, y0 + int(130 * scale)), int(26 * scale))
        rows = [("Date", "May 8, 2025"), ("Age", "1 year ago"), ("File size", "4.8 MB"), ("Resolution", "4032 x 3024"), ("Type", "Live Photo")]
        cy = y0 + int(470 * scale)
        for label, value in rows:
            rounded(d, (x0 + pad, cy, x1 - pad, cy + int(64 * scale)), int(14 * scale), fill=CARD)
            d.text((x0 + pad + int(18 * scale), cy + int(18 * scale)), label, fill=INK, font=small_font)
            tw = d.textbbox((0, 0), value, font=small_font)[2]
            d.text((x1 - pad - int(18 * scale) - tw, cy + int(18 * scale)), value, fill=MUTED, font=small_font)
            cy += int(76 * scale)
    elif screen == "summary":
        app_header("Review complete", large=False)
        d.text((x0 + pad, y0 + int(112 * scale)), "15 kept · 5 marked", fill=MUTED, font=body_font)
        cy = y0 + int(172 * scale)
        for group in range(2):
            rounded(d, (x0 + pad, cy, x1 - pad, cy + int(190 * scale)), int(20 * scale), fill=CARD)
            d.text((x0 + pad + int(20 * scale), cy + int(18 * scale)), "1 kept · 2 marked", fill=MUTED, font=small_font)
            for i in range(3):
                paste_round(base, synthetic_photo(45 + group * 4 + i, (int(82 * scale), int(82 * scale))).convert("RGBA"), (x0 + pad + int(20 * scale) + i * int(95 * scale), cy + int(70 * scale)), int(12 * scale))
            cy += int(210 * scale)
        rounded(d, (x0 + pad, y1 - int(92 * scale), x1 - pad, y1 - int(35 * scale)), int(19 * scale), fill=RED)
        d.text((x0 + int(138 * scale), y1 - int(79 * scale)), "Delete 5 Photos", fill=(255, 255, 255), font=body_font)
    elif screen == "settings":
        app_header("Settings", large=False)
        sections = [("Review Size", "20"), ("Lifetime Stats", "184 deleted"), ("Space freed", "1.8 GB")]
        cy = y0 + int(140 * scale)
        for label, value in sections:
            rounded(d, (x0 + pad, cy, x1 - pad, cy + int(86 * scale)), int(18 * scale), fill=CARD)
            d.text((x0 + pad + int(20 * scale), cy + int(27 * scale)), label, fill=INK, font=body_font)
            tw = d.textbbox((0, 0), value, font=body_font)[2]
            d.text((x1 - pad - int(20 * scale) - tw, cy + int(27 * scale)), value, fill=MUTED, font=body_font)
            cy += int(105 * scale)


def compose(device: str, slide: dict, index: int):
    w, h = DEVICES[device]
    img = gradient((w, h), WARM, (242, 235, 225))
    d = ImageDraw.Draw(img, "RGBA")
    draw_background(d, w, h)
    scale = w / 1290

    icon_size = int(118 * scale)
    paste_round(img, load_icon(icon_size), (int(86 * scale), int(116 * scale)), int(28 * scale))
    d.text((int(222 * scale), int(136 * scale)), "SnipSnaps", fill=INK, font=font(int(38 * scale)))
    d.text((int(222 * scale), int(182 * scale)), "Photo cleanup that feels calm.", fill=MUTED, font=font(int(22 * scale)))

    if device.startswith("iphone"):
        text_x, text_y = int(86 * scale), int(365 * scale)
        draw_slide_text(d, slide, text_x, text_y, int(1080 * scale), scale)
        frame = app_frame(
            (int(590 * scale), int(1165 * scale)),
            slide["screen"],
            scale,
            raw_capture(device, index, slide["screen"]),
            "phone",
        )
        shadow = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow, "RGBA")
        sd.rounded_rectangle((0, 0, frame.width, frame.height), radius=int(65 * scale), fill=(0, 0, 0, 54))
        shadow = shadow.filter(ImageFilter.GaussianBlur(int(28 * scale)))
        fx = (w - frame.width) // 2
        fy = int(1320 * scale)
        img.paste(shadow, (fx, fy + int(32 * scale)), shadow)
        img.paste(frame, (fx, fy), frame)
    else:
        text_x, text_y = int(120 * scale), int(340 * scale)
        draw_slide_text(d, slide, text_x, text_y, int(850 * scale), scale * 0.82)
        frame = app_frame(
            (860, 1148),
            slide["screen"],
            1.0,
            raw_capture(device, index, slide["screen"]),
            "tablet",
        )
        fx = w - frame.width - int(150 * scale)
        fy = int(800 * scale)
        shadow = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow, "RGBA")
        sd.rounded_rectangle((0, 0, frame.width, frame.height), radius=78, fill=(0, 0, 0, 52))
        shadow = shadow.filter(ImageFilter.GaussianBlur(34))
        img.paste(shadow, (fx, fy + int(34 * scale)), shadow)
        img.paste(frame, (fx, fy), frame)

        for i in range(7):
            x = int(120 * scale + (i % 3) * 185 * scale)
            y = int(1240 * scale + (i // 3) * 175 * scale)
            paste_round(img, synthetic_photo(70 + index * 7 + i, (int(132 * scale), int(132 * scale))).convert("RGBA"), (x, y), int(20 * scale))

    img = img.convert("RGB")
    out_dir = OUT / device
    out_dir.mkdir(parents=True, exist_ok=True)
    img.save(out_dir / f"{index:02d}-{slide['screen']}.png", optimize=True)


def main():
    for device in DEVICES:
        for i, slide in enumerate(SLIDES, 1):
            compose(device, slide, i)
    print(f"Generated {len(SLIDES) * len(DEVICES)} screenshots in {OUT}")


if __name__ == "__main__":
    main()
