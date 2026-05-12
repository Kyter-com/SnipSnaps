from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "output"
RAW = Path(__file__).resolve().parent / "raw"
ICON = ROOT / "SnipSnaps/Assets.xcassets/AppIcon.appiconset/Frame 11.png"

# Palette pulled from the app icon: deep navy frame, electric blue body,
# silvery ice-blue highlight in the center sparkle.
DEEP = (6, 10, 26)
MID = (14, 24, 56)
NIGHT = (20, 36, 84)
GLOW = (44, 104, 214)
ACCENT = (84, 170, 255)
ICE = (180, 218, 255)
SILVER = (214, 228, 250)
DIM = (158, 178, 214)
WHITE = (255, 255, 255)

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


def rounded(draw, xy, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def paste_round(base: Image.Image, image: Image.Image, xy, radius: int):
    mask = Image.new("L", image.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    base.paste(image, xy, mask)


def fit_image(image: Image.Image, size, fill=None) -> Image.Image:
    image = image.convert("RGB")
    if fill is None:
        # Sample the top-left edge of the screenshot so the letterbox area
        # blends with the iOS status-bar background instead of showing a
        # cream band that doesn't exist on the real device.
        fill = image.getpixel((6, 6))
    canvas = Image.new("RGB", size, fill)
    ratio = min(size[0] / image.width, size[1] / image.height)
    resized = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return canvas


def gradient(size, top, bottom) -> Image.Image:
    img = Image.new("RGB", size, top)
    pix = img.load()
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(size[0]):
            pix[x, y] = color
    return img


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


def radial_glow(size, center, radius, color, alpha=160) -> Image.Image:
    """Soft circular bloom built from concentric translucent ellipses."""
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(glow, "RGBA")
    layers = 28
    for i in range(layers, 0, -1):
        t = i / layers
        a = int(alpha * (1 - t) ** 2.2)
        r = int(radius * t)
        d.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=(*color, a))
    return glow.filter(ImageFilter.GaussianBlur(radius=radius * 0.05))


def sparkle(size: int, color=ICE, alpha=220) -> Image.Image:
    """Four-point sparkle echoing the icon's center mark."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = size / 2
    h = size / 2
    waist = h * 0.18
    d.polygon([(cx, cy - h), (cx + waist, cy), (cx, cy + h), (cx - waist, cy)], fill=(*color, alpha))
    d.polygon([(cx - h, cy), (cx, cy - waist), (cx + h, cy), (cx, cy + waist)], fill=(*color, alpha))
    img = img.filter(ImageFilter.GaussianBlur(radius=max(1, size * 0.02)))
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo, "RGBA")
    hr = h * 0.55
    hd.ellipse((cx - hr, cy - hr, cx + hr, cy + hr), fill=(*color, max(20, alpha // 8)))
    halo = halo.filter(ImageFilter.GaussianBlur(radius=size * 0.18))
    return Image.alpha_composite(halo, img)


def glass_panel(size, radius, fill=(255, 255, 255, 28), border_alpha=110) -> Image.Image:
    """Liquid-glass translucent panel with hairline highlight and top sheen."""
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((0, 0, w, h), radius=radius, fill=fill)
    sheen = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen, "RGBA")
    sd.rounded_rectangle((0, 0, w, int(h * 0.55)), radius=radius, fill=(255, 255, 255, 22))
    img = Image.alpha_composite(img, sheen)
    border = Image.new("RGBA", size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(border, "RGBA")
    bd.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, outline=(255, 255, 255, border_alpha), width=2)
    bd.rounded_rectangle((1, 1, w - 2, h - 2), radius=radius - 1, outline=(255, 255, 255, max(30, border_alpha // 3)), width=1)
    return Image.alpha_composite(img, border)


def background(w: int, h: int) -> Image.Image:
    """Deep midnight backdrop with aurora glows and floating sparkles."""
    base = gradient((w, h), DEEP, MID).convert("RGBA")
    upper = gradient((w, h), (10, 18, 44), (12, 22, 52)).convert("RGBA")
    base = Image.alpha_composite(base, upper)

    g1 = radial_glow((w, h), (int(w * 0.18), int(h * 0.04)), int(h * 0.55), GLOW, alpha=150)
    base = Image.alpha_composite(base, g1)
    g2 = radial_glow((w, h), (int(w * 1.02), int(h * 0.32)), int(h * 0.45), ACCENT, alpha=110)
    base = Image.alpha_composite(base, g2)
    g3 = radial_glow((w, h), (int(w * 0.5), int(h * 1.05)), int(h * 0.55), GLOW, alpha=120)
    base = Image.alpha_composite(base, g3)

    grain = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grain, "RGBA")
    random.seed(7)
    for _ in range(int(w * h / 9000)):
        x = random.randint(0, w - 1)
        y = random.randint(0, h - 1)
        a = random.randint(6, 18)
        gd.point((x, y), fill=(255, 255, 255, a))
    base = Image.alpha_composite(base, grain)

    random.seed(101)
    for _ in range(22):
        sx = random.randint(int(w * 0.02), int(w * 0.98))
        sy = random.randint(int(h * 0.02), int(h * 0.98))
        ssize = random.randint(int(w * 0.012), int(w * 0.04))
        alpha = random.randint(80, 200)
        color = ICE if random.random() < 0.7 else ACCENT
        sp = sparkle(ssize, color, alpha)
        base.alpha_composite(sp, (sx - ssize // 2, sy - ssize // 2))

    return base


def load_icon(size: int) -> Image.Image:
    return Image.open(ICON).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def draw_kicker_chip(base: Image.Image, text: str, xy, scale: float):
    fnt = font(int(28 * scale))
    pad_x = int(26 * scale)
    pad_y = int(13 * scale)
    tmp = ImageDraw.Draw(base, "RGBA")
    tw = tmp.textbbox((0, 0), text, font=fnt)[2]
    th = tmp.textbbox((0, 0), text, font=fnt)[3]
    chip_w = tw + pad_x * 2
    chip_h = th + pad_y * 2
    chip = glass_panel((chip_w, chip_h), radius=chip_h // 2, fill=(255, 255, 255, 36), border_alpha=140)
    base.alpha_composite(chip, xy)
    cd = ImageDraw.Draw(base, "RGBA")
    cd.text((xy[0] + pad_x, xy[1] + pad_y - int(2 * scale)), text, fill=ICE, font=fnt)
    dot_r = int(6 * scale)
    cd.ellipse(
        (
            xy[0] + chip_w - pad_x - dot_r * 2 - tw - int(8 * scale),
            xy[1] + chip_h // 2 - dot_r,
            xy[0] + chip_w - pad_x - tw - int(8 * scale),
            xy[1] + chip_h // 2 + dot_r,
        ),
        fill=ACCENT,
    )
    return chip_h


def draw_slide_text(base: Image.Image, slide, x: int, y: int, max_width: int, scale: float):
    chip_h = draw_kicker_chip(base, slide["kicker"], (x, y), scale)
    y += chip_h + int(34 * scale)
    title_font = font(int(94 * scale))
    subtitle_font = font(int(34 * scale))
    title_line_height = int(108 * scale)
    subtitle_line_height = int(48 * scale)
    d = ImageDraw.Draw(base, "RGBA")
    title_lines = wrapped_lines(d, slide["title"], max_width, title_font)[:2]
    for index, line in enumerate(title_lines):
        d.text((x + 2, y + index * title_line_height + 2), line, fill=(0, 0, 0, 110), font=title_font)
        d.text((x, y + index * title_line_height), line, fill=WHITE, font=title_font)
    y += title_line_height * 2 + int(20 * scale)
    subtitle_lines = wrapped_lines(d, slide["subtitle"], max_width, subtitle_font)[:2]
    for index, line in enumerate(subtitle_lines):
        d.text((x, y + index * subtitle_line_height), line, fill=DIM, font=subtitle_font)


def raw_capture(device: str, index: int, screen: str):
    path = RAW / device / f"{index:02d}-{screen}.png"
    if path.exists():
        return Image.open(path).convert("RGB")
    return None


def app_frame(size, scale: float, screenshot, style: str = "phone") -> Image.Image:
    """iOS device frame with a glassy reflective rim and inner screen."""
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    outer_radius = int((78 if style == "phone" else 52) * scale)
    inner_radius = int((60 if style == "phone" else 38) * scale)
    inset = int((22 if style == "phone" else 20) * scale)

    rounded(d, (0, 0, w, h), outer_radius, fill=(10, 12, 22))
    rounded(d, (1, 1, w - 1, h - 1), outer_radius - 1, outline=(255, 255, 255, 90), width=max(2, int(3 * scale)))
    rounded(d, (3, 3, w - 3, h - 3), outer_radius - 3, outline=(255, 255, 255, 28), width=1)

    rim = Image.new("RGBA", size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim, "RGBA")
    rd.rounded_rectangle(
        (int(6 * scale), int(6 * scale), w - int(6 * scale), int(h * 0.18)),
        radius=outer_radius,
        fill=(255, 255, 255, 24),
    )
    rim = rim.filter(ImageFilter.GaussianBlur(int(6 * scale)))
    img = Image.alpha_composite(img, rim)

    screen_box = (inset, inset, w - inset, h - inset)
    if screenshot is not None:
        screen_size = (screen_box[2] - screen_box[0], screen_box[3] - screen_box[1])
        paste_round(img, fit_image(screenshot, screen_size).convert("RGBA"), (screen_box[0], screen_box[1]), inner_radius)
    else:
        rounded(ImageDraw.Draw(img, "RGBA"), screen_box, inner_radius, fill=(246, 244, 239))

    return img


def device_shadow(size, radius: int, scale: float) -> Image.Image:
    w, h = size
    pad = int(140 * scale)
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sd = ImageDraw.Draw(canvas, "RGBA")
    sd.rounded_rectangle((pad, pad, pad + w, pad + h), radius=radius, fill=(0, 0, 0, 150))
    return canvas.filter(ImageFilter.GaussianBlur(int(48 * scale))), pad


def device_glow(size, radius: int, scale: float, color=GLOW) -> Image.Image:
    w, h = size
    pad = int(180 * scale)
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sd = ImageDraw.Draw(canvas, "RGBA")
    sd.rounded_rectangle((pad, pad, pad + w, pad + h), radius=radius, fill=(*color, 130))
    return canvas.filter(ImageFilter.GaussianBlur(int(80 * scale))), pad


def draw_top_brand(base: Image.Image, scale: float, w: int):
    icon_size = int(118 * scale)
    icon_x = int(86 * scale)
    icon_y = int(110 * scale)
    icon = load_icon(icon_size)
    base.alpha_composite(icon, (icon_x, icon_y))
    d = ImageDraw.Draw(base, "RGBA")
    text_x = icon_x + icon_size + int(26 * scale)
    d.text((text_x, icon_y + int(22 * scale)), "SnipSnaps", fill=WHITE, font=font(int(46 * scale)))
    d.text((text_x, icon_y + int(76 * scale)), "Photo cleanup that feels calm.", fill=DIM, font=font(int(24 * scale)))


def feature_chip(label: str, scale: float, accent_color=ACCENT) -> Image.Image:
    fnt = font(int(28 * scale))
    pad_x = int(34 * scale)
    pad_y = int(20 * scale)
    tmp = ImageDraw.Draw(Image.new("RGBA", (10, 10)), "RGBA")
    tw = tmp.textbbox((0, 0), label, font=fnt)[2]
    th = tmp.textbbox((0, 0), label, font=fnt)[3]
    dot = int(14 * scale)
    chip_w = tw + pad_x * 2 + dot + int(14 * scale)
    chip_h = th + pad_y * 2
    chip = glass_panel((chip_w, chip_h), radius=chip_h // 2, fill=(255, 255, 255, 30), border_alpha=120)
    cd = ImageDraw.Draw(chip, "RGBA")
    cd.ellipse((pad_x, chip_h // 2 - dot // 2, pad_x + dot, chip_h // 2 + dot // 2), fill=accent_color)
    cd.text((pad_x + dot + int(14 * scale), pad_y - int(2 * scale)), label, fill=WHITE, font=fnt)
    return chip


def compose(device: str, slide, index: int):
    w, h = DEVICES[device]
    img = background(w, h)
    scale = w / 1290

    draw_top_brand(img, scale, w)

    if device.startswith("iphone"):
        text_x = int(86 * scale)
        text_y = int(380 * scale)
        draw_slide_text(img, slide, text_x, text_y, int(1100 * scale), scale)

        frame_w = int(914 * scale)
        frame_h = int(1986 * scale)  # ~iPhone 0.46 aspect
        frame = app_frame((frame_w, frame_h), scale, raw_capture(device, index, slide["screen"]), "phone")
        fx = (w - frame_w) // 2
        fy = int(960 * scale)

        glow_layer, gpad = device_glow((frame_w, frame_h), int(78 * scale), scale, GLOW)
        img.alpha_composite(glow_layer, (fx - gpad, fy - gpad + int(40 * scale)))
        shadow_layer, spad = device_shadow((frame_w, frame_h), int(78 * scale), scale)
        img.alpha_composite(shadow_layer, (fx - spad, fy - spad + int(50 * scale)))

        img.alpha_composite(frame, (fx, fy))
    else:
        # iPad: stacked centered composition, larger device frame.
        ipad_scale = 1.4
        text_x = 160
        text_y = 380
        draw_slide_text(img, slide, text_x, text_y, w - 320, ipad_scale)

        frame_w = 1356
        frame_h = 1808  # ~0.75 iPad aspect
        frame = app_frame((frame_w, frame_h), 1.0, raw_capture(device, index, slide["screen"]), "tablet")
        fx = (w - frame_w) // 2
        fy = 930

        glow_layer, gpad = device_glow((frame_w, frame_h), 60, 1.0, GLOW)
        img.alpha_composite(glow_layer, (fx - gpad, fy - gpad + 60))
        shadow_layer, spad = device_shadow((frame_w, frame_h), 60, 1.0)
        img.alpha_composite(shadow_layer, (fx - spad, fy - spad + 80))
        img.alpha_composite(frame, (fx, fy))

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
